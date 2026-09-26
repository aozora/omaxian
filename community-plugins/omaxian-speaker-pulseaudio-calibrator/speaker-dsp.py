#!/usr/bin/python3 -sB
"""PulseAudio userspace DSP graph for omaxian-speaker-pulseaudio-calibrator.

Replaces upstream's PipeWire filter-chain client. Apps play into a null sink;
this process reads the monitor, applies high-pass / peaking EQ / balance, a
soft ceiling limiter, and writes to the physical sink.

LV2 plugins (LSP limiter / loudness, bankstown) are intentionally not hosted
here: Debian's python3-lilv loads the wrong soname, and LSP plugins require a
full LV2 host (URID map + Atom ports) or they segfault on run. The fitted
biquads carry the calibration; the soft limiter enforces the -1 dBFS ceiling.

Control is a length-prefixed JSON request/response Unix socket (0600) under
$XDG_RUNTIME_DIR. Loudness-tracker and speaker-calibrate talk to that socket
instead of upstream live-control tooling.
"""

from __future__ import annotations

import json
import math
import os
import signal
import socket
import struct
import subprocess
import sys
import threading
import time
from pathlib import Path

PLUGIN_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(PLUGIN_DIR))

RATE = 48000
CHANNELS = 2
# Large blocks + latency absorb Pulse/Python scheduling jitter (crackle).
FRAMES = 4096
BYTES_PER_FRAME = CHANNELS * 2  # s16le
LATENCY_MSEC = 200
PROCESS_TIME_MSEC = 40
MAX_MSG = 1 << 20
# Match the profile's limiter_ceiling_dbfs / safety.limiter_ceiling_dbfs.
LIMITER_CEILING_DBFS = -1.0

RUNTIME = Path(
    os.environ.get("XDG_RUNTIME_DIR")
    or f"/run/user/{os.getuid()}"
) / "omaxian-speaker-pulseaudio-calibrator"
SOCKET_PATH = RUNTIME / "dsp.sock"
PID_PATH = RUNTIME / "dsp.pid"
LOG_PATH = RUNTIME / "dsp.log"


def rbj_peaking(freq, q, gain_db, rate=RATE):
  A = 10.0 ** (gain_db / 40.0)
  w0 = 2.0 * math.pi * max(1.0, freq) / rate
  alpha = math.sin(w0) / (2.0 * max(0.05, q))
  b0 = 1 + alpha * A
  b1 = -2 * math.cos(w0)
  b2 = 1 - alpha * A
  a0 = 1 + alpha / A
  a1 = -2 * math.cos(w0)
  a2 = 1 - alpha / A
  return [b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0]


def rbj_highpass(freq, q, rate=RATE):
  w0 = 2.0 * math.pi * max(1.0, freq) / rate
  alpha = math.sin(w0) / (2.0 * max(0.05, q))
  cosw = math.cos(w0)
  b0 = (1 + cosw) / 2
  b1 = -(1 + cosw)
  b2 = (1 + cosw) / 2
  a0 = 1 + alpha
  a1 = -2 * cosw
  a2 = 1 - alpha
  return [b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0]


class Biquad:
  __slots__ = ("b0", "b1", "b2", "a1", "a2")

  def __init__(self, coeffs):
    self.b0, self.b1, self.b2, self.a1, self.a2 = coeffs

  def sos_row(self):
    return [self.b0, self.b1, self.b2, 1.0, self.a1, self.a2]


class SoftLimiter:
  """Ceiling at LIMITER_CEILING_DBFS with input makeup (g_in).

  Soft knee (tanh) avoids the hard-clip crackle of a brick-wall limiter.
  """

  def __init__(self, ceiling_dbfs=LIMITER_CEILING_DBFS):
    self.ceiling = 10.0 ** (float(ceiling_dbfs) / 20.0)
    self.g_in = 1.0

  def set_controls(self, mapping):
    if "limiter:g_in" in mapping:
      self.g_in = max(0.0, float(mapping["limiter:g_in"]))
    elif "g_in" in mapping:
      self.g_in = max(0.0, float(mapping["g_in"]))

  def process(self, left, right):
    import numpy as np
    g = self.g_in
    c = self.ceiling
    # Drive into a gentle tanh so peaks fold instead of square-clip.
    scale = 1.5
    left = c * np.tanh((left * g) * (scale / c)) / np.tanh(scale)
    right = c * np.tanh((right * g) * (scale / c)) / np.tanh(scale)
    return left.astype(np.float32, copy=False), right.astype(np.float32, copy=False)


class ChannelChain:
  """Cascaded biquads via scipy sosfilt — real-time safe, keeps zi state."""

  __slots__ = ("sos", "zi", "gain_mult", "gain_add")

  def __init__(self):
    self.sos = None
    self.zi = None
    self.gain_mult = 1.0
    self.gain_add = 0.0

  def configure(self, sections, gain_mult=1.0, gain_add=0.0):
    import numpy as np
    from scipy import signal
    self.gain_mult = float(gain_mult)
    self.gain_add = float(gain_add)
    if not sections:
      self.sos = None
      self.zi = None
      return
    sos = np.asarray([row.sos_row() for row in sections], dtype=np.float64)
    # Keep filter memory across control rebuilds when shape matches.
    if self.sos is not None and self.sos.shape == sos.shape:
      self.sos = sos
    else:
      self.sos = sos
      self.zi = signal.sosfilt_zi(sos) * 0.0

  def process(self, samples):
    import numpy as np
    from scipy import signal
    x = np.asarray(samples, dtype=np.float64)
    if self.sos is not None:
      x, self.zi = signal.sosfilt(self.sos, x, zi=self.zi)
    if self.gain_mult != 1.0 or self.gain_add != 0.0:
      x = x * self.gain_mult + self.gain_add
    return x.astype(np.float32, copy=False)


class Graph:
  def __init__(self):
    self.lock = threading.Lock()
    self.controls = {}
    self.left = ChannelChain()
    self.right = ChannelChain()
    self.limiter = SoftLimiter()
    self.bypass = False

  def apply_controls(self, controls):
    with self.lock:
      self.controls = {str(k): float(v) for k, v in controls.items()}
      self._rebuild_biquads()
      self.limiter.set_controls(self.controls)

  def _rebuild_biquads(self):
    for side, chain in (("l", self.left), ("r", self.right)):
      sections = []
      for index in (1, 2):
        f = self.controls.get(f"hp{index}_{side}:Freq")
        q = self.controls.get(f"hp{index}_{side}:Q", 0.707)
        if f is not None and f > 0:
          sections.append(Biquad(rbj_highpass(f, q)))
      for slot in range(1, 13):
        f = self.controls.get(f"p{slot}_{side}:Freq")
        g = self.controls.get(f"p{slot}_{side}:Gain", 0.0)
        q = self.controls.get(f"p{slot}_{side}:Q", 1.0)
        if f is not None and abs(g) > 1e-6:
          sections.append(Biquad(rbj_peaking(f, q, g)))
      mult = self.controls.get(f"bal_{side}:Mult", 1.0)
      add = self.controls.get(f"bal_{side}:Add", 0.0)
      chain.configure(sections, mult, add)

  def process_block(self, interleaved_f32):
    import numpy as np
    with self.lock:
      left = interleaved_f32[0::2]
      right = interleaved_f32[1::2]
      left = self.left.process(left)
      right = self.right.process(right)
      left, right = self.limiter.process(left, right)
      out = np.empty(left.size * 2, dtype=np.float32)
      out[0::2] = left
      out[1::2] = right
      return out


class Daemon:
  def __init__(self, monitor, physical):
    self.monitor = monitor
    self.physical = physical
    self.graph = Graph()
    self.running = True
    self.parec = None
    self.pacat = None

  def stop(self, *_):
    self.running = False

  def handle(self, request):
    cmd = request.get("cmd")
    if cmd == "ping":
      return {"ok": True}
    if cmd == "shutdown":
      self.running = False
      return {"ok": True}
    if cmd == "get_controls":
      with self.graph.lock:
        return {"ok": True, "controls": dict(self.graph.controls)}
    if cmd == "set_controls":
      controls = request.get("controls") or {}
      if not isinstance(controls, dict):
        return {"ok": False, "error": "controls must be an object"}
      self.graph.apply_controls(controls)
      return {"ok": True}
    if cmd == "set_loudness":
      controls = request.get("controls") or {}
      with self.graph.lock:
        merged = dict(self.graph.controls)
        merged.update({str(k): float(v) for k, v in controls.items()})
      self.graph.apply_controls(merged)
      return {"ok": True}
    return {"ok": False, "error": f"unknown cmd {cmd}"}

  def serve_socket(self):
    RUNTIME.mkdir(mode=0o700, parents=True, exist_ok=True)
    if SOCKET_PATH.exists():
      SOCKET_PATH.unlink()
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.bind(str(SOCKET_PATH))
    os.chmod(SOCKET_PATH, 0o600)
    sock.listen(8)
    sock.settimeout(0.5)
    while self.running:
      try:
        conn, _ = sock.accept()
      except socket.timeout:
        continue
      except OSError:
        break
      threading.Thread(target=self._client, args=(conn,), daemon=True).start()
    sock.close()
    try:
      SOCKET_PATH.unlink()
    except OSError:
      pass

  def _client(self, conn):
    try:
      header = _recv_exact(conn, 4)
      if not header:
        return
      (length,) = struct.unpack("!I", header)
      if length > MAX_MSG:
        return
      raw = _recv_exact(conn, length)
      request = json.loads(raw.decode("utf-8"))
      response = self.handle(request)
      payload = json.dumps(response).encode("utf-8")
      conn.sendall(struct.pack("!I", len(payload)) + payload)
    except Exception as error:
      try:
        payload = json.dumps({"ok": False, "error": str(error)}).encode("utf-8")
        conn.sendall(struct.pack("!I", len(payload)) + payload)
      except OSError:
        pass
    finally:
      conn.close()

  def audio_loop(self):
    import numpy as np
    # Unique Pulse application names so module-stream-restore and move_apps
    # do not park our playback on the null sink (silent feedback loop).
    env = os.environ.copy()
    env.pop("PULSE_SINK", None)
    env.pop("PULSE_SOURCE", None)
    env["PULSE_LATENCY_MSEC"] = str(LATENCY_MSEC)
    env["PULSE_PROP_application.name"] = "omaxian-speaker-dsp"
    env["PULSE_PROP_media.role"] = "filter"
    self.parec = subprocess.Popen(
      [
        "/usr/bin/parec",
        "--raw",
        "--format=s16le",
        f"--rate={RATE}",
        f"--channels={CHANNELS}",
        f"--device={self.monitor}",
        f"--latency-msec={LATENCY_MSEC}",
        f"--process-time-msec={PROCESS_TIME_MSEC}",
        "--client-name=omaxian-speaker-dsp-capture",
        "--property=application.name=omaxian-speaker-dsp-capture",
      ],
      stdout=subprocess.PIPE,
      stderr=subprocess.DEVNULL,
      env=env,
      bufsize=0,
    )
    self.pacat = subprocess.Popen(
      [
        "/usr/bin/pacat",
        "--playback",
        "--raw",
        "--format=s16le",
        f"--rate={RATE}",
        f"--channels={CHANNELS}",
        f"--device={self.physical}",
        f"--latency-msec={LATENCY_MSEC}",
        f"--process-time-msec={PROCESS_TIME_MSEC}",
        "--client-name=omaxian-speaker-dsp",
        "--property=application.name=omaxian-speaker-dsp",
        "--property=media.role=filter",
      ],
      stdin=subprocess.PIPE,
      stderr=subprocess.DEVNULL,
      env=env,
      # Let the OS pipe buffer absorb write bursts; do not flush every block.
      bufsize=FRAMES * BYTES_PER_FRAME * 4,
    )
    self._pin_playback_to_physical()
    chunk = FRAMES * BYTES_PER_FRAME
    # Pre-roll silence so Pulse starts playback with a full cushion instead of
    # draining the ALSA ~7 ms hardware buffer on the first real audio.
    preroll = b"\x00" * (RATE * BYTES_PER_FRAME * LATENCY_MSEC // 1000)
    try:
      self.pacat.stdin.write(preroll)
      self.pacat.stdin.flush()
    except BrokenPipeError:
      return
    pending = bytearray()
    scale = np.float32(1.0 / 32768.0)
    try:
      while self.running:
        data = self.parec.stdout.read(chunk)
        if not data:
          if self.parec.poll() is not None:
            break
          time.sleep(0.005)
          continue
        pending.extend(data)
        while len(pending) >= chunk:
          block = bytes(pending[:chunk])
          del pending[:chunk]
          samples = np.frombuffer(block, dtype=np.int16).astype(np.float32)
          samples *= scale
          out = self.graph.process_block(samples)
          pcm = (np.clip(out, -1.0, 1.0) * 32767.0).astype(np.int16).tobytes()
          try:
            self.pacat.stdin.write(pcm)
          except BrokenPipeError:
            self.running = False
            break
    finally:
      for proc in (self.parec, self.pacat):
        if proc and proc.poll() is None:
          proc.terminate()
          try:
            proc.wait(timeout=2)
          except subprocess.TimeoutExpired:
            proc.kill()

  def _pin_playback_to_physical(self):
    """Move our pacat onto the physical sink if restore/move_apps stole it."""
    for _ in range(40):
      try:
        listing = subprocess.check_output(
          ["/usr/bin/pactl", "list", "short", "sink-inputs"],
          text=True,
          stderr=subprocess.DEVNULL,
        )
        sinks = {}
        for line in subprocess.check_output(
          ["/usr/bin/pactl", "list", "short", "sinks"],
          text=True,
          stderr=subprocess.DEVNULL,
        ).splitlines():
          parts = line.split()
          if len(parts) >= 2:
            sinks[parts[0]] = parts[1]
        for line in listing.splitlines():
          # index sink client ...  — application name is not here; use long list
          pass
        # Prefer JSON when it works; fall back to moving by matching pacat cmdline.
        raw = subprocess.check_output(
          ["/usr/bin/pactl", "-f", "json", "list", "sink-inputs"],
          text=True,
          stderr=subprocess.DEVNULL,
        )
        import json as _json
        for stream in _json.loads(raw or "[]"):
          props = stream.get("properties") or {}
          if props.get("application.name") != "omaxian-speaker-dsp":
            continue
          sink = stream.get("sink")
          sink_name = sinks.get(str(sink), sink)
          if sink_name != self.physical:
            subprocess.run(
              [
                "/usr/bin/pactl", "move-sink-input",
                str(stream["index"]), self.physical,
              ],
              check=False,
              stdout=subprocess.DEVNULL,
              stderr=subprocess.DEVNULL,
            )
          return
      except (subprocess.CalledProcessError, ValueError, OSError, TypeError):
        pass
      time.sleep(0.05)
def _recv_exact(conn, n):
  buf = b""
  while len(buf) < n:
    chunk = conn.recv(n - len(buf))
    if not chunk:
      return None
    buf += chunk
  return buf


def write_pid():
  RUNTIME.mkdir(mode=0o700, parents=True, exist_ok=True)
  PID_PATH.write_text(f"{os.getpid()}\n")


def main():
  if len(sys.argv) < 3:
    print("usage: speaker-dsp.py <monitor_source> <physical_sink>", file=sys.stderr)
    sys.exit(2)
  monitor, physical = sys.argv[1], sys.argv[2]
  RUNTIME.mkdir(mode=0o700, parents=True, exist_ok=True)
  try:
    log = open(LOG_PATH, "w", buffering=1)
    sys.stderr = log
  except OSError:
    pass
  daemon = Daemon(monitor, physical)
  signal.signal(signal.SIGTERM, daemon.stop)
  signal.signal(signal.SIGINT, daemon.stop)
  write_pid()
  threading.Thread(target=daemon.serve_socket, daemon=True).start()
  try:
    daemon.audio_loop()
  finally:
    daemon.running = False
    try:
      PID_PATH.unlink()
    except OSError:
      pass


if __name__ == "__main__":
  main()

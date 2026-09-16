#!/usr/bin/python3 -s
"""PulseAudio userspace DSP graph for omaxian.speaker-calibrator.

Replaces upstream's PipeWire filter-chain client. Apps play into a null sink;
this process reads the monitor, applies the same section order as upstream
(optional bankstown → loudness compensator → biquads → limiter), and writes
to the physical sink.

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
FRAMES = 1024
BYTES_PER_FRAME = CHANNELS * 2  # s16le
MAX_MSG = 1 << 20

LOUDNESS_URI = "http://lsp-plug.in/plugins/lv2/loud_comp_stereo"
LIMITER_URI = "http://lsp-plug.in/plugins/lv2/limiter_stereo"
BASS_URI = "https://chadmed.au/bankstown"

RUNTIME = Path(
    os.environ.get("XDG_RUNTIME_DIR")
    or f"/run/user/{os.getuid()}"
) / "omaxian-speaker-calibrator"
SOCKET_PATH = RUNTIME / "dsp.sock"
PID_PATH = RUNTIME / "dsp.pid"


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
  __slots__ = ("b0", "b1", "b2", "a1", "a2", "z1", "z2")

  def __init__(self, coeffs):
    self.b0, self.b1, self.b2, self.a1, self.a2 = coeffs
    self.z1 = 0.0
    self.z2 = 0.0

  def process(self, x):
    y = self.b0 * x + self.z1
    self.z1 = self.b1 * x - self.a1 * y + self.z2
    self.z2 = self.b2 * x - self.a2 * y
    return y

  def reset(self):
    self.z1 = self.z2 = 0.0


class Lv2Stage:
  """Thin lilv wrapper; absent plugins become a passthrough."""

  def __init__(self, uri, rate=RATE):
    self.uri = uri
    self.ok = False
    self.instance = None
    self.in_l = self.in_r = self.out_l = self.out_r = None
    self.controls = {}
    self._ports = {}
    try:
      import lilv
      import numpy as np
    except ImportError:
      return
    self._np = np
    world = lilv.World()
    world.load_all()
    plugin = world.get_plugin_by_uri(world.new_uri(uri))
    if plugin is None:
      return
    self.instance = lilv.Instance(plugin, rate)
    self._plugin = plugin
    self._world = world
    for i in range(plugin.get_num_ports()):
      port = plugin.get_port_by_index(i)
      symbol = port.get_symbol().as_string() if hasattr(port.get_symbol(), "as_string") else str(port.get_symbol())
      self._ports[symbol] = i
    # Connect stereo audio if present; otherwise first two audio in/out.
    audio_in, audio_out = [], []
    for symbol, index in self._ports.items():
      port = plugin.get_port_by_index(index)
      if port.is_a(world.ns.lv2.AudioPort):
        if port.is_a(world.ns.lv2.InputPort):
          audio_in.append((symbol, index))
        elif port.is_a(world.ns.lv2.OutputPort):
          audio_out.append((symbol, index))
    if len(audio_in) < 2 or len(audio_out) < 2:
      return
    n = FRAMES
    self.in_l = np.zeros(n, dtype=np.float32)
    self.in_r = np.zeros(n, dtype=np.float32)
    self.out_l = np.zeros(n, dtype=np.float32)
    self.out_r = np.zeros(n, dtype=np.float32)
    self.instance.connect_port(audio_in[0][1], self.in_l)
    self.instance.connect_port(audio_in[1][1], self.in_r)
    self.instance.connect_port(audio_out[0][1], self.out_l)
    self.instance.connect_port(audio_out[1][1], self.out_r)
    for symbol, index in self._ports.items():
      port = plugin.get_port_by_index(index)
      if port.is_a(world.ns.lv2.ControlPort) and port.is_a(world.ns.lv2.InputPort):
        default = 0.0
        try:
          default = float(port.get_range()[1]) if port.get_range() else 0.0
        except Exception:
          pass
        buf = np.array([default], dtype=np.float32)
        self.controls[symbol] = buf
        self.instance.connect_port(index, buf)
    self.instance.activate()
    self.ok = True

  def set_controls(self, mapping, prefix=""):
    if not self.ok:
      return
    for name, value in mapping.items():
      key = name.split(":", 1)[-1] if prefix and name.startswith(prefix) else name
      if key in self.controls:
        self.controls[key][0] = float(value)

  def process(self, left, right):
    if not self.ok:
      return left, right
    n = len(left)
    self.in_l[:n] = left
    self.in_r[:n] = right
    self.instance.run(n)
    return self.out_l[:n].copy(), self.out_r[:n].copy()


class Graph:
  def __init__(self):
    self.lock = threading.Lock()
    self.controls = {}
    self.left_biquads = []
    self.right_biquads = []
    self.bass = Lv2Stage(BASS_URI)
    self.loud = Lv2Stage(LOUDNESS_URI)
    self.limiter = Lv2Stage(LIMITER_URI)
    self.bypass = False

  def apply_controls(self, controls):
    with self.lock:
      self.controls = {str(k): float(v) for k, v in controls.items()}
      self._rebuild_biquads()
      self.bass.set_controls(self.controls, "bass:")
      self.loud.set_controls(
        {k.split(":", 1)[-1]: v for k, v in self.controls.items() if k.startswith("loudcomp:")}
      )
      if "limiter:g_in" in self.controls and "g_in" in self.limiter.controls:
        self.limiter.controls["g_in"][0] = self.controls["limiter:g_in"]
      for key in ("alr", "boost", "th"):
        name = f"limiter:{key}"
        if name in self.controls and key in self.limiter.controls:
          self.limiter.controls[key][0] = self.controls[name]

  def _rebuild_biquads(self):
    left, right = [], []
    for side, bucket in (("l", left), ("r", right)):
      # High-pass stages
      for index in (1, 2):
        f = self.controls.get(f"hp{index}_{side}:Freq")
        q = self.controls.get(f"hp{index}_{side}:Q", 0.707)
        if f is not None and f > 0:
          bucket.append(Biquad(rbj_highpass(f, q)))
      # Peaking slots
      for slot in range(1, 13):
        f = self.controls.get(f"p{slot}_{side}:Freq")
        g = self.controls.get(f"p{slot}_{side}:Gain", 0.0)
        q = self.controls.get(f"p{slot}_{side}:Q", 1.0)
        if f is not None and abs(g) > 1e-6:
          bucket.append(Biquad(rbj_peaking(f, q, g)))
      # Balance as simple gain
      mult = self.controls.get(f"bal_{side}:Mult", 1.0)
      add = self.controls.get(f"bal_{side}:Add", 0.0)
      bucket.append(("gain", float(mult), float(add)))
    self.left_biquads = left
    self.right_biquads = right

  def process_block(self, interleaved_f32):
    import numpy as np
    with self.lock:
      left = interleaved_f32[0::2].copy()
      right = interleaved_f32[1::2].copy()
      if self.controls.get("bass:bypass", 1.0) < 0.5:
        left, right = self.bass.process(left, right)
      if self.controls.get("loudcomp:enabled", 0.0) >= 0.5:
        left, right = self.loud.process(left, right)
      left = self._run_channel(left, self.left_biquads)
      right = self._run_channel(right, self.right_biquads)
      left, right = self.limiter.process(left, right)
      out = np.empty(left.size * 2, dtype=np.float32)
      out[0::2] = left
      out[1::2] = right
      return out

  @staticmethod
  def _run_channel(samples, stages):
    for stage in stages:
      if isinstance(stage, tuple) and stage[0] == "gain":
        _, mult, add = stage
        samples = samples * mult + add
      else:
        out = samples.copy()
        for i, x in enumerate(samples):
          out[i] = stage.process(float(x))
        samples = out
    return samples


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
    self.parec = subprocess.Popen(
      [
        "/usr/bin/parec",
        "--format=s16le",
        f"--rate={RATE}",
        f"--channels={CHANNELS}",
        f"--device={self.monitor}",
        f"--latency-msec=30",
      ],
      stdout=subprocess.PIPE,
      stderr=subprocess.DEVNULL,
    )
    self.pacat = subprocess.Popen(
      [
        "/usr/bin/pacat",
        "--playback",
        "--format=s16le",
        f"--rate={RATE}",
        f"--channels={CHANNELS}",
        f"--device={self.physical}",
        f"--latency-msec=30",
      ],
      stdin=subprocess.PIPE,
      stderr=subprocess.DEVNULL,
    )
    chunk = FRAMES * BYTES_PER_FRAME
    try:
      while self.running:
        data = self.parec.stdout.read(chunk)
        if not data:
          time.sleep(0.05)
          continue
        if len(data) < chunk:
          data = data + b"\x00" * (chunk - len(data))
        samples = np.frombuffer(data, dtype=np.int16).astype(np.float32) / 32768.0
        out = self.graph.process_block(samples)
        clipped = np.clip(out, -1.0, 1.0)
        pcm = (clipped * 32767.0).astype(np.int16).tobytes()
        try:
          self.pacat.stdin.write(pcm)
        except BrokenPipeError:
          break
    finally:
      for proc in (self.parec, self.pacat):
        if proc and proc.poll() is None:
          proc.terminate()
          try:
            proc.wait(timeout=2)
          except subprocess.TimeoutExpired:
            proc.kill()


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

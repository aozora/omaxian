#!/usr/bin/env python3
"""Emit {"peak": 0..1} JSON lines from the default PulseAudio source.

Fallback when /usr/bin/voxtype-audio-bridge is not installed. Aura only reads
`peak`. Uses pacat --record (more reliable remix than bare parec on
pipewire-pulse) at stereo s16le @ 48 kHz.
"""

from __future__ import annotations

import math
import struct
import subprocess
import sys
import time

RATE = 48000
CHANNELS = 2
SAMPLE_WIDTH = 2  # s16le
CHUNK_FRAMES = 480  # 10 ms
CHUNK_BYTES = CHUNK_FRAMES * CHANNELS * SAMPLE_WIDTH
SAMPLE_COUNT = CHUNK_FRAMES * CHANNELS


def main() -> int:
  # pacat --record is the PulseAudio utility that consistently remixes the
  # default source; bare `parec` with forced rate/channels often yields no
  # samples on pipewire-pulse monitor sources.
  cmd = [
    "pacat",
    "--record",
    "--raw",
    "--format=s16le",
    f"--channels={CHANNELS}",
    f"--rate={RATE}",
    "--latency-msec=30",
  ]
  try:
    proc = subprocess.Popen(
      cmd,
      stdout=subprocess.PIPE,
      stderr=subprocess.DEVNULL,
    )
  except OSError as exc:
    print(f"aura-audio-peak: failed to start pacat: {exc}", file=sys.stderr)
    return 1

  assert proc.stdout is not None
  buf = b""
  try:
    while True:
      need = CHUNK_BYTES - len(buf)
      chunk = proc.stdout.read(need)
      if not chunk:
        break
      buf += chunk
      while len(buf) >= CHUNK_BYTES:
        frame = buf[:CHUNK_BYTES]
        buf = buf[CHUNK_BYTES:]
        samples = struct.unpack("<" + "h" * SAMPLE_COUNT, frame)
        peak = 0.0
        for sample in samples:
          peak = max(peak, abs(sample) / 32768.0)
        peak = min(1.0, math.sqrt(peak) * 1.4)
        sys.stdout.write(f'{{"peak": {peak:.4f}, "ts_ms": {int(time.time() * 1000)}}}\n')
        sys.stdout.flush()
  except BrokenPipeError:
    return 0
  finally:
    proc.terminate()
    try:
      proc.wait(timeout=1)
    except subprocess.TimeoutExpired:
      proc.kill()
  return 0


if __name__ == "__main__":
  raise SystemExit(main())

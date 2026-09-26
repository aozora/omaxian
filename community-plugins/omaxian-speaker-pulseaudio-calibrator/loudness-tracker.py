#!/usr/bin/python3 -sB
"""Tell the loudness compensator what level the speakers are playing at.

Omaxian port: writes go to the local speaker-dsp Unix socket instead of upstream live-control tooling.

The ear loses bass as the level drops, so quiet music sounds thin.  The
compensator in the filter graph can undo that, but only if it is told the
listening level.  On this port the user-facing volume is the calibrated null
sink (the default), so that is what is watched.
"""

import importlib.util
import signal
import subprocess
import sys
import time
from pathlib import Path

HELPER = Path(__file__).resolve().parent / "speaker-calibrate.py"
VOLUME_EPSILON_DB = 0.4
RETRY_SECONDS = 2.0


def load_helper():
  spec = importlib.util.spec_from_file_location("speaker_calibrate", HELPER)
  module = importlib.util.module_from_spec(spec)
  sys.path.insert(0, str(HELPER.parent))
  spec.loader.exec_module(module)
  return module


class Tracker:
  def __init__(self, helper):
    self.helper = helper
    self.applied_db = None
    self.profile_stamp = None
    self.enabled = False
    self.input_gain = 1.0
    self.sink = None
    self.running = True

  def stop(self, *_):
    self.running = False

  def apply(self, volume_db, enabled=True):
    if not self.helper.dsp_running():
      return False
    controls = self.helper.loudness_controls(volume_db, enabled, self.input_gain)
    response = self.helper.dsp_request({"cmd": "set_loudness", "controls": controls})
    if not response or not response.get("ok"):
      return False
    self.applied_db = volume_db if enabled else None
    return True

  def wanted(self):
    try:
      stamp = self.helper.PROFILE.stat().st_mtime
    except OSError:
      return False
    if stamp != self.profile_stamp:
      profile = self.helper.load_profile(self.helper.PROFILE) or {}
      self.enabled = profile.get("loudness_compensation") == "on"
      self.input_gain = float(
        (profile.get("fit") or {}).get("input_gain_linear", 1.0))
      # Virtual sink is the default users hear; its volume is the listening level.
      self.sink = self.helper.VIRTUAL_SINK
      self.profile_stamp = stamp
    return self.enabled

  def follow_volume(self):
    if not self.wanted():
      return self.apply(0.0, enabled=False) if self.applied_db is not None else True
    volume = self.helper.sink_volume_db(self.sink or self.helper.VIRTUAL_SINK)
    if self.applied_db is not None and abs(volume - self.applied_db) < VOLUME_EPSILON_DB:
      return True
    return self.apply(volume)

  def run(self):
    if not self.wanted():
      return
    while self.running:
      if not self.follow_volume():
        time.sleep(RETRY_SECONDS)
        continue
      if not self.watch():
        time.sleep(RETRY_SECONDS)

  def watch(self):
    try:
      events = subprocess.Popen(
        ["/usr/bin/pactl", "subscribe"], stdout=subprocess.PIPE, text=True
      )
    except OSError:
      return False
    try:
      for line in events.stdout:
        if not self.running:
          return True
        if "on sink" in line and not self.follow_volume():
          return False
      return False
    finally:
      events.terminate()
      try:
        events.wait(timeout=2)
      except subprocess.TimeoutExpired:
        events.kill()


def main():
  helper = load_helper()
  tracker = Tracker(helper)
  signal.signal(signal.SIGTERM, tracker.stop)
  signal.signal(signal.SIGINT, tracker.stop)
  try:
    tracker.run()
  finally:
    if tracker.applied_db is not None:
      tracker.apply(0.0, enabled=False)


if __name__ == "__main__":
  main()

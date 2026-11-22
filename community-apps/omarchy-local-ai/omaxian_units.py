"""Omaxian port: the user-unit layer of the engine, without systemd.

Upstream runs every model as a systemd user unit (a Podman Quadlet) and every
detached setup as a transient unit. Devuan has no user manager, so this module
gives the engine the same few operations with plain processes:

  * a model unit is a supervisor process (`omarchy-local-ai supervise <unit>`)
    that runs `podman run` in the foreground, probes the model's health, applies
    the unit's restart policy and writes the unit's state;
  * a detached setup is the engine's own command, run in a new session;
  * a process "is the unit" while it holds an flock on the unit's lock file, so a
    crashed process never leaves a unit looking active.

`systemctl()` answers the calls agent_local.py makes (show, start, stop,
reset-failed, is-active, daemon-reload) from this state, so the engine's own
logic is unchanged. Everything lives under <state>/units and <state>/logs.
"""

import fcntl
import json
import os
import signal
import subprocess
import sys
import time

# The engine binds these once: its state directory (a function, as tests move
# HOME) and the entry script that re-runs it as a supervisor or a setup.
_state_dir = None
_entry = None

LOG_KEEP_BYTES = 4 * 1024 * 1024
STOP_TIMEOUT = 100
LIVE = ("active", "activating", "deactivating", "reloading")


def bind(state_dir, entry):
  global _state_dir, _entry
  _state_dir = state_dir
  _entry = entry


def _units_dir():
  return os.path.join(_state_dir(), "units")


def spec_path(unit):
  return os.path.join(_units_dir(), f"{unit}.spec.json")


def _state_path(unit):
  return os.path.join(_units_dir(), f"{unit}.state.json")


def _lock_path(unit):
  return os.path.join(_units_dir(), f"{unit}.lock")


def log_path(unit):
  return os.path.join(_state_dir(), "logs", f"{unit}.log")


def _ensure(path):
  os.makedirs(path, mode=0o700, exist_ok=True)


def _write_atomic(path, text):
  _ensure(os.path.dirname(path))
  temp = f"{path}.{os.getpid()}.tmp"
  with open(temp, "w") as handle:
    handle.write(text)
  os.replace(temp, path)


def _read_json(path):
  try:
    with open(path) as handle:
      value = json.load(handle)
    return value if isinstance(value, dict) else {}
  except (OSError, ValueError):
    return {}


def _stamp():
  return "@%d" % int(time.time())


def _result(returncode=0, stdout="", stderr=""):
  return subprocess.CompletedProcess([], returncode, stdout, stderr)


# ---------------------------------------------------------------- locks and state


def _take_lock(unit):
  """The unit's lock, held by the process that is the unit; None if another holds it."""
  _ensure(_units_dir())
  handle = open(_lock_path(unit), "a")
  try:
    fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
  except OSError:
    handle.close()
    return None
  return handle


def held(unit):
  handle = _take_lock(unit)
  if handle is None:
    return True
  handle.close()
  return False


def _set_state(unit, **changes):
  state = _read_json(_state_path(unit))
  state.update(changes)
  state["StateChangeTimestamp"] = _stamp()
  _write_atomic(_state_path(unit), json.dumps(state))
  return state


def read_state(unit):
  """The unit as `systemctl show` would report it, from its state file and its lock."""
  state = _read_json(_state_path(unit))
  active = state.get("ActiveState", "inactive")
  if active in LIVE and not held(unit) and state.get("MainPID") != 0:
    # The process that was the unit is gone without saying so. (MainPID 0 is a
    # start whose supervisor has not taken the lock yet; start() times that out.)
    if os.path.exists(spec_path(unit)):
      state.update(ActiveState="failed", SubState="failed", Result="signal")
    else:
      state.update(ActiveState="inactive", SubState="dead")
  state.setdefault("ActiveState", "inactive")
  return state


def show(unit, names):
  state = read_state(unit)
  defaults = {"SubState": "dead", "Result": "success"}
  return {name: str(state.get(name, defaults.get(name, ""))) for name in names}


# ---------------------------------------------------------------- the systemctl seam


def systemctl(*args, check=False, timeout=None, tick=None):
  """The subset of `systemctl --user` the engine uses, for this module's units."""
  args = list(args)
  command = args.pop(0) if args else ""
  flags = [a for a in args if a.startswith("--")]
  units = [a for a in args if not a.startswith("--")]
  unit = units[0] if units else ""
  if command == "show":
    names = [f[len("--property="):] for f in flags if f.startswith("--property=")]
    values = show(unit, names)
    return _result(0, "".join(f"{name}={value}\n" for name, value in values.items()))
  if command == "is-active":
    state = read_state(unit)
    return _result(0 if state.get("ActiveState") in ("active", "activating") else 3)
  if command == "reset-failed":
    if read_state(unit).get("ActiveState") == "failed":
      _set_state(unit, ActiveState="inactive", SubState="dead", Result="success")
    return _result()
  if command == "daemon-reload":
    return _result()
  if command == "stop":
    result = stop(unit, block="--no-block" not in flags)
  elif command == "start":
    result = start(unit, tick=tick)
  else:
    result = _result(1, "", f"unsupported systemctl command: {command}")
  if check and result.returncode != 0:
    raise subprocess.CalledProcessError(result.returncode, ["systemctl", command, unit], result.stdout, result.stderr)
  return result


def _signal_unit(unit, sig):
  state = _read_json(_state_path(unit))
  pid = state.get("MainPID")
  if not isinstance(pid, int) or pid <= 1:
    return False
  try:
    # A setup runs in a session of its own, so its downloads end with it; a
    # supervisor stops its container itself.
    if state.get("Kind") == "transient":
      os.killpg(pid, sig)
    else:
      os.kill(pid, sig)
  except OSError:
    return False
  return True


def stop(unit, block=True):
  if not held(unit):
    return _result()
  _signal_unit(unit, signal.SIGTERM)
  if not block:
    return _result()
  deadline = time.time() + STOP_TIMEOUT
  while held(unit):
    if time.time() > deadline:
      _signal_unit(unit, signal.SIGKILL)
      name = _read_json(spec_path(unit)).get("name")
      if name:
        subprocess.run(["podman", "rm", "-v", "-f", "-i", "-t", "0", name], capture_output=True)
      break
    time.sleep(0.1)
  return _result()


def start(unit, tick=None):
  """Start a supervised unit and wait, as `systemctl start` does for Notify=healthy,
  until it is healthy (0) or has failed (1). `tick` is called once a second."""
  if not os.path.isfile(spec_path(unit)):
    return _result(5, "", f"Unit {unit} not found.")
  if held(unit):
    state = read_state(unit)
    if state.get("ActiveState") == "active":
      return _result()
  else:
    _set_state(unit, ActiveState="activating", SubState="start", Result="success", InactiveExitTimestamp=_stamp(), MainPID=0)
    log = _open_log(unit)
    subprocess.Popen([sys.executable, _entry, "supervise", unit], stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                     start_new_session=True, close_fds=True)
    log.close()
  spawned = time.time()
  while True:
    time.sleep(0.5)
    if tick:
      tick()
    state = read_state(unit)
    active = state.get("ActiveState")
    if active == "active":
      return _result()
    if active == "failed":
      return _result(1, "", f"Job for {unit} failed: {state.get('Result', 'failed')}")
    if active == "inactive" and not held(unit) and time.time() - spawned > 3:
      return _result(1, "", f"{unit} stopped before it was healthy")
    if active == "activating" and not held(unit) and time.time() - spawned > 10:
      _set_state(unit, ActiveState="failed", SubState="failed", Result="exit-code", MainPID=-1)
      return _result(1, "", f"{unit} did not start")


def _open_log(unit):
  path = log_path(unit)
  _ensure(os.path.dirname(path))
  try:
    if os.path.getsize(path) > LOG_KEEP_BYTES:
      os.replace(path, path + ".1")
  except OSError:
    pass
  return open(path, "ab")


# ---------------------------------------------------------------- detached runs (systemd-run)


def run_transient(unit, argv, env=None):
  """Run argv detached, as a unit named `unit` (what `systemd-run --user --unit` did)."""
  if held(unit):
    return _result(1, "", f"Unit {unit} is already running")
  log = _open_log(unit)
  child = subprocess.Popen([sys.executable, _entry, "_exec", unit, "--", *argv], stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                           env=env, start_new_session=True, close_fds=True)
  log.close()
  # Like systemd-run, return once the unit exists.
  for _ in range(100):
    if held(unit):
      return _result()
    if child.poll() is not None:
      return _result(child.returncode or 1, "", f"{unit} didn't start")
    time.sleep(0.05)
  return _result(1, "", f"{unit} didn't start")


def cmd_exec(args):
  """`_exec <unit> -- argv`: take the unit's lock, then become argv. The lock's descriptor
  stays open across the exec, so the unit is active exactly as long as argv runs."""
  unit, argv = args[0], args[args.index("--") + 1:]
  handle = _take_lock(unit)
  if handle is None:
    return 1
  os.set_inheritable(handle.fileno(), True)
  _set_state(unit, ActiveState="active", SubState="running", Kind="transient", MainPID=os.getpid(), Result="success")
  os.execvp(argv[0], argv)


# ---------------------------------------------------------------- logs (journalctl)


def journal(unit, lines=15, since_ms=None):
  try:
    with open(log_path(unit), "rb") as handle:
      handle.seek(0, os.SEEK_END)
      size = handle.tell()
      handle.seek(max(0, size - 512 * 1024))
      text = handle.read().decode("utf-8", "replace")
  except OSError:
    return ""
  if since_ms:
    # The text after the last start that began at or after since_ms.
    parts = text.split("--- start ")
    keep = [parts[0]] if len(parts) == 1 else []
    for part in parts[1:]:
      stamp, _, rest = part.partition(" ---\n")
      if stamp.isdigit() and int(stamp) * 1000 >= since_ms:
        keep.append(rest)
    text = "".join(keep) if keep else ""
  return "\n".join(text.splitlines()[-lines:]).strip()


# ---------------------------------------------------------------- the supervisor


class Supervisor:
  """One model's unit: `podman run` in the foreground, its health, its restarts."""

  def __init__(self, unit):
    self.unit = unit
    self.spec = _read_json(spec_path(unit))
    self.name = self.spec["name"]
    self.stop_requested = False
    self.starts = []

  # -- podman helpers
  def podman(self, *args, timeout=None):
    try:
      return subprocess.run(["podman", *args], capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
      return _result(124)

  def remove_container(self):
    self.podman("rm", "-v", "-f", "-i", "-t", "0", self.name)

  def probe(self):
    return self.podman("exec", self.name, *self.spec["probe"], timeout=self.spec.get("probe_timeout", 5)).returncode == 0

  def say(self, text):
    print(text, flush=True)

  def hook(self, which, result="success"):
    argv = self.spec.get("hooks", {}).get(which)
    if not argv:
      return
    env = dict(os.environ, SERVICE_RESULT=result)
    try:
      subprocess.run(argv, env=env, stdin=subprocess.DEVNULL, capture_output=True, timeout=120)
    except (OSError, subprocess.SubprocessError):
      pass

  def sleep(self, seconds):
    end = time.time() + seconds
    while not self.stop_requested and time.time() < end:
      time.sleep(0.2)

  def control_group(self):
    pid = self.podman("inspect", "-f", "{{.State.Pid}}", self.name).stdout.strip()
    if not pid.isdigit() or pid == "0":
      return ""
    try:
      with open(f"/proc/{pid}/cgroup") as handle:
        for line in handle:
          if line.startswith("0::"):
            return line[3:].strip()
    except OSError:
      pass
    return ""

  # -- one run of the container; returns the unit result
  def run_once(self):
    self.remove_container()
    self.say("--- start %d ---" % int(time.time()))
    _set_state(self.unit, ActiveState="activating", SubState="start", Result="success", InactiveExitTimestamp=_stamp(), ControlGroup="")
    argv = ["podman", "run", "--name", self.name, "--pull=never", *self.spec["flags"], self.spec["image"], *self.spec.get("args", [])]
    process = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=sys.stdout, stderr=sys.stderr)
    started = time.time()
    healthy = False
    failures = 0
    next_probe = started
    result = None
    while process.poll() is None:
      if self.stop_requested:
        break
      now = time.time()
      if now >= next_probe:
        ok = self.probe()
        if not healthy:
          if ok:
            healthy = True
            failures = 0
            _set_state(self.unit, ActiveState="active", SubState="running", ControlGroup=self.control_group())
            self.hook("started")
          elif now - started > self.spec.get("start_timeout", 720):
            self.say("The model did not become healthy in time")
            result = "timeout"
            break
          next_probe = time.time() + 2
        else:
          failures = 0 if ok else failures + 1
          if failures >= 3:
            self.say("The model failed its health check; killing it")
            self.podman("kill", self.name)
            result = "exit-code"
            break
          next_probe = time.time() + 30
      time.sleep(0.5)
    left_active = healthy
    _set_state(self.unit, ActiveState="deactivating", SubState="stop", **({"ActiveExitTimestamp": _stamp()} if left_active else {}))
    if self.stop_requested and process.poll() is None:
      if healthy:
        self.podman("stop", "-t", str(self.spec.get("stop_timeout", 20)), self.name)
      else:
        # A server still loading doesn't heed SIGTERM: remove the container at once.
        self.remove_container()
    elif process.poll() is None:
      self.remove_container()
    try:
      code = process.wait(timeout=60)
    except subprocess.TimeoutExpired:
      process.kill()
      code = process.wait()
    self.remove_container()
    if self.stop_requested:
      return "success"
    if result:
      return result
    if code == 0:
      return "success"
    return "signal" if code < 0 or code >= 128 else "exit-code"

  def run(self):
    def stop(*_):
      self.stop_requested = True
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    limit = self.spec.get("start_limit", [3, 600])
    final = "success"
    while True:
      now = time.time()
      self.starts = [at for at in self.starts if now - at < limit[1]]
      if len(self.starts) >= limit[0]:
        final = "start-limit-hit"
        break
      self.starts.append(now)
      result = self.run_once()
      self.hook("stopped", result)
      if self.stop_requested or result == "success" or not self.spec.get("restart"):
        final = result
        break
      _set_state(self.unit, ActiveState="activating", SubState="auto-restart", Result=result)
      self.sleep(self.spec.get("restart_seconds", 10))
      if self.stop_requested:
        final = "success"
        break
    ok = final == "success"
    _set_state(self.unit, ActiveState="inactive" if ok else "failed", SubState="dead" if ok else "failed", Result=final, ControlGroup="")
    return 0 if ok else 1


def cmd_supervise(args):
  unit = args[0]
  handle = _take_lock(unit)
  if handle is None:
    return 0
  _set_state(unit, MainPID=os.getpid(), Kind="supervisor")
  return Supervisor(unit).run()

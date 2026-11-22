#!/bin/bash
# Omaxian: the supervisor that stands in for systemd user units (omaxian_units.py).
# Needs rootless Podman and an alpine image already in its store (it never pulls);
# otherwise the container checks are skipped. Engine state goes to a temporary HOME,
# Podman keeps using the real one.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
export ENGINE_ROOT="$ROOT" PYTHONDONTWRITEBYTECODE=1 SCRATCH="$scratch"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}" XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export HOME="$scratch"

python3 -I <<'PY'
import json
import os
import subprocess
import sys
import threading
import time

sys.path.insert(0, os.environ["ENGINE_ROOT"])
import agent_local as a
u = a.omaxian_units

failed = []


def check(name, condition, detail=""):
  print(("ok - " if condition else "not ok - ") + name, flush=True)
  if not condition:
    failed.append(name)
    if detail:
      print(detail, file=sys.stderr)


unit = "omarchy-agent-local-model-supertest.service"
name = unit[:-len(".service")]
state = lambda: u.show(unit, ["ActiveState", "SubState", "Result"])

# -- a unit that isn't there, and the plain transient run, need no container
check("an unknown unit is inactive", state()["ActiveState"] == "inactive")
check("starting an unknown unit fails", a.systemctl("start", unit).returncode != 0)
tu = "omarchy-agent-local-use-supertest.service"
result = u.run_transient(tu, ["sh", "-c", "echo hello; sleep 2; echo bye"])
check("a transient run starts and is active", result.returncode == 0 and a.systemctl("is-active", "--quiet", tu).returncode == 0)
check("a transient unit can't start twice", u.run_transient(tu, ["true"]).returncode != 0)
time.sleep(3)
check("a transient run ends and keeps its output", a.systemctl("is-active", "--quiet", tu).returncode != 0 and u.journal(tu, 5) == "hello\nbye", u.journal(tu, 5))
long_tu = "omarchy-agent-local-use-supertest2.service"
u.run_transient(long_tu, ["sh", "-c", "sleep 60"])
t = time.time()
a.systemctl("stop", long_tu)
check("stopping a transient run ends it", a.systemctl("is-active", "--quiet", long_tu).returncode != 0 and time.time() - t < 5)

alpine = "docker.io/library/alpine:latest"
have_alpine = subprocess.run(["podman", "image", "exists", alpine], capture_output=True).returncode == 0 if subprocess.run(["which", "podman"], capture_output=True).returncode == 0 else False
if not have_alpine:
  print("ok - container checks # SKIP (no podman, or no alpine image in its store)")
else:
  net = f"omaxian-test-{os.getpid()}"
  subprocess.run(["podman", "network", "create", "--internal", net], capture_output=True, check=True)
  hooks = os.path.join(os.environ["SCRATCH"], "hooks.log")
  spec = {
    "name": name, "image": alpine,
    "flags": ["--network", net, "--read-only", "--cap-drop=all", "--tmpfs", "/tmp"],
    "args": ["sh", "-c", "echo booting; sleep 3; echo ready > /tmp/ready; sleep 600"],
    "probe": ["sh", "-c", "test -f /tmp/ready"], "start_timeout": 60, "stop_timeout": 5,
    "restart": True, "restart_seconds": 2, "start_limit": [3, 600],
    "hooks": {"started": ["sh", "-c", f"echo started >> {hooks}"], "stopped": ["sh", "-c", f"echo stopped:$SERVICE_RESULT >> {hooks}"]},
  }
  os.makedirs(os.path.dirname(u.spec_path(unit)), exist_ok=True)
  try:
    with open(u.spec_path(unit), "w") as handle:
      json.dump(spec, handle)
    result = a.systemctl("start", unit)
    check("start waits until the model is healthy", result.returncode == 0 and state()["ActiveState"] == "active", repr((result, state())))
    check("an active unit reports active", a.systemctl("is-active", "--quiet", unit).returncode == 0)
    check("starting a running unit does nothing", a.systemctl("start", unit).returncode == 0)
    pid = subprocess.run(["podman", "inspect", "-f", "{{.State.Pid}}", name], capture_output=True, text=True).stdout.strip()
    os.kill(int(pid), 9)
    time.sleep(1)
    check("a crash shows as an automatic restart", state()["ActiveState"] == "activating" and state()["SubState"] == "auto-restart", repr(state()))
    for _ in range(40):
      time.sleep(1)
      if state()["ActiveState"] == "active":
        break
    check("a crashed model is restarted and goes active again", state()["ActiveState"] == "active", repr(state()))
    started = time.time()
    a.systemctl("stop", unit)
    check("stop ends the model", state()["ActiveState"] == "inactive" and not a.omaxian_units.held(unit) and time.time() - started < 30, repr(state()))
    check("the container is gone after a stop", subprocess.run(["podman", "container", "exists", name]).returncode != 0)
    with open(hooks) as handle:
      check("the hooks ran for the start, the crash, the restart and the stop", handle.read().split() == ["started", "stopped:signal", "started", "stopped:success"])
    check("the log holds this run's output", "booting" in u.journal(unit, 5, since_ms=1))

    # Stopped while still loading: the container goes at once.
    a.systemctl("reset-failed", unit)
    box = []
    thread = threading.Thread(target=lambda: box.append(a.systemctl("start", unit)))
    thread.start()
    time.sleep(1.5)
    check("a model still loading is activating", state()["ActiveState"] == "activating", repr(state()))
    started = time.time()
    a.stop_unit("supertest")
    thread.join()
    check("stopping mid-load is prompt and ends the start", time.time() - started < 10 and state()["ActiveState"] == "inactive" and box and box[0].returncode != 0, repr((state(), box)))

    # A model that never gets healthy times out and gives up after the start limit.
    spec.update(args=["sh", "-c", "sleep 600"], probe=["false"], start_timeout=2, restart_seconds=1, start_limit=[2, 600])
    with open(u.spec_path(unit), "w") as handle:
      json.dump(spec, handle)
    a.systemctl("reset-failed", unit)
    result = a.systemctl("start", unit)
    deadline = time.time() + 60
    while time.time() < deadline and state()["ActiveState"] != "failed":
      time.sleep(1)
    check("a model that never gets healthy ends failed at the start limit", state()["ActiveState"] == "failed" and state()["Result"] == "start-limit-hit", repr((result, state())))
    a.systemctl("reset-failed", unit)
    check("reset-failed clears it", state()["ActiveState"] == "inactive")
  finally:
    subprocess.run(["podman", "rm", "-v", "-f", "-i", "-t", "0", name], capture_output=True)
    subprocess.run(["podman", "network", "rm", "-f", net], capture_output=True)

if failed:
  print("\n".join(f"failed - {n}" for n in failed), file=sys.stderr)
  raise SystemExit(1)
PY

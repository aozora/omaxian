#!/usr/bin/env python3
"""Verify Service.copyText uses Qt clipboard (no external CLI) on Omaxian."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
runner = shutil.which("qmltestrunner6") or shutil.which("qmltestrunner")
if not runner and Path("/usr/lib/qt6/bin/qmltestrunner").exists():
    runner = "/usr/lib/qt6/bin/qmltestrunner"
if not runner:
    print("Clipboard transport regression SKIP: requires QML test tooling")
    raise SystemExit(0)

with tempfile.TemporaryDirectory(prefix="omamail-clipboard-") as directory:
    env = dict(os.environ, XDG_RUNTIME_DIR=directory,
               XDG_CONFIG_HOME=directory, XDG_DATA_HOME=directory,
               XDG_CACHE_HOME=directory, XDG_STATE_HOME=directory,
               DISPLAY=":0",
               QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
               QT_QPA_PLATFORMTHEME="", GSETTINGS_BACKEND="memory")
    result = subprocess.run([runner, "-input", str(ROOT / "ui/tests/qml/tst_clipboard_arguments.qml"),
                             "-import", str(ROOT / "ui/tests/qml/imports")],
                            env=env, text=True, capture_output=True, timeout=30)
    assert result.returncode == 0, result.stdout + result.stderr
print("Clipboard transport regression PASS; Qt clipboard, no external CLI")

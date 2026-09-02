#!/usr/bin/env python3
"""Force X11 input focus onto the Quickshell polkit auth overlay.

The polkit dialog (plugins/polkit/PolkitAgent.qml) is a full-screen
`PanelWindow` (X11 dock), *not* an override-redirect popup — so
`focus-window.py`'s filter (which requires override_redirect) skips it. Here
we do the opposite: among the windows owned by the quickshell process, pick
the largest *managed* (not override-redirect) mapped one and XSetInputFocus
it, so the password `TextInput` can actually receive keys under i3.

Only runs while the auth dialog is mapped (PolkitAgent.qml's focusGrab
timer), so the "largest managed qs window" is the polkit overlay.
"""
import subprocess
import sys

from Xlib import X, display


def main() -> int:
    try:
        pid = int(
            subprocess.check_output(["pgrep", "-x", "quickshell"]).decode().split()[0]
        )
    except Exception:
        return 1

    d = display.Display()
    root = d.screen().root
    pid_atom = d.intern_atom("_NET_WM_PID")

    best = None
    best_area = 0

    def walk(win):
        nonlocal best, best_area
        try:
            attrs = win.get_attributes()
            geom = win.get_geometry()
            prop = win.get_full_property(pid_atom, X.AnyPropertyType)
            owner_pid = prop.value[0] if prop else None
            if (
                owner_pid == pid
                and not attrs.override_redirect
                and attrs.map_state == X.IsViewable
            ):
                area = geom.width * geom.height
                if area > best_area:
                    best, best_area = win, area
        except Exception:
            pass
        try:
            children = win.query_tree().children
        except Exception:
            children = []
        for c in children:
            walk(c)

    walk(root)
    if best is None:
        return 1

    best.set_input_focus(X.RevertToParent, X.CurrentTime)
    d.sync()
    return 0


if __name__ == "__main__":
    sys.exit(main())

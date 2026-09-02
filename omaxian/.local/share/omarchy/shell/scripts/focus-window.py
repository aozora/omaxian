#!/usr/bin/env python3
"""Force X11 input focus onto the current quickshell popup window.

Why this exists: Quickshell's PopupCard (Ui/PopupCard.qml) is a
Qt::Popup-flagged, override-redirect window (confirmed live via
`_NET_WM_WINDOW_TYPE`/`get_input_focus` traced with python-xlib during this
migration). Under i3, mapping that window does not transfer X11 keyboard
input focus to it automatically the way a real toplevel would -- i3 keeps
whatever window it last tracked as focused, and Qt's own
`TextField.forceActiveFocus()` only sets *which item* would receive keys
*if* the window had focus, it doesn't request the window-level focus
itself. Confirmed the other direction too: a plain top-level
`PanelWindow` (which does grant proper focus) gets tiled into the layout by
i3 instead, since it has no floating hint -- so switching window types
trades this problem for a worse one. Explicitly calling XSetInputFocus on
the popup window, from outside the Qt/QPA layer, is the fix that actually
sticks (verified: repeated open/type/check-focus cycles hold focus on the
popup, not reverting to whatever window was focused before).

Finds the popup by: owned by this quickshell process (`_NET_WM_PID`),
override-redirect (popups are; the bar/dock is not), mapped, and not the
full-width bar strip.
"""
import subprocess
import sys

from Xlib import X, display


def main() -> int:
    # Phase 3: the host runs `quickshell -n -p <OMARCHY_PATH>/shell` (via
    # omarchy-launch-shell), not `quickshell -d …`. Match the process name
    # exactly (`pgrep -x`) so a shell command line that merely mentions
    # quickshell can't false-positive.
    try:
        pid = int(
            subprocess.check_output(["pgrep", "-x", "quickshell"]).decode().split()[0]
        )
    except Exception:
        return 1

    d = display.Display()
    root = d.screen().root
    pid_atom = d.intern_atom("_NET_WM_PID")

    def find(win):
        try:
            attrs = win.get_attributes()
            geom = win.get_geometry()
            prop = win.get_full_property(pid_atom, X.AnyPropertyType)
            owner_pid = prop.value[0] if prop else None
            if (
                owner_pid == pid
                and attrs.override_redirect
                and attrs.map_state == X.IsViewable
                and geom.height > 40  # excludes the 36px bar strip
            ):
                return win
        except Exception:
            pass
        try:
            children = win.query_tree().children
        except Exception:
            children = []
        for c in children:
            found = find(c)
            if found:
                return found
        return None

    target = find(root)
    if target is None:
        return 1

    target.set_input_focus(X.RevertToParent, X.CurrentTime)
    d.sync()
    return 0


if __name__ == "__main__":
    sys.exit(main())

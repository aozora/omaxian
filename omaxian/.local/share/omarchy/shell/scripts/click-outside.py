#!/usr/bin/env python3
"""Print `outside` whenever a mouse button is pressed on a window that does
not belong to quickshell.

Why this exists: X11 delivers a click to the client that owns the window
under the pointer. `PopupWindow.grabFocus` (Qt::Popup) holds no X pointer
grab here (verified with python-xlib: a second client can grab the pointer
and keyboard while a popup is open), so a press on another application's
window never reaches quickshell and the popup stays open. Hyprland's
`HyprlandFocusGrab` has no X11 equivalent, and a full-screen catcher
window is out (a full-screen `PanelWindow` is an i3 dock and swallows the
workspace — see docs/omarchy-port/phase-8.md).

So instead of grabbing, listen: XI2 raw button events on the root window
are delivered for every press on the display without grabbing anything.
The click still reaches the app; quickshell only learns it happened.

On each press of button 1–3 (the wheel and side buttons never dismiss),
walk the window stack under the pointer from the root down to the deepest
child. If no window on that path carries `_NET_WM_PID` == the quickshell
pid, the press was outside: print a line. The bar (plugins/bar/Bar.qml)
runs this only while a popout is open and closes it on each line.

Usage: click-outside.py [quickshell-pid]  (default: the parent process,
since Quickshell's Process starts this directly).
"""
import os
import struct
import sys

from Xlib import X, display
from Xlib.ext import xinput

DISMISS_BUTTONS = (1, 2, 3)


def owned_by(d, root, pid_atom, pid):
    win = root
    while True:
        try:
            prop = win.get_full_property(pid_atom, X.AnyPropertyType)
            if prop and prop.value and prop.value[0] == pid:
                return True
            child = win.query_pointer().child
        except Exception:
            return False
        if not child:
            return False
        win = child


def main() -> int:
    pid = int(sys.argv[1]) if len(sys.argv) > 1 else os.getppid()

    d = display.Display()
    if not d.has_extension("XInputExtension"):
        return 1
    root = d.screen().root
    pid_atom = d.intern_atom("_NET_WM_PID")

    root.xinput_select_events([(xinput.AllMasterDevices, xinput.RawButtonPressMask)])
    d.flush()

    while True:
        ev = d.next_event()
        if getattr(ev, "evtype", None) != xinput.RawButtonPress:
            continue
        # python-xlib registers no parser for raw events, so `data` is the
        # wire payload after the GE header: deviceid u16, time u32,
        # detail u32 (the button), in the client's byte order.
        if struct.unpack_from("=HII", ev.data, 0)[2] not in DISMISS_BUTTONS:
            continue
        if not owned_by(d, root, pid_atom, pid):
            print("outside", flush=True)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (KeyboardInterrupt, BrokenPipeError):
        sys.exit(0)

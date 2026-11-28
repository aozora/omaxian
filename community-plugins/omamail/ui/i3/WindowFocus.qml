import QtQuick
import Quickshell
import Quickshell.Io

// Brings the mail window in front of the person who clicked a notification.
//
// Omaxian: upstream's helper asks Hyprland. The window keeps the workspace it
// was left on, so focusing it by its exact title makes i3 switch to it. The
// request is repeated for up to about 1.5 s because a window the click has
// just summoned may not be mapped yet, and stops at the first one i3 accepts.
//
// i3-only, behind a Loader in App.qml, so the standalone host never loads it.
Item {
  id: root
  visible: false

  property string windowTitle: ""
  property int maxAttempts: 12

  function bringToFront() {
    if (windowTitle === "" || focus.running) return
    var title = String(windowTitle).replace(/[.*+?^${}()|[\]\\"]/g, "\\$&")
    // The criteria is passed as an argument, never read as shell code.
    focus.command = ["bash", "-c",
      'for ((i = 0; i < $2; i++)); do i3-msg -q "$1" 2>/dev/null && exit 0; sleep 0.12; done',
      "omamail-focus", "[title=\"^" + title + "$\"] focus", String(maxAttempts)]
    focus.running = true
  }

  Process { id: focus }
}

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// X11 stand-in for upstream's Hyprland `activelayout` IPC +
// `switchxkblayout current next`. Subscribes to XkbStateNotify via
// `scripts/keyboard.sh watch` so Alt+Shift / Shift+Alt updates the label
// immediately (a 2s poll often missed the change or felt stuck). Click
// cycles with `keyboard.sh next` (XkbLockGroup, then xkb-switch / setxkbmap).
BarWidget {
  id: root
  moduleName: "omarchy.keyboard-layout"

  property string display: ""

  function cycle() {
    if (!cycleProc.running) cycleProc.running = true
  }

  // Long-lived watcher: one line per layout / Caps change.
  Process {
    id: watchProc
    running: true
    command: ["bash", Quickshell.shellDir + "/scripts/keyboard.sh", "watch"]
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(line) {
        var t = String(line || "").trim()
        if (t.length > 0) root.display = t
      }
    }
    // If the helper exits (display lost, crash), retry shortly.
    onExited: function() {
      watchRestart.restart()
    }
  }

  Timer {
    id: watchRestart
    interval: 1000
    repeat: false
    onTriggered: {
      if (!watchProc.running) watchProc.running = true
    }
  }

  Process {
    id: cycleProc
    property string stdoutBuf: ""
    property int maxStdout: 1024
    property bool overflowed: false
    command: ["bash", Quickshell.shellDir + "/scripts/keyboard.sh", "next"]
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        if (cycleProc.overflowed) return
        cycleProc.stdoutBuf += chunk
        if (cycleProc.stdoutBuf.length > cycleProc.maxStdout) {
          cycleProc.overflowed = true
          cycleProc.stdoutBuf = ""
          cycleProc.signal(15)
          cycleKillTimer.start()
        }
      }
    }
    onStarted: {
      cycleKillTimer.stop()
      stdoutBuf = ""
      overflowed = false
    }
    onExited: function() {
      cycleKillTimer.stop()
      var t = overflowed ? "" : String(stdoutBuf || "").trim()
      stdoutBuf = ""
      overflowed = false
      // Watcher will also refresh; apply immediately so the click feels instant.
      if (t.length > 0) root.display = t
    }
  }

  Timer {
    id: cycleKillTimer
    interval: 2000
    onTriggered: cycleProc.signal(9)
  }

  Component.onDestruction: {
    watchProc.signal(15)
    cycleProc.signal(15)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    fontSize: Style.font.body
    text: Util.plain(root.display)
    tooltipText: "Next keyboard layout"
    horizontalMargin: 8.5
    verticalPadding: 6
    onPressed: root.cycle()
  }
}

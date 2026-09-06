import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// X11 stand-in for upstream's Hyprland `activelayout` IPC +
// `switchxkblayout current next`. No i3 event source, so the label is a 2s
// poll of `scripts/keyboard.sh` (xprop + XkbGetState). Click cycles via
// that script: xkb-switch, else ISO_Next_Group (same keysym as grp:*_toggle),
// else a setxkbmap layout-list rotate.
BarWidget {
  id: root
  moduleName: "omarchy.keyboard-layout"

  property string display: ""

  function refresh() {
    if (!proc.running) proc.running = true
  }

  function cycle() {
    if (!cycleProc.running) cycleProc.running = true
  }

  Timer {
    interval: 2000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: proc
    property string stdoutBuf: ""
    property int maxStdout: 1024
    property bool overflowed: false
    command: ["bash", Quickshell.shellDir + "/scripts/keyboard.sh"]
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        if (proc.overflowed) return
        proc.stdoutBuf += chunk
        if (proc.stdoutBuf.length > proc.maxStdout) {
          proc.overflowed = true
          proc.stdoutBuf = ""
          proc.signal(15)
          keyboardKillTimer.start()
        }
      }
    }
    onStarted: {
      keyboardKillTimer.stop()
      stdoutBuf = ""
      overflowed = false
    }
    onExited: function() {
      keyboardKillTimer.stop()
      var t = overflowed ? "" : String(stdoutBuf || "").trim()
      stdoutBuf = ""
      overflowed = false
      if (t.length > 0) root.display = t
    }
  }

  Timer {
    id: keyboardKillTimer
    interval: 2000
    onTriggered: proc.signal(9)
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
      if (t.length > 0) root.display = t
    }
  }

  Timer {
    id: cycleKillTimer
    interval: 2000
    onTriggered: cycleProc.signal(9)
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

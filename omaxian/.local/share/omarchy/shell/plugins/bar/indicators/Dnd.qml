import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// X11 delta (§6, decision 4): upstream reads/writes DND on the
// `omarchy.notifications` service (the ported-out freedesktop daemon). This
// profile keeps dunst, which owns the same state — poll `dunstctl is-paused`
// and toggle with `dunstctl set-paused`.
BarIndicator {
  id: root

  property bool paused: false

  active: paused
  activeText: "󰂛"
  inactiveText: "󰂛"
  activeTooltipText: "Allow Notifications"
  inactiveTooltipText: "Silence Notifications"

  function refresh() {
    if (!root.bar || statusProc.running) return
    statusProc.running = true
  }

  onBarChanged: refresh()
  Component.onCompleted: refresh()

  Connections {
    target: root.indicatorHost
    ignoreUnknownSignals: true
    function onRefreshRequested() { root.refresh() }
  }

  // dunst hooks don't cover every transition (e.g. paused via dunstctl from
  // another client), so a slow poll backs up the click round-trip.
  Timer {
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: statusProc
    property string stdoutBuf: ""
    property int maxStdout: 256
    property bool overflowed: false
    command: ["/usr/bin/dunstctl", "is-paused"]
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        if (statusProc.overflowed) return
        statusProc.stdoutBuf += chunk
        if (statusProc.stdoutBuf.length > statusProc.maxStdout) {
          statusProc.overflowed = true
          statusProc.stdoutBuf = ""
          statusProc.signal(15)
          dndKillTimer.start()
        }
      }
    }
    onStarted: {
      dndKillTimer.stop()
      stdoutBuf = ""
      overflowed = false
    }
    onExited: function(exitCode) {
      dndKillTimer.stop()
      var raw = overflowed ? "" : String(stdoutBuf || "").trim()
      stdoutBuf = ""
      overflowed = false
      if (exitCode !== 0) root.paused = false
      else root.paused = raw === "true"
    }
  }

  Timer {
    id: dndKillTimer
    interval: 2000
    onTriggered: statusProc.signal(9)
  }

  onPressed: function() {
    Quickshell.execDetached(["/usr/bin/dunstctl", "set-paused", root.paused ? "false" : "true"])
    Qt.callLater(root.refresh)
  }
}

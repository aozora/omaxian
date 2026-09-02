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
    command: ["dunstctl", "is-paused"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.paused = String(text || "").trim() === "true"
    }
    onExited: function(exitCode) { if (exitCode !== 0) root.paused = false }
  }

  onPressed: function() {
    Quickshell.execDetached(["bash", "-lc",
      "dunstctl set-paused " + (root.paused ? "false" : "true")])
    Qt.callLater(root.refresh)
  }
}

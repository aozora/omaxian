import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

BarIndicator {
  id: root

  property int reminderCount: 0
  property string tooltip: ""

  active: reminderCount > 0
  activeText: "󰢌"
  inactiveText: "󰢌"
  activeTooltipText: tooltip
  inactiveTooltipText: tooltip

  function refresh() {
    if (!jsonProc.running) jsonProc.running = true
  }

  function openReminderFlow() {
    Quickshell.execDetached(["omarchy-reminder", "-i"])
  }

  function update(raw) {
    var data = extractData(raw)
    reminderCount = Number(data.count || 0)
    tooltip = String(data.tooltip || "")
  }

  Component.onCompleted: refresh()

  Connections {
    target: root.indicatorHost
    ignoreUnknownSignals: true
    function onRefreshRequested() { root.refresh() }
  }

  Process {
    id: jsonProc
    property string stdoutBuf: ""
    property int maxStdout: 16384
    property bool overflowed: false
    command: ["omarchy-reminder", "show", "--json"]
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        if (jsonProc.overflowed) return
        jsonProc.stdoutBuf += chunk
        if (jsonProc.stdoutBuf.length > jsonProc.maxStdout) {
          jsonProc.overflowed = true
          jsonProc.stdoutBuf = ""
          jsonProc.signal(15)
          reminderKillTimer.start()
        }
      }
    }
    onStarted: {
      reminderKillTimer.stop()
      stdoutBuf = ""
      overflowed = false
    }
    onExited: function(exitCode) {
      reminderKillTimer.stop()
      var raw = overflowed ? "" : String(stdoutBuf || "")
      stdoutBuf = ""
      overflowed = false
      if (exitCode !== 0) {
        root.reminderCount = 0
        root.tooltip = ""
        return
      }
      root.update(raw)
    }
  }

  Timer {
    id: reminderKillTimer
    interval: 2000
    onTriggered: jsonProc.signal(9)
  }

  onPressed: function() {
    if (root.reminderCount > 0) Quickshell.execDetached(["omarchy-reminder", "show"])
    else root.openReminderFlow()
  }
}

import QtQuick
import Quickshell
import Quickshell.Io
import "NotificationsModel.js" as Model

// The one place that talks to dunst for the notification widget, shared by
// every bar. dunst stays the notification daemon; this only reads its state
// and history, and re-reads them when dunst signals a change.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  // False until dunst answers.
  property bool available: false
  property bool paused: false
  property int waiting: 0
  property var entries: []
  // Entries the panel has shown. Whatever is already in the history when the
  // shell starts counts as seen.
  property var seen: ({})
  property bool seeded: false
  readonly property int unseenCount: Object.keys(Model.unseenKeys(entries, seen)).length

  property var wallTimes: ({})
  property bool refreshQueued: false

  function refresh() {
    if (stateProc.running) {
      root.refreshQueued = true
      return
    }
    stateProc.running = true
  }

  function apply(raw) {
    var state = Model.parseState(raw, Date.now(), root.wallTimes)
    if (!state) return
    root.wallTimes = state.wallTimes
    if (!root.seeded) {
      root.seen = Model.allKeys(state.entries)
      root.seeded = true
    }
    root.paused = state.paused
    root.waiting = state.waiting
    root.entries = state.entries
    root.available = true
  }

  function markSeen() {
    root.seen = Model.allKeys(root.entries)
  }

  function remove(id) { Quickshell.execDetached(["dunstctl", "history-rm", String(id)]) }
  function showAgain(id) { Quickshell.execDetached(["dunstctl", "history-pop", String(id)]) }
  function clearAll() { Quickshell.execDetached(["dunstctl", "history-clear"]) }
  // The command also refreshes the bar's Do Not Disturb indicator.
  function toggleDnd() { Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-toggle-notification-silencing"]) }

  Process {
    id: stateProc
    command: ["bash", root.omarchyPath + "/shell/scripts/notifications-state.sh"]
    stdout: StdioCollector {
      id: stateOutput
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.apply(stateOutput.text)
      } else {
        root.available = false
        root.entries = []
        root.waiting = 0
        root.paused = false
      }
      if (root.refreshQueued) {
        root.refreshQueued = false
        Qt.callLater(root.refresh)
      }
    }
  }

  // Signals only: dunst's counts and pause state, history removals, and the
  // notification name changing hands when dunst restarts.
  Process {
    id: monitorProc
    command: ["gdbus", "monitor", "--session",
      "--dest", "org.freedesktop.Notifications",
      "--object-path", "/org/freedesktop/Notifications"]
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        if (line.indexOf("org.dunstproject.cmd0") !== -1 || line.indexOf("The name ") === 0)
          settle.start()
      }
    }
    onExited: monitorRestart.start()
  }

  Timer {
    id: monitorRestart
    interval: 5000
    onTriggered: {
      monitorProc.running = true
      root.refresh()
    }
  }

  // One read per burst of signals. Not restarted by later signals, so a steady
  // stream cannot postpone it forever.
  Timer {
    id: settle
    interval: 150
    onTriggered: root.refresh()
  }

  Component.onCompleted: refresh()
}

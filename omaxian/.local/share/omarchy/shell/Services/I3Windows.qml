pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.I3
import qs.Commons

// Live i3 window list — the piece `Quickshell.I3` doesn't expose itself
// (I3.workspaces/I3.monitors have no window tree; see
// plugins/bar/widgets/Workspaces.qml's own comment on this). Backs the dock
// plugin's running-app tracking (local, Services/qmldir).
//
// Seeded once from `i3-msg -t get_tree` (a plain tree walk — same fields the
// old, unused `scripts/windows-json.sh` extracted via jq: window_properties
// .class, name), then kept live via `I3IpcListener`, which delivers i3's raw
// IPC event stream in-process — no `i3-msg -t subscribe` subprocess needed.
QtObject {
  id: root

  // { conId, appId, title, workspace, focused, urgent }
  property var windows: []
  property var focusedWindow: null

  function focusWindow(conId) {
    if (conId === undefined || conId === null) return
    // `unset I3SOCK`: same guard as Workspaces.qml's focusWorkspace() — i3's
    // own /proc/environ keeps a stale socket path across an in-place
    // restart; unsetting it makes i3-msg fall back to the live
    // I3_SOCKET_PATH X root-window property.
    Util.execDetached("unset I3SOCK; exec i3-msg -q '[con_id=" + Number(conId) + "] focus'")
  }

  // A retree in flight can't be restarted; record the request and re-run once
  // it lands, so a burst (new + focus + move within a few ms) doesn't drop the
  // final authoritative walk.
  property bool _refreshQueued: false

  // i3 fires `window::new` the instant the frame maps — usually before the X11
  // client has set WM_CLASS, so that first retree sees an empty appId and
  // _walk() drops the window (it needs class||instance). i3 emits no
  // "property changed" event, so re-walk once more after the client settles.
  property Timer _settleTimer: Timer {
    interval: 400
    onTriggered: root.refresh()
  }

  function refresh() {
    if (getTree.running) { root._refreshQueued = true; return }
    getTree.running = true
  }

  function _walk(node, workspaceName, out) {
    if (!node || typeof node !== "object") return
    var ws = workspaceName
    if (node.type === "workspace") ws = String(node.name || "")

    if (node.window !== undefined && node.window !== null) {
      var props = node.window_properties || {}
      var appId = String(props.class || props.instance || "")
      if (appId.length > 0) {
        out.push({
          conId: node.id,
          appId: appId,
          title: String(node.name || ""),
          workspace: ws,
          focused: node.focused === true,
          urgent: node.urgent === true
        })
      }
    }

    var kids = (node.nodes || []).concat(node.floating_nodes || [])
    for (var i = 0; i < kids.length; i++) root._walk(kids[i], ws, out)
  }

  function _applyTree(rawText) {
    var parsed = null
    try {
      parsed = JSON.parse(rawText)
    } catch (e) {
      return
    }
    if (!parsed) return

    var out = []
    root._walk(parsed, "", out)
    root.windows = out
    root._syncFocused()
  }

  function _syncFocused() {
    for (var i = 0; i < root.windows.length; i++) {
      if (root.windows[i].focused) {
        root.focusedWindow = root.windows[i]
        return
      }
    }
    root.focusedWindow = null
  }

  // Patch a single window's fields in place, keyed by con_id, instead of a
  // full retree — cheap enough to run on every window/workspace event
  // without churning the whole list on every keystroke of a title change.
  function _patchWindow(conId, patch) {
    var list = root.windows
    for (var i = 0; i < list.length; i++) {
      if (list[i].conId === conId) {
        var next = list.slice()
        next[i] = Object.assign({}, list[i], patch)
        root.windows = next
        return true
      }
    }
    return false
  }

  function _removeWindow(conId) {
    var list = root.windows
    var next = []
    for (var i = 0; i < list.length; i++) {
      if (list[i].conId !== conId) next.push(list[i])
    }
    root.windows = next
  }

  function _handleWindowEvent(payload) {
    var change = String(payload.change || "")
    var container = payload.container || null
    if (!container) return

    if (change === "new") {
      root.refresh()
      root._settleTimer.restart()
      return
    }
    if (change === "close") {
      root._removeWindow(container.id)
      root._syncFocused()
      return
    }
    if (change === "focus") {
      var found = false
      var list = root.windows
      var next = []
      for (var i = 0; i < list.length; i++) {
        var w = list[i]
        next.push(w.conId === container.id ? Object.assign({}, w, { focused: true }) : (w.focused ? Object.assign({}, w, { focused: false }) : w))
        if (w.conId === container.id) found = true
      }
      root.windows = next
      if (!found) root.refresh()
      else root._syncFocused()
      return
    }
    if (change === "title") {
      // A patch miss means we never recorded this window (dropped at `new`
      // time with no WM_CLASS yet) — retree to pick it up now.
      if (!root._patchWindow(container.id, { title: String(container.name || "") }))
        root.refresh()
      return
    }
    if (change === "urgent") {
      if (!root._patchWindow(container.id, { urgent: container.urgent === true }))
        root.refresh()
      return
    }
    if (change === "move") {
      root.refresh()
      return
    }
  }

  property Process getTree: Process {
    command: ["bash", "-c", "unset I3SOCK; exec i3-msg -t get_tree"]
    stdout: StdioCollector {
      onStreamFinished: {
        root._applyTree(text)
        if (root._refreshQueued) {
          root._refreshQueued = false
          Qt.callLater(root.refresh)
        }
      }
    }
  }

  property I3IpcListener listener: I3IpcListener {
    subscriptions: ["window", "workspace"]
    onIpcEvent: function(event) {
      var payload = null
      try {
        payload = JSON.parse(event.data)
      } catch (e) {
        return
      }
      if (!payload) return

      if (event.type === "window") {
        root._handleWindowEvent(payload)
      } else if (event.type === "workspace") {
        // Cheapest correct response to a workspace change (focus, move,
        // rename, empty-workspace destroy) is a full retree — none of these
        // are as hot a path as a window title/focus change.
        root.refresh()
      }
    }
  }

  Component.onCompleted: root.refresh()
}

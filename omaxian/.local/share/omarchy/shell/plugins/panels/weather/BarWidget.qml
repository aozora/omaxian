import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.weather"

  property string statusNotifyBuf: ""

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function refresh() {
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  // Shape contract for shell.summon/hide/toggle routing (Bar.findPanelWidget
  // requires open/close/opened on the bar-widget root). Open maps to the
  // panel's hotkey path so summoning suppresses the center hover reveal,
  // matching what the old per-plugin IpcHandler did.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  // Forwarded so this widget can stand in for the panel as the bar's popout
  // identity: Bar.requestPopout prefers closeForPopoutSwitch over close, and
  // KeyboardPanel reads popoutSwitchClosing back off its owner.
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function notifyStatus() {
    if (statusNotifyProc.running) return
    root.statusNotifyBuf = ""
    statusNotifyProc.running = true
  }

  visible: panelLoader.item && panelLoader.item.label !== ""
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Binding {
    target: panelLoader.item
    property: "settings"
    value: root.settings
    restoreMode: Binding.RestoreNone
    when: panelLoader.item !== null
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  Process {
    id: statusNotifyProc
    command: ["omarchy-weather-status"]
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        if (root.statusNotifyBuf.length > 512) {
          statusNotifyProc.signal(15)
          statusNotifyKill.start()
          return
        }
        root.statusNotifyBuf += String(chunk || "")
        if (root.statusNotifyBuf.length > 512) {
          statusNotifyProc.signal(15)
          statusNotifyKill.start()
          root.statusNotifyBuf = ""
        }
      }
    }
    onExited: function(exitCode) {
      var raw = root.statusNotifyBuf
      root.statusNotifyBuf = ""
      if (exitCode !== 0 || !String(raw || "").trim()) return
      Util.notify(raw)
    }
  }

  Timer {
    id: statusNotifyKill
    interval: 2000
    repeat: false
    onTriggered: statusNotifyProc.signal(9)
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: panelLoader.item ? Util.plain(panelLoader.item.label) : ""
    slotSize: Style.bar.statusSlot
    // Tooltip suppressed because the panel is the detail view.
    tooltipText: ""

    onPressed: function(b) {
      if (!root.bar) return
      if (b === Qt.RightButton) root.notifyStatus()
      else if (b === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }
  }
}

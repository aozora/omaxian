import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Control Panel tab: Bluetooth adapter + device list. A fresh
// reimplementation of plugins/panels/bluetooth/Panel.qml's content — Control
// Panel is a standalone plugin, this file has no runtime dependency on the
// original.
//
// Deliberately simplified vs. the original:
//  - No keyboard-cursor navigation (focusSection/selectedIndex/moveCursor) —
//    same simplification as AudioTab, mouse-driven only.
//  - Discovery start/stop is still tracked (owesDiscoveryStop) so closing
//    this tab doesn't leave the radio stuck scanning, but the multi-monitor
//    sibling handoff (openSibling()/Component.onDestruction in the
//    original) is dropped: each Control Panel instance now manages its own
//    discovery debt independently. Only matters if bluetooth tabs are open
//    on two monitors' Control Panels at the same moment — worst case there
//    is a redundant stop/restart blip, not a stuck scan.
Item {
  id: root

  // Not `required`: injected by Control Panel's Loader.setSource() map —
  // see AudioTab.qml for the rationale.
  property QtObject bar: null
  property bool active: false

  // address -> "connecting" | "disconnecting" | "forgetting"
  property var pendingActions: ({})
  property bool owesDiscoveryStop: false

  readonly property var adapter: Bluetooth.defaultAdapter
  readonly property var devices: Bluetooth.devices ? Bluetooth.devices.values : []
  readonly property var deviceGroups: Model.deviceLists(devices)
  readonly property var connectedDevices: deviceGroups.connected || []
  readonly property var knownDevices: deviceGroups.known || []
  readonly property var discoveredDevices: (adapter && adapter.discovering) ? (deviceGroups.discovered || []) : []

  readonly property string icon: {
    if (!adapter) return "󰂲"
    if (!adapter.enabled) return "󰂲"
    if (connectedDevices.length > 0) return "󰂱"
    return "󰂯"
  }

  readonly property string heroStatusText: {
    if (!adapter) return "No adapter"
    if (!adapter.enabled) return "Turned off"
    if (connectedDevices.length > 0) return "Connected"
    return adapter.discovering ? "Scanning…" : "On"
  }

  implicitWidth: Style.space(380)
  implicitHeight: column.implicitHeight

  function toggleBluetooth() {
    if (!adapter) return
    Quickshell.execDetached(["omarchy-bluetooth-power", adapter.enabled ? "off" : "on"])
  }

  function pendingAction(address) { return Model.pendingAction(pendingActions, address) }

  function setPendingAction(address, action) {
    if (!address) return
    pendingActions = Model.withPendingAction(pendingActions, address, action)
    if (action) pendingTimeout.restart()
  }

  function deviceCommand(action, address) {
    return ["omarchy-bluetooth-device", action, address]
  }

  function runDeviceAction(device, action, pending) {
    if (!device || !device.address) return
    setPendingAction(device.address, pending)
    Quickshell.execDetached(deviceCommand(action, device.address))
  }

  function connectDevice(device) {
    if (!device || device.connected) return
    if (device.paired || device.bonded || device.trusted) runDeviceAction(device, "connect", "connecting")
    else runDeviceAction(device, "pair", "connecting")
  }

  function disconnectDevice(device) {
    if (!device || !device.address || !device.connected) return
    setPendingAction(device.address, "disconnecting")
    if (device.disconnect) device.disconnect()
    Quickshell.execDetached(deviceCommand("disconnect", device.address))
  }

  function forgetDevice(device) {
    if (!device || !device.address) return
    runDeviceAction(device, "forget", "forgetting")
  }

  function syncPendingActions() {
    var next = Model.cloneMap(pendingActions)
    var changed = false
    for (var address in next) {
      var action = next[address]
      var found = null
      for (var i = 0; i < devices.length; i++) {
        if (devices[i] && devices[i].address === address) { found = devices[i]; break }
      }
      var finishedConnecting = action === "connecting" && found && found.connected
      if (finishedConnecting
          || (action === "disconnecting" && found && !found.connected)
          || (action === "forgetting" && (!found || (!found.paired && !found.bonded && !found.trusted)))) {
        delete next[address]
        changed = true
      }
    }
    if (changed) pendingActions = next
  }

  onConnectedDevicesChanged: syncPendingActions()
  onKnownDevicesChanged: syncPendingActions()
  onDiscoveredDevicesChanged: syncPendingActions()

  onActiveChanged: if (active && adapter !== null && adapter.discovering) owesDiscoveryStop = true

  Timer {
    id: discoveryRetry
    interval: 1000
    repeat: true
    triggeredOnStart: true
    running: root.active && root.adapter !== null && root.adapter.enabled && !root.adapter.discovering
    onTriggered: {
      root.owesDiscoveryStop = true
      root.adapter.discovering = true
    }
  }

  Timer {
    id: discoveryStop
    interval: 1000
    repeat: true
    property int attempts: 0
    running: !root.active && root.owesDiscoveryStop && root.adapter !== null && root.adapter.discovering === true
    onRunningChanged: if (running) attempts = 0
    onTriggered: {
      attempts += 1
      if (attempts > 3) { root.owesDiscoveryStop = false; return }
      root.adapter.discovering = false
    }
  }

  Connections {
    target: root.adapter
    function onDiscoveringChanged() {
      if (root.adapter && !root.adapter.discovering) root.owesDiscoveryStop = false
    }
  }

  Timer {
    id: pendingTimeout
    interval: 20000
    repeat: false
    onTriggered: root.pendingActions = ({})
  }

  Column {
    id: column
    width: parent.width
    spacing: Style.space(14)

    // ---------- Hero ----------
    Item {
      width: parent.width
      implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, powerSwitch.implicitHeight)

      Text {
        id: heroIcon
        textFormat: Text.PlainText
        text: root.icon
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.display
        opacity: root.adapter && root.adapter.enabled ? 1.0 : 0.5
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      ToggleSwitch {
        id: powerSwitch
        visible: !!root.adapter
        checked: !!root.adapter && root.adapter.enabled
        foreground: root.bar.foreground
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        onToggled: root.toggleBluetooth()
      }

      Column {
        id: heroLabels
        anchors.left: heroIcon.right
        anchors.leftMargin: Style.space(14)
        anchors.right: parent.right
        anchors.rightMargin: powerSwitch.visible ? powerSwitch.width + Style.space(12) : 0
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Text {
          text: "Bluetooth"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
          elide: Text.ElideRight
          width: parent.width
        }

        Text {
          textFormat: Text.PlainText
          text: root.heroStatusText.toUpperCase()
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1.2
          elide: Text.ElideRight
          width: parent.width
        }
      }
    }

    PanelSeparator { foreground: root.bar.foreground }

    Column {
      width: parent.width
      spacing: Style.space(10)
      visible: root.connectedDevices.length > 0

      PanelSectionHeader {
        text: "CONNECTED"
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
      }

      Repeater {
        model: root.connectedDevices
        DeviceRow {
          required property var modelData
          width: column.width
          dev: modelData
          bar: root.bar
          isDiscovered: false
          pendingActionText: root.pendingAction(modelData.address)
          onConnectRequested: root.disconnectDevice(modelData)
          onForgetRequested: root.forgetDevice(modelData)
        }
      }
    }

    PanelSeparator {
      visible: root.knownDevices.length > 0
      foreground: root.bar.foreground
    }

    Column {
      width: parent.width
      spacing: Style.space(10)
      visible: root.knownDevices.length > 0

      PanelSectionHeader {
        text: "PAIRED"
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
      }

      Repeater {
        model: root.knownDevices
        DeviceRow {
          required property var modelData
          width: column.width
          dev: modelData
          bar: root.bar
          isDiscovered: false
          pendingActionText: root.pendingAction(modelData.address)
          onConnectRequested: root.connectDevice(modelData)
          onForgetRequested: root.forgetDevice(modelData)
        }
      }
    }

    PanelSeparator {
      visible: root.discoveredDevices.length > 0
      foreground: root.bar.foreground
    }

    Column {
      width: parent.width
      spacing: Style.space(10)
      visible: root.discoveredDevices.length > 0

      PanelSectionHeader {
        text: "AVAILABLE"
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
      }

      Repeater {
        model: root.discoveredDevices
        DeviceRow {
          required property var modelData
          width: column.width
          dev: modelData
          bar: root.bar
          isDiscovered: true
          pendingActionText: root.pendingAction(modelData.address)
          onConnectRequested: root.connectDevice(modelData)
        }
      }
    }

    Text {
      textFormat: Text.PlainText
      visible: root.connectedDevices.length === 0 && root.knownDevices.length === 0 && root.discoveredDevices.length === 0
      text: !root.adapter ? "No Bluetooth adapter"
          : !root.adapter.enabled ? "Turn Bluetooth on to scan"
          : "Scanning for devices…"
      color: Qt.darker(root.bar.foreground, 1.5)
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
      width: parent.width
    }
  }

  component DeviceRow: CursorSurface {
    id: row
    required property var dev
    property QtObject bar: null
    property bool isDiscovered: false
    property string pendingActionText: ""

    signal connectRequested()
    signal forgetRequested()

    readonly property bool isConnected: dev && dev.connected
    readonly property int devState: dev && dev.state !== undefined ? dev.state : -1
    readonly property string actionTooltip: isConnected ? "Disconnect" : (isDiscovered ? "Pair" : "Connect")
    readonly property bool forgetAvailable: !isDiscovered
    readonly property bool showForgetButton: forgetAvailable && rowMouse.containsMouse

    hasCursor: rowMouse.containsMouse
    current: isConnected
    foreground: bar ? bar.foreground : Color.foreground

    readonly property string statusText: {
      if (!dev) return ""
      if (pendingActionText === "forgetting") return "Forgetting…"
      if (pendingActionText === "disconnecting" || devState === 2) return "Disconnecting…"
      if (isConnected) {
        if (dev.batteryAvailable) return Math.round(dev.battery * 100) + "%"
        return ""
      }
      if (pendingActionText === "connecting" || devState === 3 || dev.pairing === true) return "Connecting…"
      return ""
    }

    readonly property color statusColor: {
      var fg = bar ? bar.foreground : Color.foreground
      if (isConnected) return fg
      if (pendingActionText !== "" || devState === 3 || dev.pairing === true) return fg
      return Qt.darker(fg, 1.5)
    }

    implicitHeight: rowContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: row.dev ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) {
          if (row.isConnected) row.connectRequested()
          else if (!row.isDiscovered) row.forgetRequested()
          return
        }
        row.connectRequested()
      }
    }

    PanelToolTip {
      visible: row.actionTooltip !== "" && rowMouse.containsMouse
      text: row.actionTooltip
      fontFamily: row.bar ? row.bar.fontFamily : Style.font.family
    }

    Item {
      id: rowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      implicitHeight: Math.max(deviceIcon.implicitHeight, info.implicitHeight, forgetBtn.implicitHeight)

      Text {
        id: deviceIcon
        textFormat: Text.PlainText
        text: row.isConnected ? "󰂱" : "󰂯"
        color: row.statusColor
        font.family: row.bar ? row.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.heading
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Column {
        id: info
        spacing: Style.space(1)
        anchors.left: deviceIcon.right
        anchors.leftMargin: Style.space(10)
        anchors.right: forgetBtn.visible ? forgetBtn.left : parent.right
        anchors.rightMargin: forgetBtn.visible ? Style.space(8) : 0
        anchors.verticalCenter: parent.verticalCenter

        Text {
          textFormat: Text.PlainText
          text: Model.deviceLabel(row.dev) || "Device"
          color: row.bar ? row.bar.foreground : Color.foreground
          font.family: row.bar ? row.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          width: parent.width
        }

        Text {
          textFormat: Text.PlainText
          visible: row.statusText !== ""
          text: row.statusText
          color: row.statusColor
          font.family: row.bar ? row.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          width: parent.width
        }
      }

      PanelActionButton {
        id: forgetBtn
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: row.showForgetButton
        iconText: "󰅙"
        tooltipText: "Forget"
        foreground: row.bar ? row.bar.foreground : Color.foreground
        hoverColor: row.bar ? row.bar.foreground : Color.foreground
        fontFamily: row.bar ? row.bar.fontFamily : Style.font.family
        onClicked: row.forgetRequested()
      }
    }
  }
}

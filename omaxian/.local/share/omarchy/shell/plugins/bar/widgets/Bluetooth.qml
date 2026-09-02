import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs.Commons
import qs.Services
import qs.Ui

// New, simplified against Quickshell.Bluetooth (BlueZ/DBus — desktop-agnostic,
// no Wayland dependency). eww's bluetooth-module builds a rich per-device-type
// icon string by shelling out to `bluetoothctl`; reproducing that exactly
// isn't worth it when Quickshell already exposes live adapter/device state
// directly — this shows a generic bluetooth glyph, dims when the adapter is
// off, and lists connected device names in the tooltip. Click opens
// `scripts/bluetooth-menu.sh` (blueman-manager) rather than building a
// themed pairing UI — see
// docs/quickshell/widget-mapping.md, `panels/bluetooth` was scoped as a
// "Port" for a future popup, not required for bar parity with eww.
BarWidget {
  id: root
  moduleName: "omaxian.bluetooth"

  readonly property var adapter: Bluetooth.defaultAdapter
  readonly property bool enabled: adapter && adapter.enabled
  readonly property var connectedDevices: {
    var names = []
    if (Bluetooth.devices) {
      for (var i = 0; i < Bluetooth.devices.values.length; i++) {
        var dev = Bluetooth.devices.values[i]
        if (dev && dev.connected) names.push(dev.name || dev.deviceName)
      }
    }
    return names
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    fontSize: Style.font.body + 3
    // Exact glyphs verified from eww/scripts/bluetooth.sh (off/on/connected),
    // not guessed — a first attempt using a different codepoint rendered as
    // nothing (blank glyph) in this profile's JetBrainsMono Nerd Font build.
    text: !root.enabled ? "󰂲" : root.connectedDevices.length > 0 ? "󰂱" : "󰂯"
    foreground: root.enabled ? BarPalette.bluetooth : Color.muted
    tooltipText: !root.enabled ? "Bluetooth off"
      : root.connectedDevices.length > 0 ? root.connectedDevices.join(", ")
      : "Bluetooth on"
    horizontalMargin: 8.5
    verticalPadding: 6
    onPressed: function(mouseButton) {
      root.bar.run(Quickshell.shellDir + "/scripts/bluetooth-menu.sh")
    }
  }
}

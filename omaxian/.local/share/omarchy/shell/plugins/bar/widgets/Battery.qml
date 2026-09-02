import QtQuick
import Quickshell.Services.UPower
import qs.Commons
import qs.Services
import qs.Ui

// New (not a port — omarchy-quattro splits this across services/battery +
// panels/power; this profile only needs eww's simple bar pill, no popup
// panel). UPower is DBus, desktop-agnostic. Matches eww's battery-module:
// hidden entirely when no battery is present (desktop machines), no click
// action, icon tiers by percentage + charging state.
BarWidget {
  id: root
  moduleName: "omaxian.battery"

  readonly property var device: UPower.displayDevice
  readonly property bool present: device && device.isPresent
  readonly property real percent: present ? device.percentage * 100 : 0
  readonly property bool charging: present && (device.state === UPowerDeviceState.Charging || device.state === UPowerDeviceState.PendingCharge)

  // Exact glyphs + thresholds copied from eww/scripts/battery.sh (verified
  // working in this profile's Nerd Font) rather than retyped from memory —
  // a first pass here used unverified nearby codepoints for the middle
  // tiers and several didn't render (see Bluetooth.qml's comment for the
  // same lesson learned on that widget).
  function glyph() {
    if (charging) return "󰂄"
    if (percent <= 10) return "󰁺"
    if (percent <= 25) return "󰁻"
    if (percent <= 50) return "󰁽"
    if (percent <= 75) return "󰁿"
    return "󰁹"
  }

  visible: present
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    fontSize: Style.font.body + 3
    text: root.present ? (root.glyph() + " " + Math.round(root.percent) + "%") : ""
    foreground: BarPalette.battery
    interactive: false
    horizontalMargin: 8.5
    verticalPadding: 6
  }
}

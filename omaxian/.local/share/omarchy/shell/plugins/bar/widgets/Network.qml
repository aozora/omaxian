import QtQuick
import Quickshell
import Quickshell.Networking
import qs.Commons
import qs.Services
import qs.Ui

// New, against Quickshell.Networking (NetworkManager/DBus — desktop-agnostic).
// eww's network-module shells out to `nmcli`/`ip route` for SSID+signal;
// Quickshell already surfaces the same NetworkManager state directly, so
// this reads it live instead of polling a script. Click opens
// `scripts/network-menu.sh` (nm-connection-editor, else nmtui) rather than
// building a themed Wi-Fi picker — same reasoning as Bluetooth.qml.
BarWidget {
  id: root
  moduleName: "omaxian.network"

  readonly property var activeWifi: {
    for (var i = 0; i < Networking.devices.values.length; i++) {
      var dev = Networking.devices.values[i]
      if (dev.type !== DeviceType.Wifi || !dev.connected) continue
      for (var j = 0; j < dev.networks.values.length; j++) {
        var net = dev.networks.values[j]
        if (net.connected) return net
      }
    }
    return null
  }
  readonly property var activeWired: {
    for (var i = 0; i < Networking.devices.values.length; i++) {
      var dev = Networking.devices.values[i]
      if (dev.type === DeviceType.Wired && dev.connected) return dev
    }
    return null
  }

  // Exact glyphs copied from eww/scripts/network.sh (verified working in
  // this profile's Nerd Font): eww itself only has one "connected" wifi
  // icon regardless of signal strength (it shows the signal % as text
  // instead of tiering the icon) and one disconnected icon — a first pass
  // here invented unverified per-tier icons from memory and the
  // disconnected one was simply wrong (off-by-one codepoint that doesn't
  // render). Matching eww's actual (simpler) behavior instead of a richer
  // one that turned out to be guesswork.
  function glyph() {
    if (activeWired) return "󰈀"
    if (activeWifi) return "󰤨"
    return "󰤮"
  }

  // SSID hidden from the always-visible bar label (screen-sharing/
  // screenshot privacy) — matches eww's actual network-module, which
  // showed signal strength as a percentage, not the network name either.
  // The name is still one hover away in the tooltip.
  // signalStrength is a 0.0-1.0 fraction, not a 0-100 percentage — confirmed
  // live against `nmcli dev wifi` (real signal 66% rendered as "1%" before
  // this fix, i.e. Math.round(0.66)).
  readonly property string label: activeWired ? "Wired"
    : activeWifi ? Math.round(activeWifi.signalStrength * 100) + "%"
    : "Disconnected"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    fontSize: Style.font.body + 3
    text: root.glyph() + " " + root.label
    foreground: (root.activeWifi || root.activeWired) ? BarPalette.network : Color.muted
    tooltipText: root.activeWifi ? root.activeWifi.name : ""
    horizontalMargin: 8.5
    verticalPadding: 6
    onPressed: function(mouseButton) {
      root.bar.run(Quickshell.shellDir + "/scripts/network-menu.sh")
    }
  }
}

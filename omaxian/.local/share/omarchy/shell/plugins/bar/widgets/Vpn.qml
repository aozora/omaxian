import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services
import qs.Ui

// New — no omarchy-quattro equivalent (WireGuard/NymVPN detection is
// bespoke to this profile). Ported unchanged: `scripts/vpn.sh` checks a raw
// WireGuard link, then an NM WireGuard active connection, then NymVPN
// (process + tun interface), polled on the same 5s interval eww used.
// Glyphs copied exactly from the i3/polybar vpn.sh script (shield+check
// U+F0565 on, shield+slash U+F512 off) rather than the earlier lock icons.
BarWidget {
  id: root
  moduleName: "omaxian.vpn"

  property bool on: false

  Timer {
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: proc.running = true
  }

  Process {
    id: proc
    command: ["bash", Quickshell.shellDir + "/scripts/vpn.sh"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.on = text.trim().length > 0 && text.trim().codePointAt(0) === 0xf0565
      }
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    fontSize: Style.font.body + 1
    text: root.on ? "󰕥" : ""
    foreground: root.on ? BarPalette.vpnOn : BarPalette.vpnOff
    horizontalMargin: 8.5
    verticalPadding: 6
    onPressed: root.bar.run(Quickshell.shellDir + "/scripts/network-menu.sh")
  }
}

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// X11 stand-in for upstream's Hyprland `activelayout` IPC +
// `switchxkblayout current next`. No i3 event source, so the label is a 2s
// poll of `scripts/keyboard.sh` (xprop + XkbGetState). Click cycles via
// that script: xkb-switch, else ISO_Next_Group (grp:win_space_toggle),
// else a setxkbmap layout-list rotate.
BarWidget {
  id: root
  moduleName: "omarchy.keyboard-layout"

  property string display: ""

  function refresh() {
    if (!proc.running) proc.running = true
  }

  function cycle() {
    if (!cycleProc.running) cycleProc.running = true
  }

  Timer {
    interval: 2000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: proc
    command: ["bash", Quickshell.shellDir + "/scripts/keyboard.sh"]
    stdout: StdioCollector {
      onStreamFinished: {
        var t = text.trim()
        if (t.length > 0) root.display = t
      }
    }
  }

  Process {
    id: cycleProc
    command: ["bash", Quickshell.shellDir + "/scripts/keyboard.sh", "next"]
    stdout: StdioCollector {
      onStreamFinished: {
        var t = text.trim()
        if (t.length > 0) root.display = t
      }
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    fontSize: Style.font.body
    text: root.display
    tooltipText: "Next keyboard layout"
    horizontalMargin: 8.5
    verticalPadding: 6
    onPressed: root.cycle()
  }
}

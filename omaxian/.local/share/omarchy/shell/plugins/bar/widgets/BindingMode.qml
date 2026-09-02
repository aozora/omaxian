import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services
import qs.Ui

// i3 binding-mode indicator (polybar-style "[resize on]"). Subscribes to the
// i3 IPC `mode` event and shows a pill while any non-default mode is active
// (Resize / Move / Gaps …); collapses to zero width in the default mode.
// `unset I3SOCK` for the same stale-socket reason as Workspaces.qml.
BarWidget {
  id: root
  moduleName: "omaxian.mode"

  property string mode: "default"
  readonly property bool active: mode !== "default" && mode !== ""
  // Mode names can be long ("Gaps: (o)uter, (i)nner") — keep the first word.
  readonly property string shortMode: {
    var w = mode.replace(/[^A-Za-z].*$/, "")
    return (w || mode).toLowerCase()
  }

  Process {
    running: true
    command: ["bash", "-c", "unset I3SOCK; exec i3-msg -t subscribe -m '[\"mode\"]'"]
    stdout: SplitParser {
      onRead: function(line) {
        var t = String(line || "").trim()
        if (!t)
          return
        try {
          var o = JSON.parse(t)
          if (o && typeof o.change === "string")
            root.mode = o.change
        } catch (e) {}
      }
    }
  }

  // Slot fills the bar cross-axis so the left/right Row (top-aligned children)
  // still parks this widget on the bar midline; the pill itself is inset.
  implicitWidth: root.active ? pill.implicitWidth : 0
  implicitHeight: root.active ? root.barSize : 0
  visible: root.active

  Rectangle {
    id: pill
    anchors.verticalCenter: parent.verticalCenter
    anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
    implicitWidth: label.implicitWidth + Style.space(16)
    implicitHeight: root.barSize - Style.space(6)
    radius: Style.cornerRadius
    color: Color.urgent

    Text {
      id: label
      anchors.centerIn: parent
      text: "[" + root.shortMode + " on]"
      color: Color.background
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      font.bold: true
    }
  }
}

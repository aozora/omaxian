import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services
import qs.Ui

// Keybindings cheatsheet. Rows come from scripts/help-bindings.py, which
// prefers `i3-msg -t get_config` (live loaded config) over on-disk files so
// the sheet matches what i3 is actually running — not a stale Archcraft map.
BarWidget {
  id: root
  moduleName: "omaxian.help"

  property bool menuOpen: false
  property var rows: []

  function refresh() { proc.running = true }

  IpcHandler {
    target: "help"
    function toggle(): void { root.menuOpen = !root.menuOpen }
    function hide(): void { root.menuOpen = false }
  }

  Process {
    id: proc
    command: ["python3", Quickshell.shellDir + "/scripts/help-bindings.py"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          root.rows = JSON.parse(text)
        } catch (e) {
          root.rows = []
        }
      }
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    fontSize: Style.font.body + 3
    text: "󰘥"
    foreground: Color.bar.text
    horizontalMargin: 8.5
    verticalPadding: 6
    onPressed: root.menuOpen = !root.menuOpen
  }

  PopupCard {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: helpOwner
    open: root.menuOpen
    contentWidth: Style.space(520)
    contentHeight: Style.space(480)

    onOpenChanged: if (open) root.refresh()

    ColumnLayout {
      anchors.fill: parent
      spacing: Style.spacing.sm

      Text {
        text: "Keybindings"
        color: BarPalette.popupHeaderAccent
        font.family: Style.font.family
        font.pixelSize: Style.font.title
        font.bold: true
      }

      ListView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        model: root.rows
        delegate: Item {
          required property var modelData
          width: ListView.view.width
          height: modelData.type === "header" ? Style.space(26) : Style.space(24)

          Text {
            visible: parent.modelData.type === "header"
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: parent.modelData.text
            color: BarPalette.popupHeaderAccent
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
          }

          RowLayout {
            visible: parent.modelData.type === "bind"
            anchors.fill: parent
            anchors.leftMargin: Style.spacing.sm

            Text {
              Layout.preferredWidth: Style.space(220)
              text: parent.parent.modelData.keys
              color: BarPalette.popupHelpKeys
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
            Text {
              Layout.fillWidth: true
              text: parent.parent.modelData.action
              color: BarPalette.popupSubtext
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }
        }
      }
    }
  }

  QtObject {
    id: helpOwner
    function close() { root.menuOpen = false }
  }
}

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.Commons
import qs.Services

// Control Panel tab: theme picker. A fresh copy of
// plugins/bar/widgets/ThemeButton.qml's popup content, re-hosted as one tab
// pane instead of its own bar-icon+popup pair — Control Panel is a
// standalone plugin, this file has no runtime dependency on the original.
Item {
  id: root

  property bool active: false
  property var themes: []

  implicitWidth: Style.space(1000)
  implicitHeight: Style.space(680)

  function refresh() { proc.running = true }

  // theme-set updates the current symlink asynchronously; delay so the
  // "current" border lands on the theme the user just picked.
  Timer {
    id: refreshAfterPick
    interval: 400
    repeat: false
    onTriggered: root.refresh()
  }

  onActiveChanged: if (active) root.refresh()

  // slug \t pretty \t previewPath \t current(1|empty), one row per theme.
  Process {
    id: proc
    command: ["bash", "-c",
      "cur=$(omarchy-theme-current 2>/dev/null); " +
      "omarchy-theme-list 2>/dev/null | while IFS= read -r name; do " +
      "[ -n \"$name\" ] || continue; " +
      "slug=$(printf '%s' \"$name\" | tr '[:upper:]' '[:lower:]' | tr ' ' '-'); " +
      "dir=$(omarchy-theme-dir \"$slug\" 2>/dev/null); " +
      "flag=; [ \"$name\" = \"$cur\" ] && flag=1; " +
      "printf '%s\\t%s\\t%s/preview.png\\t%s\\n' \"$slug\" \"$name\" \"$dir\" \"$flag\"; " +
      "done"]
    stdout: StdioCollector {
      onStreamFinished: {
        var out = []
        var lines = text.split("\n")
        for (var i = 0; i < lines.length; i++) {
          if (!lines[i]) continue
          var f = lines[i].split("\t")
          if (f.length < 3) continue
          out.push({ slug: f[0], pretty: f[1], preview: f[2], current: f[3] === "1" })
        }
        root.themes = out
      }
    }
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.spacing.md

    RowLayout {
      Layout.fillWidth: true
      Text {
        Layout.fillWidth: true
        text: "Theme"
        color: BarPalette.popupHeaderAccent
        font.family: Style.font.family
        font.pixelSize: Style.font.title
        font.bold: true
      }
      Text {
        text: root.themes.length + (root.themes.length === 1 ? " theme" : " themes")
        color: BarPalette.popupSubtext
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }

    GridView {
      id: grid
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      cellWidth: Style.space(300)
      cellHeight: Style.space(190)
      model: root.themes

      delegate: Item {
        id: cell
        required property int index
        required property var modelData
        width: grid.cellWidth
        height: grid.cellHeight

        ClippingRectangle {
          id: thumb
          anchors.fill: parent
          anchors.margins: Style.spacing.sm
          radius: Style.cornerRadius
          color: BarPalette.popupInputBackground
          border.width: cell.modelData.current ? 3 : (hoverHandler.hovered ? 2 : 0)
          border.color: cell.modelData.current
                        ? BarPalette.workspace.activeBackground
                        : Color.bar.text

          Image {
            anchors.fill: parent
            asynchronous: true
            cache: true
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: thumb.width
            sourceSize.height: thumb.height
            source: cell.modelData.preview ? "file://" + cell.modelData.preview : ""
          }

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: label.implicitHeight + Style.spacing.sm * 2
            color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.78)

            Text {
              id: label
              anchors.fill: parent
              anchors.margins: Style.spacing.sm
              text: cell.modelData.pretty
              color: cell.modelData.current
                     ? BarPalette.workspace.activeBackground
                     : Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              font.bold: cell.modelData.current
              verticalAlignment: Text.AlignVCenter
              elide: Text.ElideRight
            }
          }
        }

        HoverHandler { id: hoverHandler }
        TapHandler {
          onTapped: {
            Quickshell.execDetached(["omarchy-theme-set", cell.modelData.slug])
            // Stay open so the user can compare themes; refresh marks the new current.
            refreshAfterPick.restart()
          }
        }
      }
    }
  }
}

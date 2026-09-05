import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt.labs.folderlistmodel
import Quickshell
import qs.Commons
import qs.Ui

// Inline directory-only browser — the kit's "pick a folder" primitive. There
// is no native folder dialog on this stack, and a Ui/CenteredModal layered
// over a grabFocus PopupCard / KeyboardPanel steals the pointer grab and
// dismisses its own host. So this never creates a window: it's a plain Item
// the consumer overlays in place (anchors.fill + toggled `visible`), sitting
// on top of whatever content it replaces.
//
// Walks the filesystem with a dirs-only FolderListModel; the quick-jump row
// seeds common roots ($HOME, /, /mnt, /media, /run/media/$USER). Emits
// `chosen(path)` with an absolute path, or `cancelled()`.
Item {
  id: root

  // Absolute path to open at; falls back to $HOME when empty / missing.
  property string startPath: ""
  property string heading: "Choose a folder"

  // Palette — defaults suit the dark popup card both consumers live on.
  property color foreground: Color.popups.text
  property color subtext: Qt.darker(Color.popups.text, 1.5)
  property color surface: Color.popups.background

  signal chosen(string path)
  signal cancelled()

  property string currentPath: ""

  onVisibleChanged: {
    if (visible) Qt.callLater(function() { if (root.visible) keyCatcher.forceActiveFocus() })
  }

  function _norm(p) {
    var s = String(p || "").trim()
    while (s.length > 1 && s.charAt(s.length - 1) === "/") s = s.slice(0, -1)
    return s.length ? s : "/"
  }
  function _parent(p) {
    var s = _norm(p)
    if (s === "/") return "/"
    var i = s.lastIndexOf("/")
    return i <= 0 ? "/" : s.slice(0, i)
  }
  function _rescan() {
    dirModel.folder = ""
    dirModel.folder = "file://" + root.currentPath
  }

  onVisibleChanged: if (visible) {
    root.currentPath = _norm(root.startPath && root.startPath.length
                             ? root.startPath : Quickshell.env("HOME"))
    _rescan()
    keyCatcher.forceActiveFocus()
  }
  onCurrentPathChanged: _rescan()

  readonly property var quickRoots: {
    var user = Quickshell.env("USER")
    var home = Quickshell.env("HOME")
    return [
      { label: "Home", path: home },
      { label: "Filesystem", path: "/" },
      { label: "/mnt", path: "/mnt" },
      { label: "/media", path: "/media" },
      { label: "Removable", path: "/run/media/" + user }
    ]
  }

  FolderListModel {
    id: dirModel
    showDirs: true
    showFiles: false
    showDotAndDotDot: false
    showHidden: false
    showOnlyReadable: true
    sortField: FolderListModel.Name
  }

  // Opaque backing + event sink so the browser fully masks the content it
  // overlays (a stray click must not fall through to the grid below).
  Rectangle {
    anchors.fill: parent
    color: root.surface
  }
  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
  }

  Item {
    id: keyCatcher
    anchors.fill: parent
    focus: true
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Escape) {
        root.cancelled(); event.accepted = true
      } else if (event.key === Qt.Key_Backspace) {
        root.currentPath = root._parent(root.currentPath); event.accepted = true
      } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        root.chosen(root.currentPath); event.accepted = true
      }
    }

    ColumnLayout {
      anchors.fill: parent
      spacing: Style.spacing.md

      Text {
        text: root.heading
        color: root.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.title
        font.bold: true
      }

      Flow {
        Layout.fillWidth: true
        spacing: Style.spacing.sm
        Repeater {
          model: root.quickRoots
          delegate: Button {
            required property var modelData
            text: modelData.label
            bordered: true
            foreground: root.foreground
            fontSize: Style.font.bodySmall
            onClicked: root.currentPath = root._norm(modelData.path)
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.spacing.sm

        Button {
          text: "󰁍  Up"
          bordered: true
          enabled: root.currentPath !== "/"
          foreground: root.foreground
          fontSize: Style.font.bodySmall
          onClicked: root.currentPath = root._parent(root.currentPath)
        }
        Text {
          Layout.fillWidth: true
          text: root.currentPath
          color: root.subtext
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideMiddle
          verticalAlignment: Text.AlignVCenter
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        color: "transparent"
        radius: Style.cornerRadius
        border.width: Math.max(1, Style.space(1))
        border.color: root.subtext

        ListView {
          id: list
          anchors.fill: parent
          anchors.margins: Style.spacing.xs
          clip: true
          model: dirModel
          spacing: 0
          ScrollBar.vertical: ScrollBar {}

          delegate: Item {
            id: dirRow
            required property string fileName
            required property string filePath
            width: list.width
            height: Style.spacing.popupRowHeight

            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius
              color: rowHover.hovered
                     ? Style.hoverFillFor(root.foreground, Color.accent)
                     : "transparent"

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Style.spacing.sm
                anchors.rightMargin: Style.spacing.sm
                spacing: Style.spacing.sm

                Text {
                  text: "󰉋"
                  color: root.subtext
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }
                Text {
                  Layout.fillWidth: true
                  text: dirRow.fileName
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                  verticalAlignment: Text.AlignVCenter
                }
              }
            }

            HoverHandler { id: rowHover }
            TapHandler { onTapped: root.currentPath = root._norm(dirRow.filePath) }
          }
        }
      }

      Text {
        visible: dirModel.status === FolderListModel.Ready && dirModel.count === 0
        Layout.fillWidth: true
        text: "No sub-folders here."
        color: root.subtext
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.spacing.sm

        Item { Layout.fillWidth: true }

        Button {
          text: "Cancel"
          bordered: true
          foreground: root.foreground
          fontSize: Style.font.bodySmall
          onClicked: root.cancelled()
        }
        Button {
          text: "Use this folder"
          bordered: true
          selected: true
          foreground: root.foreground
          fontSize: Style.font.bodySmall
          onClicked: root.chosen(root.currentPath)
        }
      }
    }
  }
}

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt.labs.folderlistmodel
import Quickshell
import qs.Commons
import qs.Ui

// Inline filesystem browser — the kit's "pick a folder / file" primitive. There
// is no native folder dialog on this stack, and a Ui/CenteredModal layered
// over a grabFocus PopupCard / KeyboardPanel steals the pointer grab and
// dismisses its own host. So this never creates a window: it's a plain Item
// the consumer overlays in place (anchors.fill + toggled `visible`), sitting
// on top of whatever content it replaces.
//
// Default is dirs-only. Set `pickFiles: true` to also list image files
// (`nameFilters`) and confirm a file path. Emits `chosen(path)`, or `cancelled()`.
Item {
  id: root

  // Absolute path to open at; falls back to $HOME when empty / missing.
  property string startPath: ""
  property string heading: "Choose a folder"
  // When true, list image files and confirm a file (not a directory).
  property bool pickFiles: false
  property var nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.bmp"]

  // Palette — defaults suit the dark popup card both consumers live on.
  property color foreground: Color.popups.text
  property color subtext: Qt.darker(Color.popups.text, 1.5)
  property color surface: Color.popups.background

  signal chosen(string path)
  signal cancelled()

  property string currentPath: ""
  property string selectedFile: ""

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
  function _dirname(p) {
    var s = _norm(p)
    if (s.indexOf("/") < 0) return Quickshell.env("HOME")
    return _parent(s)
  }
  function _isImageName(name) {
    var lower = String(name || "").toLowerCase()
    return lower.endsWith(".png") || lower.endsWith(".jpg") || lower.endsWith(".jpeg")
      || lower.endsWith(".webp") || lower.endsWith(".bmp")
  }
  function _rescan() {
    dirModel.folder = ""
    dirModel.folder = "file://" + root.currentPath
  }
  function _confirm() {
    if (root.pickFiles) {
      if (root.selectedFile.length)
        root.chosen(root.selectedFile)
      return
    }
    root.chosen(root.currentPath)
  }

  onVisibleChanged: if (visible) {
    root.selectedFile = ""
    var start = root.startPath && root.startPath.length ? root.startPath : Quickshell.env("HOME")
    // File mode: if startPath points at a file, open its parent and preselect it.
    if (root.pickFiles && root._isImageName(start)) {
      root.selectedFile = root._norm(start)
      root.currentPath = root._dirname(start)
    } else {
      root.currentPath = root._norm(start)
    }
    _rescan()
    // Deferred: KeyboardPanel's open focus nudge can race this overlay.
    Qt.callLater(function() { if (root.visible) keyCatcher.forceActiveFocus() })
  }
  onCurrentPathChanged: {
    if (!root.pickFiles)
      root.selectedFile = ""
    else if (root.selectedFile.length && root._dirname(root.selectedFile) !== root.currentPath)
      root.selectedFile = ""
    _rescan()
  }

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
    showFiles: root.pickFiles
    showDotAndDotDot: false
    showHidden: false
    showOnlyReadable: true
    nameFilters: root.pickFiles ? root.nameFilters : []
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
        root._confirm(); event.accepted = true
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
          text: root.pickFiles && root.selectedFile.length
                ? root.selectedFile
                : root.currentPath
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
            id: entryRow
            required property string fileName
            required property string filePath
            required property bool fileIsDir
            width: list.width
            height: Style.spacing.popupRowHeight

            readonly property bool isSelected: root.pickFiles
              && !entryRow.fileIsDir
              && root._norm(entryRow.filePath) === root.selectedFile

            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius
              color: entryRow.isSelected
                     ? Style.hoverFillFor(root.foreground, Color.accent)
                     : (rowHover.hovered
                        ? Style.hoverFillFor(root.foreground, Color.accent)
                        : "transparent")
              opacity: entryRow.isSelected ? 1 : (rowHover.hovered ? 0.7 : 1)

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Style.spacing.sm
                anchors.rightMargin: Style.spacing.sm
                spacing: Style.spacing.sm

                Text {
                  text: entryRow.fileIsDir ? "󰉋" : "󰋩"
                  color: root.subtext
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }
                Text {
                  Layout.fillWidth: true
                  text: entryRow.fileName
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                  verticalAlignment: Text.AlignVCenter
                }
              }
            }

            HoverHandler { id: rowHover }
            TapHandler {
              onTapped: {
                if (entryRow.fileIsDir) {
                  root.currentPath = root._norm(entryRow.filePath)
                } else if (root.pickFiles) {
                  var path = root._norm(entryRow.filePath)
                  if (root.selectedFile === path)
                    root.chosen(path)
                  else
                    root.selectedFile = path
                }
              }
            }
          }
        }
      }

      Text {
        visible: dirModel.status === FolderListModel.Ready && dirModel.count === 0
        Layout.fillWidth: true
        text: root.pickFiles ? "No folders or images here." : "No sub-folders here."
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
          text: root.pickFiles ? "Use this file" : "Use this folder"
          bordered: true
          selected: true
          enabled: root.pickFiles ? root.selectedFile.length > 0 : true
          foreground: root.foreground
          fontSize: Style.font.bodySmall
          onClicked: root._confirm()
        }
      }
    }
  }
}

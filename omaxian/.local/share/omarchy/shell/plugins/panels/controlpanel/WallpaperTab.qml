import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.Commons
import qs.Services
import qs.Ui
import "Model.js" as Model

// Control Panel tab: wallpaper picker. Same FolderListModel grid as
// WallpaperButton — find|sort was picking up macOS AppleDouble `._*.jpg`
// sidecars (locale sort pairs them with the real file → empty odd columns).
// FolderListModel with showHidden: false skips those; FolderPicker stays
// inline (nested URL Loader failed to activate on click).
Item {
  id: root

  property bool active: false

  property string subTab: "theme"
  property string localFolder: ""
  readonly property bool folderPickerOpen: picker.visible

  readonly property string themeDir:
    Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/backgrounds"
  readonly property string activeDir: subTab === "folder" ? localFolder : themeDir

  implicitWidth: Style.space(1000)
  implicitHeight: Style.space(720)

  FileView {
    id: settingsFile
    path: Quickshell.env("HOME") + "/.config/omarchy/wallpaper-settings.json"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.localFolder = Model.parseWallpaperSettings(text()).localFolder
    onFileChanged: root.localFolder = Model.parseWallpaperSettings(text()).localFolder
    onLoadFailed: root.localFolder = ""
  }

  FolderListModel {
    id: bgModel
    showDirs: false
    showHidden: false
    showOnlyReadable: true
    sortField: FolderListModel.Name
    nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.bmp"]
  }

  // Imperative folder set: `current/theme` is a symlink that can keep the
  // same URL string while resolving elsewhere — clear first to force rescan.
  function refresh() {
    var target = root.activeDir.length ? "file://" + root.activeDir : ""
    bgModel.folder = ""
    if (target.length) bgModel.folder = target
  }

  onActiveDirChanged: if (active) root.refresh()
  onActiveChanged: {
    if (active) root.refresh()
    else picker.visible = false
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.spacing.md

    RowLayout {
      Layout.fillWidth: true
      Text {
        Layout.fillWidth: true
        text: "Wallpapers"
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.title
        font.bold: true
      }
      Text {
        text: bgModel.count + (bgModel.count === 1 ? " image" : " images")
        color: BarPalette.popupSubtext
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }

    ButtonGroup {
      Layout.fillWidth: true
      foreground: Color.popups.text
      options: [
        { value: "theme", label: "From theme" },
        { value: "folder", label: "From local folder" }
      ]
      value: root.subTab
      onChanged: function(value) { root.subTab = value }
    }

    RowLayout {
      visible: root.subTab === "folder"
      Layout.fillWidth: true
      spacing: Style.spacing.sm

      Text {
        Layout.fillWidth: true
        text: root.localFolder.length ? root.localFolder : "No folder selected"
        color: BarPalette.popupSubtext
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideMiddle
        verticalAlignment: Text.AlignVCenter
      }
      Button {
        text: "Choose folder…"
        bordered: true
        foreground: Color.popups.text
        fontSize: Style.font.bodySmall
        onClicked: picker.visible = true
      }
    }

    Text {
      visible: bgModel.status === FolderListModel.Ready && bgModel.count === 0
      Layout.fillWidth: true
      text: root.subTab === "folder"
            ? (root.localFolder.length ? "No images in " + root.localFolder
                                       : "Choose a folder to show its wallpapers.")
            : "No backgrounds in the current theme."
      color: BarPalette.popupSubtext
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }

    GridView {
      id: grid
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      cellWidth: Style.space(240)
      cellHeight: Style.space(150)
      model: bgModel

      delegate: Item {
        id: cell
        required property int index
        required property string fileName
        required property string filePath
        required property url fileUrl
        width: grid.cellWidth
        height: grid.cellHeight

        ClippingRectangle {
          id: thumb
          anchors.fill: parent
          anchors.margins: Style.spacing.sm
          radius: Style.cornerRadius
          color: BarPalette.popupInputBackground
          border.width: hoverHandler.hovered ? 2 : 0
          border.color: BarPalette.workspace.activeBackground

          Image {
            anchors.fill: parent
            asynchronous: true
            cache: true
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: thumb.width
            sourceSize.height: thumb.height
            source: cell.fileUrl
          }
        }

        HoverHandler { id: hoverHandler }
        TapHandler {
          onTapped: {
            Quickshell.execDetached(["omarchy-theme-bg-set", cell.filePath])
            // Keep Control Panel open so the user can try several wallpapers.
          }
        }
      }
    }
  }

  FolderPicker {
    id: picker
    anchors.fill: parent
    visible: false
    z: 10
    startPath: root.localFolder
    onChosen: function(path) {
      root.localFolder = path
      settingsFile.setText(Model.serializeWallpaperSettings({ localFolder: path }))
      root.subTab = "folder"
      picker.visible = false
      root.refresh()
    }
    onCancelled: picker.visible = false
  }
}

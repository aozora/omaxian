import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.Commons
import qs.Services
import qs.Ui
import "WallpaperModel.js" as WModel

// Wallpaper picker. Ported from the LocalHost `Bar/widgets/WallpaperButton.qml`
// into the visible bar. Two sub-tabs:
//   "From theme"        — a Qt `FolderListModel` over the current Omarchy
//                         theme's `backgrounds/` dir (the original behaviour).
//   "From local folder" — the same grid over a user-picked directory,
//                         chosen via Ui/FolderPicker and persisted to
//                         ~/.config/omarchy/wallpaper-settings.json.
// Picking one runs `omarchy-theme-bg-set` (vendored, X11-adapted:
// `hsetroot -cover` + persist over the i3 theme path) — it accepts an
// arbitrary image path, so folder picks work unchanged.
BarWidget {
  id: root
  moduleName: "omaxian.wallpapers"

  property bool menuOpen: false

  property string subTab: "theme"
  property string localFolder: ""

  readonly property string themeDir:
    Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/backgrounds"
  readonly property string activeDir: subTab === "folder" ? localFolder : themeDir

  IpcHandler {
    target: "wallpapers"
    function toggle(): void { root.menuOpen = !root.menuOpen }
    function hide(): void { root.menuOpen = false }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // watchChanges so a pick made in the Control Panel's Wallpaper tab (which
  // writes the same file) shows up here without a shell restart. Writes are
  // rare and idempotent, so the self-write/watch race dock-pinned.json
  // guards against doesn't matter here.
  FileView {
    id: settingsFile
    path: Quickshell.env("HOME") + "/.config/omarchy/wallpaper-settings.json"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.localFolder = WModel.parseSettings(text()).localFolder
    onFileChanged: root.localFolder = WModel.parseSettings(text()).localFolder
    onLoadFailed: root.localFolder = ""
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    fontSize: Style.font.body + 4
    text: "󰥶"
    foreground: Color.bar.text
    horizontalMargin: 8.5
    verticalPadding: 6
    onPressed: root.menuOpen = !root.menuOpen
  }

  FolderListModel {
    id: bgModel
    showDirs: false
    showHidden: false
    showOnlyReadable: true
    sortField: FolderListModel.Name
    nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.bmp"]
  }

  // Set imperatively rather than bound: `current/theme` is a symlink that
  // follows theme switches, so the folder URL string can stay identical
  // while resolving elsewhere — a plain binding wouldn't re-scan. Clearing
  // to "" first forces the model to drop its cache.
  function rescan() {
    var target = root.activeDir.length ? "file://" + root.activeDir : ""
    bgModel.folder = ""
    if (target.length) bgModel.folder = target
  }

  onActiveDirChanged: rescan()
  Component.onCompleted: rescan()

  PopupCard {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: wallpaperOwner
    open: root.menuOpen
    contentWidth: Style.space(1000)
    contentHeight: Style.space(760)

    onOpenChanged: if (open) {
      root.rescan()
    } else {
      picker.visible = false
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
              root.menuOpen = false
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
        settingsFile.setText(WModel.serializeSettings({ localFolder: path }))
        root.subTab = "folder"
        picker.visible = false
        root.rescan()
      }
      onCancelled: picker.visible = false
    }
  }

  QtObject {
    id: wallpaperOwner
    function close() { root.menuOpen = false }
  }
}

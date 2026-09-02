import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.Commons
import qs.Services
import qs.Ui
import "Model.js" as Model

// Control Panel tab: wallpaper picker. Image list via bash Process (ThemeTab
// pattern). FolderPicker stays inline — a nested URL Loader for the picker
// overlay failed to activate on click (resolvedUrl / async active race).
Item {
  id: root

  property bool active: false
  signal picked()

  property string subTab: "theme"
  property string localFolder: ""
  property var images: []

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

  function refresh() {
    if (!root.activeDir.length) {
      root.images = []
      return
    }
    listProc.command = ["bash", "-c",
      "dir=" + JSON.stringify(root.activeDir) + "; " +
      "[ -d \"$dir\" ] || exit 0; " +
      "find -L \"$dir\" -maxdepth 1 -type f \\( " +
      "-iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o " +
      "-iname '*.webp' -o -iname '*.bmp' \\) -print | sort"]
    listProc.running = false
    listProc.running = true
  }

  onActiveDirChanged: if (active) root.refresh()
  onActiveChanged: {
    if (active) root.refresh()
    else picker.visible = false
  }

  Process {
    id: listProc
    stdout: StdioCollector {
      onStreamFinished: {
        var out = []
        var lines = text.split("\n")
        for (var i = 0; i < lines.length; i++) {
          var p = lines[i].replace(/\r$/, "")
          if (!p.length) continue
          var slash = p.lastIndexOf("/")
          out.push({
            path: p,
            name: slash >= 0 ? p.slice(slash + 1) : p,
            url: "file://" + p
          })
        }
        root.images = out
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
        text: "Wallpapers"
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.title
        font.bold: true
      }
      Text {
        text: root.images.length + (root.images.length === 1 ? " image" : " images")
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
      visible: root.images.length === 0
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
      model: root.images

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
          border.width: hoverHandler.hovered ? 2 : 0
          border.color: BarPalette.workspace.activeBackground

          Image {
            anchors.fill: parent
            asynchronous: true
            cache: true
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: thumb.width
            sourceSize.height: thumb.height
            source: cell.modelData.url
          }
        }

        HoverHandler { id: hoverHandler }
        TapHandler {
          onTapped: {
            Quickshell.execDetached(["omarchy-theme-bg-set", cell.modelData.path])
            root.picked()
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

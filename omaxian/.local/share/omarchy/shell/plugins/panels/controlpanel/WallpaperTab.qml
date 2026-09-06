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
  property string themeName: ""
  property int themeDirAttempt: 0
  property var themeDirCandidates: []
  readonly property bool folderPickerOpen: picker.visible

  readonly property string home: Quickshell.env("HOME")
  readonly property string omarchyPath: Quickshell.env("OMARCHY_PATH") || (home + "/.local/share/omarchy")
  readonly property string activeDir: subTab === "folder" ? localFolder : (
    themeDirCandidates.length > themeDirAttempt ? themeDirCandidates[themeDirAttempt] : ""
  )

  implicitWidth: Style.space(1000)
  implicitHeight: Style.space(720)

  readonly property string themeNamePath: root.home + "/.local/state/omarchy/current/theme.name"
  readonly property string settingsPath: root.home + "/.config/omarchy/wallpaper-settings.json"
  property string themeNameReadBuf: ""
  property string settingsReadBuf: ""

  function applyThemeName(raw) {
    root.themeName = String(raw || "").trim()
    root.themeDirCandidates = Model.themeBackgroundCandidates(root.home, root.omarchyPath, root.themeName)
    if (root.active) root.refresh()
  }

  function reloadThemeNameFile() {
    if (themeNameReadProc.running) {
      themeNameReadProc.signal(15)
      themeNameReadKill.start()
    }
    root.themeNameReadBuf = ""
    themeNameReadProc.command = [
      "/usr/bin/python3", "-I", "-S",
      Quickshell.shellDir + "/scripts/safe-read.py",
      "4096", root.themeNamePath
    ]
    themeNameReadProc.running = true
  }

  function reloadSettingsFile() {
    if (settingsReadProc.running) {
      settingsReadProc.signal(15)
      settingsReadKill.start()
    }
    root.settingsReadBuf = ""
    settingsReadProc.command = [
      "/usr/bin/python3", "-I", "-S",
      Quickshell.shellDir + "/scripts/safe-read.py",
      "65536", root.settingsPath
    ]
    settingsReadProc.running = true
  }

  // Watcher only — bytes come from safe-read.py.
  FileView {
    id: themeNameFile
    path: root.themeNamePath
    preload: false
    blockAllReads: true
    watchChanges: true
    printErrors: false
    onFileChanged: root.reloadThemeNameFile()
  }

  // Write path still uses FileView.setText; read hardening is via safe-read.
  FileView {
    id: settingsFile
    path: root.settingsPath
    preload: false
    blockAllReads: true
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: root.reloadSettingsFile()
  }

  Process {
    id: themeNameReadProc
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        root.themeNameReadBuf += String(chunk || "")
        if (root.themeNameReadBuf.length > 4096) {
          themeNameReadProc.signal(15)
          themeNameReadKill.start()
          root.themeNameReadBuf = ""
        }
      }
    }
    onExited: function(exitCode) {
      var raw = root.themeNameReadBuf
      root.themeNameReadBuf = ""
      if (exitCode === 0)
        root.applyThemeName(raw)
    }
  }

  Timer {
    id: themeNameReadKill
    interval: 2000
    repeat: false
    onTriggered: themeNameReadProc.signal(9)
  }

  Process {
    id: settingsReadProc
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        root.settingsReadBuf += String(chunk || "")
        if (root.settingsReadBuf.length > 65536) {
          settingsReadProc.signal(15)
          settingsReadKill.start()
          root.settingsReadBuf = ""
        }
      }
    }
    onExited: function(exitCode) {
      var raw = root.settingsReadBuf
      root.settingsReadBuf = ""
      if (exitCode === 0)
        root.localFolder = Model.parseWallpaperSettings(raw).localFolder
    }
  }

  Timer {
    id: settingsReadKill
    interval: 2000
    repeat: false
    onTriggered: settingsReadProc.signal(9)
  }

  Component.onCompleted: {
    root.reloadThemeNameFile()
    root.reloadSettingsFile()
  }

  FolderListModel {
    id: bgModel
    showDirs: false
    showHidden: false
    showOnlyReadable: true
    sortField: FolderListModel.Name
    nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.bmp"]
    onStatusChanged: {
      if (root.subTab !== "theme") return
      if (status !== FolderListModel.Ready) return
      if (count > 0) return
      if (root.themeDirAttempt + 1 >= root.themeDirCandidates.length) return
      root.themeDirAttempt++
      root.applyThemeFolder()
    }
  }

  // Prefer live theme package paths; fall through candidates if a dir is
  // missing/empty. Clearing folder first forces FolderListModel to rescan.
  function applyThemeFolder() {
    var dir = root.themeDirCandidates.length > root.themeDirAttempt
      ? root.themeDirCandidates[root.themeDirAttempt] : ""
    var target = dir.length ? "file://" + dir : ""
    bgModel.folder = ""
    if (target.length) bgModel.folder = target
  }

  function refresh() {
    if (root.subTab === "folder") {
      var target = root.localFolder.length ? "file://" + root.localFolder : ""
      bgModel.folder = ""
      if (target.length) bgModel.folder = target
      return
    }
    root.themeDirCandidates = Model.themeBackgroundCandidates(root.home, root.omarchyPath, root.themeName)
    root.themeDirAttempt = 0
    root.applyThemeFolder()
  }

  onActiveDirChanged: if (active && subTab === "folder") root.refresh()
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
        textFormat: Text.PlainText
        Layout.fillWidth: true
        text: "Wallpapers"
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.title
        font.bold: true
      }
      Text {
        textFormat: Text.PlainText
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
      onChanged: function(value) {
        root.subTab = value
        if (root.active) root.refresh()
      }
    }

    RowLayout {
      visible: root.subTab === "folder"
      Layout.fillWidth: true
      spacing: Style.spacing.sm

      Text {
        textFormat: Text.PlainText
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
      textFormat: Text.PlainText
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

          // Resolution from the filename (e.g. …-2560x1440.png) — helps tell
          // apart the same art shipped at 16:9 / ultrawide / 4K sizes.
          Rectangle {
            id: sizeBadge
            visible: sizeLabel.text.length > 0
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Style.space(4)
            radius: Style.cornerRadius
            color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.78)
            width: sizeLabel.implicitWidth + Style.space(8)
            height: sizeLabel.implicitHeight + Style.space(4)

            Text {
              textFormat: Text.PlainText
              id: sizeLabel
              anchors.centerIn: parent
              text: Model.wallpaperSizeLabel(cell.fileName)
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
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

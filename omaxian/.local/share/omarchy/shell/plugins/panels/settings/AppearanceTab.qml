import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var pluginRegistry: null
  property var barWidgetRegistry: null
  property color foreground: Color.popups.text

  readonly property string fontFamily: Style.font.family

  property var toml: ({})
  property string localFolder: ""
  property bool pickingFolder: false

  readonly property int fontSize: {
    var n = Model.tomlNumber(toml, "font.base-size", Style.font.baseSize)
    return isFinite(n) ? Math.round(n) : Style.font.baseSize
  }
  readonly property string spacingScale: {
    var n = Model.tomlNumber(toml, "spacing.scale", Style.spacingScale)
    if (!isFinite(n)) n = Style.spacingScale
    return String(n)
  }
  readonly property int barHorizontal: {
    var n = Model.tomlNumber(toml, "bar.size-horizontal", Style.bar.sizeHorizontal)
    return isFinite(n) ? Math.round(n) : Style.bar.sizeHorizontal
  }
  readonly property int barVertical: {
    var n = Model.tomlNumber(toml, "bar.size-vertical", Style.bar.sizeVertical)
    return isFinite(n) ? Math.round(n) : Style.bar.sizeVertical
  }

  FileView {
    id: tomlFile
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.toml"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.toml = Model.parseShell(text())
    onFileChanged: reload()
    onLoadFailed: root.toml = ({})
  }

  FileView {
    id: wallpaperFile
    path: Quickshell.env("HOME") + "/.config/omarchy/wallpaper-settings.json"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.localFolder = Model.parseWallpaperSettings(text()).localFolder
    onFileChanged: reload()
    onLoadFailed: root.localFolder = ""
  }

  function persistToml(updates) {
    var next = Model.upsertToml(tomlFile.text() || "", updates)
    tomlFile.setText(next)
    root.toml = Model.parseShell(next)
  }

  function persistFolder(path) {
    root.localFolder = String(path || "")
    wallpaperFile.setText(Model.serializeWallpaperSettings({ localFolder: root.localFolder }))
  }

  function openControlPanelTab(name) {
    Quickshell.execDetached(["omarchy-shell", "-q", "omaxian.controlpanel", "showTab", String(name || "")])
    if (shell && typeof shell.hide === "function")
      shell.hide("omaxian.settings")
  }

  FolderPicker {
    anchors.fill: parent
    visible: root.pickingFolder
    z: 10
    startPath: root.localFolder
    heading: "Wallpaper folder"
    foreground: root.foreground
    onChosen: function(path) {
      root.pickingFolder = false
      root.persistFolder(path)
    }
    onCancelled: root.pickingFolder = false
  }

  Flickable {
    id: flick
    anchors.fill: parent
    visible: !root.pickingFolder
    clip: true
    contentWidth: width
    contentHeight: col.implicitHeight
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: col
      width: flick.width
      spacing: Style.space(12)

      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: "These values write ~/.config/omarchy/shell.toml and survive theme switches."
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      NumberField {
        width: parent.width
        label: "UI font size"
        value: root.fontSize
        from: 8
        to: 32
        foreground: root.foreground
        fontFamily: root.fontFamily
        onModified: function(v) { root.persistToml({ "font.base-size": v }) }
      }

      Dropdown {
        width: parent.width
        label: "UI density"
        value: root.spacingScale
        options: [
          { value: "0.8", label: "0.8 — compact" },
          { value: "0.9", label: "0.9" },
          { value: "1", label: "1.0 — default" },
          { value: "1.1", label: "1.1" },
          { value: "1.2", label: "1.2" },
          { value: "1.25", label: "1.25" },
          { value: "1.5", label: "1.5 — roomy" }
        ]
        foreground: root.foreground
        fontFamily: root.fontFamily
        onChanged: function(v) { root.persistToml({ "spacing.scale": v }) }
      }

      NumberField {
        width: parent.width
        label: "Bar height (top / bottom)"
        value: root.barHorizontal
        from: 16
        to: 64
        foreground: root.foreground
        fontFamily: root.fontFamily
        onModified: function(v) { root.persistToml({ "bar.size-horizontal": v }) }
      }

      NumberField {
        width: parent.width
        label: "Bar width (left / right)"
        value: root.barVertical
        from: 16
        to: 64
        foreground: root.foreground
        fontFamily: root.fontFamily
        onModified: function(v) { root.persistToml({ "bar.size-vertical": v }) }
      }

      PanelSectionHeader {
        text: "Wallpaper"
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: root.localFolder.length ? root.localFolder : "No extra folder selected"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideMiddle
      }

      Row {
        spacing: Style.space(8)

        Button {
          text: "Choose folder"
          bordered: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.pickingFolder = true
        }

        Button {
          text: "Clear"
          bordered: true
          enabled: root.localFolder.length > 0
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.persistFolder("")
        }

        Button {
          text: "Open wallpaper picker"
          bordered: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.openControlPanelTab("wallpaper")
        }
      }

      Button {
        text: "Open theme picker"
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.openControlPanelTab("theme")
      }
    }
  }
}

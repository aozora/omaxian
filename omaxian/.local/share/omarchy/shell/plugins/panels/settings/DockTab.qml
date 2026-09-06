import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../dock/Model.js" as DockModel

Item {
  id: root

  property var shell: null
  property var pluginRegistry: null
  property var barWidgetRegistry: null
  property color foreground: Color.popups.text

  readonly property string fontFamily: Style.font.family
  readonly property string home: Quickshell.env("HOME")
  readonly property int revision: pluginRegistry ? pluginRegistry.registryRevision : 0
  readonly property bool dockEnabled: {
    var _ = root.revision
    return pluginRegistry ? pluginRegistry.isEnabled("omaxian.dock") : false
  }

  property var themeSparse: ({})
  property var userSparse: ({})
  property var legacySparse: ({})
  property string userDockRaw: ""
  property string themeDockReadBuf: ""
  property string userDockReadBuf: ""
  property string legacyJsonReadBuf: ""

  readonly property string themeDockPath: root.home + "/.local/state/omarchy/current/theme/dock.toml"
  readonly property string userDockPath: root.home + "/.config/omarchy/dock.toml"
  readonly property string legacyJsonPath: root.home + "/.config/omarchy/dock-settings.json"

  readonly property var settings: DockModel.mergeSettings(
    root.themeSparse,
    Object.keys(root.userSparse).length ? root.userSparse : root.legacySparse
  )

  readonly property color previewFill: {
    var hex = root.settings.background || ""
    return hex ? Style.colorFromHex(hex, Color.bar.background) : Color.bar.background
  }

  function applyUserDockRaw(raw) {
    root.userDockRaw = String(raw || "")
    root.userSparse = DockModel.parseSettingsSparse(root.userDockRaw)
    if (!bgField.activeFocus)
      bgField.text = root.settings.background || ""
  }

  function reloadThemeDockFile() {
    if (themeDockReadProc.running) {
      themeDockReadProc.signal(15)
      themeDockReadKill.start()
    }
    root.themeDockReadBuf = ""
    themeDockReadProc.command = [
      "/usr/bin/python3", "-I", "-S",
      Quickshell.shellDir + "/scripts/safe-read.py",
      "65536", root.themeDockPath
    ]
    themeDockReadProc.running = true
  }

  function reloadUserDockFile() {
    if (userDockReadProc.running) {
      userDockReadProc.signal(15)
      userDockReadKill.start()
    }
    root.userDockReadBuf = ""
    userDockReadProc.command = [
      "/usr/bin/python3", "-I", "-S",
      Quickshell.shellDir + "/scripts/safe-read.py",
      "65536", root.userDockPath
    ]
    userDockReadProc.running = true
  }

  function reloadLegacyJsonFile() {
    if (legacyJsonReadProc.running) {
      legacyJsonReadProc.signal(15)
      legacyJsonReadKill.start()
    }
    root.legacyJsonReadBuf = ""
    legacyJsonReadProc.command = [
      "/usr/bin/python3", "-I", "-S",
      Quickshell.shellDir + "/scripts/safe-read.py",
      "65536", root.legacyJsonPath
    ]
    legacyJsonReadProc.running = true
  }

  // Watcher only — bytes come from safe-read.py.
  FileView {
    id: themeDockFile
    path: root.themeDockPath
    preload: false
    blockAllReads: true
    watchChanges: true
    printErrors: false
    onFileChanged: root.reloadThemeDockFile()
  }

  // Write path still uses FileView.setText; read hardening is via safe-read.
  FileView {
    id: userDockFile
    path: root.userDockPath
    preload: false
    blockAllReads: true
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: root.reloadUserDockFile()
  }

  FileView {
    id: legacyJsonFile
    path: root.legacyJsonPath
    preload: false
    blockAllReads: true
    watchChanges: true
    printErrors: false
    onFileChanged: root.reloadLegacyJsonFile()
  }

  Process {
    id: themeDockReadProc
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        root.themeDockReadBuf += String(chunk || "")
        if (root.themeDockReadBuf.length > 65536) {
          themeDockReadProc.signal(15)
          themeDockReadKill.start()
          root.themeDockReadBuf = ""
        }
      }
    }
    onExited: function(exitCode) {
      var raw = root.themeDockReadBuf
      root.themeDockReadBuf = ""
      if (exitCode === 0)
        root.themeSparse = DockModel.parseSettingsSparse(raw)
    }
  }

  Timer {
    id: themeDockReadKill
    interval: 2000
    repeat: false
    onTriggered: themeDockReadProc.signal(9)
  }

  Process {
    id: userDockReadProc
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        root.userDockReadBuf += String(chunk || "")
        if (root.userDockReadBuf.length > 65536) {
          userDockReadProc.signal(15)
          userDockReadKill.start()
          root.userDockReadBuf = ""
        }
      }
    }
    onExited: function(exitCode) {
      var raw = root.userDockReadBuf
      root.userDockReadBuf = ""
      if (exitCode === 0)
        root.applyUserDockRaw(raw)
    }
  }

  Timer {
    id: userDockReadKill
    interval: 2000
    repeat: false
    onTriggered: userDockReadProc.signal(9)
  }

  Process {
    id: legacyJsonReadProc
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        root.legacyJsonReadBuf += String(chunk || "")
        if (root.legacyJsonReadBuf.length > 65536) {
          legacyJsonReadProc.signal(15)
          legacyJsonReadKill.start()
          root.legacyJsonReadBuf = ""
        }
      }
    }
    onExited: function(exitCode) {
      var raw = root.legacyJsonReadBuf
      root.legacyJsonReadBuf = ""
      if (exitCode === 0)
        root.legacySparse = DockModel.parseSettingsSparse(raw)
    }
  }

  Timer {
    id: legacyJsonReadKill
    interval: 2000
    repeat: false
    onTriggered: legacyJsonReadProc.signal(9)
  }

  Component.onCompleted: {
    root.reloadThemeDockFile()
    root.reloadUserDockFile()
    root.reloadLegacyJsonFile()
  }

  function persist(next) {
    var body = DockModel.upsertToml(root.userDockRaw || "", next)
    // Write hardening is separate — keep FileView.setText for saves.
    userDockFile.setText(body)
    root.applyUserDockRaw(body)
  }

  function setDockEnabled(value) {
    if (!pluginRegistry) return
    pluginRegistry.setEnabled("omaxian.dock", value)
  }

  function commitBackground() {
    root.persist({ background: bgField.text.trim() })
  }

  Process {
    id: colorPick
    property string stdoutBuf: ""
    property int maxStdout: 256
    property bool overflowed: false
    command: ["gpick", "-p", "-s", "-o", "--no-newline", "-c", "color_web_hex"]
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        if (colorPick.overflowed) return
        colorPick.stdoutBuf += chunk
        if (colorPick.stdoutBuf.length > colorPick.maxStdout) {
          colorPick.overflowed = true
          colorPick.stdoutBuf = ""
          colorPick.signal(15)
          colorPickKillTimer.start()
        }
      }
    }
    onStarted: {
      colorPickKillTimer.stop()
      stdoutBuf = ""
      overflowed = false
    }
    onExited: function() {
      colorPickKillTimer.stop()
      var hex = overflowed ? "" : String(stdoutBuf || "").trim()
      stdoutBuf = ""
      overflowed = false
      if (hex)
        root.persist({ background: hex })
    }
  }

  Timer {
    id: colorPickKillTimer
    interval: 2000
    onTriggered: colorPick.signal(9)
  }

  Flickable {
    id: flick
    anchors.fill: parent
    clip: true
    contentWidth: width
    contentHeight: col.implicitHeight
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: col
      width: flick.width
      spacing: Style.space(12)

      Text {
        textFormat: Text.PlainText
        width: parent.width
        wrapMode: Text.Wrap
        text: "Theme dock.toml sets defaults. Settings write ~/.config/omarchy/dock.toml (survives theme switches)."
        color: Qt.darker(root.foreground, 1.5)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Toggle {
        width: parent.width
        label: "Show dock"
        description: "Persistent bottom dock. Pinned apps are managed on the dock itself (right-click / drag)."
        checked: root.dockEnabled
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.setDockEnabled(!root.dockEnabled)
      }

      Toggle {
        width: parent.width
        label: "Full width"
        description: "Span the whole screen edge. Off: a centered pill. Changing this may need a shell restart."
        checked: root.settings.fullWidth === true
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.persist({ fullWidth: !root.settings.fullWidth })
      }

      Toggle {
        width: parent.width
        label: "Hover magnification"
        description: "Scale up the hovered icon."
        checked: root.settings.hoverAnimation !== false
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.persist({ hoverAnimation: !root.settings.hoverAnimation })
      }

      Toggle {
        width: parent.width
        label: "Autohide"
        description: "Hide the dock off the bottom edge; peek on hover. Default off."
        checked: root.settings.autoHide === true
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.persist({ autoHide: !root.settings.autoHide })
      }

      PanelSectionHeader {
        text: "Appearance"
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Column {
        width: parent.width
        spacing: Style.space(6)

        Text {
          textFormat: Text.PlainText
          text: "Background color"
          color: Qt.darker(root.foreground, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          wrapMode: Text.Wrap
          text: "Empty matches the bar background. Enter #rgb / #rrggbb, or pick a color."
          color: Qt.darker(root.foreground, 1.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Row {
          width: parent.width
          spacing: Style.space(8)

          Rectangle {
            width: Style.space(28)
            height: Style.space(28)
            radius: Style.cornerRadius
            anchors.verticalCenter: parent.verticalCenter
            color: root.previewFill
            opacity: root.settings.opacity
            border.width: Math.max(1, Style.normalBorderWidth)
            border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.35)
          }

          TextField {
            id: bgField
            width: parent.width - Style.space(28) - pickBtn.width - resetBtn.width - parent.spacing * 3
            anchors.verticalCenter: parent.verticalCenter
            foreground: root.foreground
            placeholderText: "Match bar"
            onEditingFinished: root.commitBackground()
            Keys.onReturnPressed: root.commitBackground()
            Keys.onEnterPressed: root.commitBackground()
          }

          Button {
            id: pickBtn
            text: "Pick"
            tooltipText: "Pick a color with gpick"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.space(10)
            verticalPadding: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
            onClicked: {
              if (!colorPick.running)
                colorPick.running = true
            }
          }

          Button {
            id: resetBtn
            text: "Reset"
            tooltipText: "Match bar background"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.space(10)
            verticalPadding: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
            enabled: !!(root.settings.background && root.settings.background.length)
            onClicked: root.persist({ background: "" })
          }
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(6)

        Text {
          textFormat: Text.PlainText
          text: "Background opacity"
          color: Qt.darker(root.foreground, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Row {
          width: parent.width
          spacing: Style.space(10)

          PanelSlider {
            width: parent.width - opacityValue.width - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            value: root.settings.opacity
            minimum: 0
            maximum: 1
            step: 0.05
            trackColor: Style.selectedFillFor(root.foreground, Color.accent)
            fillColor: root.foreground
            knobColor: root.foreground
            tickColor: Color.popups.background
            onMoved: function(v) {
              opacityValue.text = (Math.round(v * 100) / 100).toFixed(2)
            }
            onReleased: function(v) {
              root.persist({ opacity: Math.round(v * 100) / 100 })
            }
          }

          Text {
            textFormat: Text.PlainText
            id: opacityValue
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(36)
            horizontalAlignment: Text.AlignRight
            text: root.settings.opacity.toFixed(2)
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
        }
      }

      NumberField {
        width: parent.width
        label: "Icon size"
        value: root.settings.iconSize
        from: 16
        to: 96
        foreground: root.foreground
        fontFamily: root.fontFamily
        onModified: function(v) { root.persist({ iconSize: v }) }
      }

      Column {
        width: parent.width
        spacing: Style.space(6)
        enabled: root.settings.hoverAnimation
        opacity: root.settings.hoverAnimation ? 1 : 0.45

        Text {
          textFormat: Text.PlainText
          text: "Hover scale"
          color: Qt.darker(root.foreground, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Row {
          width: parent.width
          spacing: Style.space(10)

          PanelSlider {
            width: parent.width - scaleValue.width - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            value: root.settings.hoverScale
            minimum: 1
            maximum: 2
            step: 0.05
            trackColor: Style.selectedFillFor(root.foreground, Color.accent)
            fillColor: root.foreground
            knobColor: root.foreground
            tickColor: Color.popups.background
            onMoved: function(v) {
              scaleValue.text = (Math.round(v * 100) / 100).toFixed(2)
            }
            onReleased: function(v) {
              root.persist({ hoverScale: Math.round(v * 100) / 100 })
            }
          }

          Text {
            textFormat: Text.PlainText
            id: scaleValue
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(36)
            horizontalAlignment: Text.AlignRight
            text: root.settings.hoverScale.toFixed(2)
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
        }
      }

      NumberField {
        width: parent.width
        enabled: !root.settings.fullWidth
        opacity: root.settings.fullWidth ? 0.45 : 1
        label: "Corner radius"
        value: root.settings.cornerRadius
        from: 0
        to: 48
        foreground: root.foreground
        fontFamily: root.fontFamily
        onModified: function(v) { root.persist({ cornerRadius: v }) }
      }

      NumberField {
        width: parent.width
        label: "Island gap"
        value: root.settings.islandGap
        from: 0
        to: 48
        foreground: root.foreground
        fontFamily: root.fontFamily
        onModified: function(v) { root.persist({ islandGap: v }) }
      }

      Dropdown {
        width: parent.width
        label: "Running indicator"
        value: root.settings.runningIndicator
        options: [
          { value: "dot", label: "Dot" },
          { value: "bar", label: "Bar" },
          { value: "none", label: "None" }
        ]
        foreground: root.foreground
        fontFamily: root.fontFamily
        onChanged: function(v) { root.persist({ runningIndicator: v }) }
      }
    }
  }
}

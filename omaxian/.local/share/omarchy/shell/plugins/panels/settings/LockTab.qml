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
  readonly property string lockPath: Quickshell.env("HOME") + "/.config/omarchy/lock-settings.json"
  readonly property string runtimeDir: {
    var r = Quickshell.env("XDG_RUNTIME_DIR")
    return r && r.length ? r : "/tmp"
  }
  readonly property string previewPath: root.runtimeDir + "/omaxian-lock-preview.png"
  readonly property string currentBgLink: Quickshell.env("HOME") + "/.local/state/omarchy/current/background"

  property string mode: "blur"
  property string image: ""
  property string folder: ""
  property string effect: "blur"
  property bool greyscale: false
  property bool pickingFolder: false
  property bool pickingFile: false
  property bool previewVisible: false
  property int previewVersion: 0
  property string statusMessage: ""
  property string lockReadBuf: ""

  readonly property bool pickingPath: root.pickingFolder || root.pickingFile

  function imagePickerStartPath() {
    if (root.image && root.image.length) return root.image
    if (root.folder && root.folder.length) return root.folder
    return Quickshell.env("HOME")
  }

  readonly property bool idleEnabled: {
    var idle = shell && shell.shellConfig && shell.shellConfig.idle ? shell.shellConfig.idle : ({})
    return idle.enabled === true
  }
  readonly property int idleLockSeconds: {
    var idle = shell && shell.shellConfig && shell.shellConfig.idle ? shell.shellConfig.idle : ({})
    var n = Number(idle.lock)
    if (!isFinite(n)) n = 300
    return Math.max(30, Math.min(86400, Math.round(n)))
  }

  function reloadLockFile() {
    if (lockReadProc.running) {
      lockReadProc.signal(15)
      lockReadKill.start()
    }
    root.lockReadBuf = ""
    lockReadProc.command = [
      "/usr/bin/python3", "-I", "-S",
      Quickshell.shellDir + "/scripts/safe-read.py",
      "65536", root.lockPath
    ]
    lockReadProc.running = true
  }

  function applyLockState(parsed) {
    root.mode = parsed.mode
    root.image = parsed.image
    root.folder = parsed.folder
    root.effect = parsed.effect
    root.greyscale = parsed.greyscale
  }

  function persistAppearance(next) {
    var payload = Model.serializeLockSettings({
      mode: next && next.mode !== undefined ? next.mode : root.mode,
      image: next && next.image !== undefined ? next.image : root.image,
      folder: next && next.folder !== undefined ? next.folder : root.folder,
      effect: next && next.effect !== undefined ? next.effect : root.effect,
      greyscale: next && next.greyscale !== undefined ? next.greyscale : root.greyscale
    })
    var parsed = Model.parseLockSettings(payload)
    root.applyLockState(parsed)
    lockFile.setText(payload)
    root.statusMessage = "Saved lock appearance"
  }

  function persistIdle(enabled, lockSeconds) {
    if (!shell || typeof shell.mutateShellConfig !== "function") {
      root.statusMessage = "Shell config unavailable"
      return
    }
    var on = enabled === true
    var secs = Number(lockSeconds)
    if (!isFinite(secs)) secs = root.idleLockSeconds
    secs = Math.max(30, Math.min(86400, Math.round(secs)))
    shell.mutateShellConfig(function(cfg) {
      var idle = (cfg.idle && typeof cfg.idle === "object") ? cfg.idle : ({})
      idle.enabled = on
      idle.lock = secs
      idle.screensaver = secs
      cfg.idle = idle
    })
    root.statusMessage = "Saved idle auto-lock"
    if (!idleApplyProc.running)
      idleApplyProc.running = true
  }

  function useCurrentWallpaper() {
    if (bgResolveProc.running) return
    root.statusMessage = "Resolving current wallpaper…"
    bgResolveProc.running = true
  }

  function runPreview() {
    if (previewProc.running) return
    root.statusMessage = "Composing preview…"
    previewProc.running = true
  }

  function runTestLock() {
    Quickshell.execDetached(["omarchy-system-lock"])
    root.statusMessage = "Locking…"
  }

  FileView {
    id: lockFile
    path: root.lockPath
    preload: false
    blockAllReads: true
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: root.reloadLockFile()
  }

  Process {
    id: lockReadProc
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        root.lockReadBuf += String(chunk || "")
        if (root.lockReadBuf.length > 65536) {
          lockReadProc.signal(15)
          lockReadKill.start()
          root.lockReadBuf = ""
        }
      }
    }
    onExited: function(exitCode) {
      var raw = root.lockReadBuf
      root.lockReadBuf = ""
      root.applyLockState(Model.parseLockSettings(exitCode === 0 ? raw : ""))
    }
  }

  Timer {
    id: lockReadKill
    interval: 2000
    repeat: false
    onTriggered: lockReadProc.signal(9)
  }

  Process {
    id: idleApplyProc
    command: ["omarchy-idle-lock-apply"]
    onExited: function(exitCode) {
      if (exitCode !== 0)
        root.statusMessage = "Idle apply failed (is xss-lock / xset installed?)"
    }
  }

  Process {
    id: previewProc
    command: ["i3lock-omaxian", "--preview", root.previewPath]
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.statusMessage = "Preview failed (need convert + i3lock-omaxian)"
        return
      }
      root.previewVersion += 1
      root.previewVisible = true
      root.statusMessage = "Preview ready"
    }
  }

  Process {
    id: bgResolveProc
    property string stdoutBuf: ""
    command: [
      "bash", "-c",
      'readlink -f -- "$1" 2>/dev/null || true',
      "lock-bg", root.currentBgLink
    ]
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) { bgResolveProc.stdoutBuf += String(chunk || "") }
    }
    onStarted: bgResolveProc.stdoutBuf = ""
    onExited: function(exitCode) {
      var path = String(bgResolveProc.stdoutBuf || "").trim()
      bgResolveProc.stdoutBuf = ""
      if (!path.length) {
        root.statusMessage = "No current wallpaper symlink"
        return
      }
      root.persistAppearance({ mode: "image", image: path })
      root.statusMessage = "Using current wallpaper"
    }
  }

  Component.onCompleted: root.reloadLockFile()

  FolderPicker {
    anchors.fill: parent
    visible: root.pickingFolder
    z: 20
    pickFiles: false
    startPath: root.folder.length ? root.folder : Quickshell.env("HOME")
    heading: "Lock wallpaper folder"
    foreground: root.foreground
    onChosen: function(path) {
      root.pickingFolder = false
      root.persistAppearance({ mode: "random", folder: path })
    }
    onCancelled: root.pickingFolder = false
  }

  FolderPicker {
    anchors.fill: parent
    visible: root.pickingFile
    z: 20
    pickFiles: true
    startPath: root.imagePickerStartPath()
    heading: "Lock wallpaper image"
    foreground: root.foreground
    onChosen: function(path) {
      root.pickingFile = false
      root.persistAppearance({ mode: "image", image: path })
    }
    onCancelled: root.pickingFile = false
  }

  Rectangle {
    anchors.fill: parent
    visible: root.previewVisible
    z: 30
    color: Qt.rgba(0, 0, 0, 0.72)

    Keys.onEscapePressed: root.previewVisible = false
    focus: root.previewVisible

    MouseArea {
      anchors.fill: parent
      onClicked: root.previewVisible = false
    }

    Image {
      anchors.centerIn: parent
      width: Math.min(parent.width - Style.space(24), Style.space(640))
      height: Math.min(parent.height - Style.space(24), Style.space(400))
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      cache: false
      source: root.previewVisible
        ? ("file://" + root.previewPath + "?v=" + root.previewVersion)
        : ""
    }

    Text {
      anchors.bottom: parent.bottom
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottomMargin: Style.space(12)
      textFormat: Text.PlainText
      text: "Click or Esc to close"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  Flickable {
    id: flick
    anchors.fill: parent
    visible: !root.pickingPath && !root.previewVisible
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
        text: "Lock appearance writes ~/.config/omarchy/lock-settings.json. Idle auto-lock uses shell.json and xss-lock."
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      PanelSectionHeader {
        text: "Appearance"
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Dropdown {
        width: parent.width
        label: "Background"
        value: root.mode
        options: Model.lockModeOptions()
        foreground: root.foreground
        fontFamily: root.fontFamily
        onChanged: function(v) {
          var nextEffect = root.effect
          if (v === "blur" && root.effect === "none") nextEffect = "blur"
          if (v !== "blur" && root.mode === "blur" && root.effect === "blur") nextEffect = "none"
          root.persistAppearance({ mode: v, effect: nextEffect })
        }
      }

      Dropdown {
        width: parent.width
        label: "Effect"
        value: root.effect
        options: Model.lockEffectOptions()
        foreground: root.foreground
        fontFamily: root.fontFamily
        onChanged: function(v) { root.persistAppearance({ effect: v }) }
      }

      Toggle {
        width: parent.width
        label: "Greyscale"
        description: "Desaturate the lock background"
        checked: root.greyscale
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.persistAppearance({ greyscale: !root.greyscale })
      }

      Text {
        textFormat: Text.PlainText
        visible: root.mode === "image"
        width: parent.width
        wrapMode: Text.Wrap
        elide: Text.ElideMiddle
        text: root.image.length ? root.image : "No image selected"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Row {
        spacing: Style.space(8)
        visible: root.mode === "image"

        Button {
          text: "Choose file"
          bordered: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.pickingFile = true
        }

        Button {
          text: "Use current wallpaper"
          bordered: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.useCurrentWallpaper()
        }

        Button {
          text: "Clear"
          bordered: true
          enabled: root.image.length > 0
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.persistAppearance({ image: "" })
        }
      }

      Text {
        textFormat: Text.PlainText
        visible: root.mode === "random"
        width: parent.width
        wrapMode: Text.Wrap
        elide: Text.ElideMiddle
        text: root.folder.length ? root.folder : "No folder selected"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Row {
        spacing: Style.space(8)
        visible: root.mode === "random"

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
          enabled: root.folder.length > 0
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.persistAppearance({ folder: "" })
        }
      }

      Text {
        textFormat: Text.PlainText
        visible: root.mode === "random"
        width: parent.width
        wrapMode: Text.Wrap
        text: "Random preview picks one image; the next real lock may differ."
        color: Qt.darker(root.foreground, 1.5)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Row {
        spacing: Style.space(8)

        Button {
          text: "Preview"
          bordered: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.runPreview()
        }

        Button {
          text: "Test lock"
          bordered: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.runTestLock()
        }
      }

      PanelSectionHeader {
        text: "Auto-lock"
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Toggle {
        width: parent.width
        label: "Enable idle auto-lock"
        description: "Arm X screensaver timeout; xss-lock runs the locker"
        checked: root.idleEnabled
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.persistIdle(!root.idleEnabled, root.idleLockSeconds)
      }

      NumberField {
        width: parent.width
        label: "Lock after (seconds)"
        value: root.idleLockSeconds
        from: 30
        to: 86400
        stepSize: 30
        foreground: root.foreground
        fontFamily: root.fontFamily
        onModified: function(v) { root.persistIdle(root.idleEnabled, v) }
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        wrapMode: Text.Wrap
        text: "Stay Awake on the bar suspends idle lock. xss-lock still handles session lock (lid / loginctl) when installed."
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Button {
        text: "Apply idle now"
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: {
          root.persistIdle(root.idleEnabled, root.idleLockSeconds)
        }
      }

      Text {
        textFormat: Text.PlainText
        visible: root.statusMessage !== ""
        width: parent.width
        wrapMode: Text.Wrap
        text: Util.plain(root.statusMessage)
        color: Qt.darker(root.foreground, 1.3)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Running Cat — a cat that runs along the bar at a speed set by CPU load.
//
// The sprite frames are monochrome SVGs. A MultiEffect colorizes them with the
// bar's foreground color (the same trick the tray uses for symbolic icons), so
// the cat follows the active theme instead of shipping one raster per theme.
//
// The animation ports RunCat's curve: a full cycle takes busyCycleMs at 100%
// CPU and idleCycleMs at 0%, easing as f(x) = busy + (idle - busy) * (1 - x)^k,
// with an exponential moving average between readings so the cat accelerates
// and settles instead of snapping. Below idleThreshold it sleeps.
//
// Left click runs clickCommand, right click cycles cat / cat+% / %, the wheel
// nudges the sprite size, middle click resamples now. Everything is settable
// from shell.json (scroll / right-click, or `omarchy-shell shell setBarWidget`).
//
// The sprite artwork comes from win0err/gnome-runcat (GPL-3.0), which traces
// back to Kyome22's RunCat for macOS. See README.md and LICENSE.
BarWidget {
  id: root
  moduleName: "io.github.kaiizu.runcat"

  // shell.json settings arrive as untyped JSON: coerce and clamp anything
  // numeric before it drives geometry or timers.
  function boolSetting(name, fallback) {
    var value = setting(name, fallback)
    if (typeof value === "boolean") return value
    var text = String(value).trim().toLowerCase()
    if (["true", "1", "yes", "on"].indexOf(text) !== -1) return true
    if (["false", "0", "no", "off"].indexOf(text) !== -1) return false
    return fallback
  }

  function enumSetting(name, fallback, options) {
    var want = String(setting(name, fallback)).trim().toLowerCase()
    return options.indexOf(want) === -1 ? fallback : want
  }

  function stringSetting(name, fallback) {
    var value = setting(name, fallback)
    return value === undefined || value === null ? fallback : String(value).trim()
  }

  // ------------------------------------------------------------------ knobs

  // Seconds between CPU samples; floored at 1s so a zero entry cannot
  // spawn a sample per frame.
  readonly property int sampleInterval: Math.max(1, Model.clampInt(setting("interval", 2), 2, 1, 60)) * 1000
  // Duration of one full animation cycle, in ms, at each end of the load range.
  readonly property int busyCycleMs: Model.clampInt(setting("busyCycleMs", 250), 250, 16, 5000)
  readonly property int idleCycleMs: Math.max(busyCycleMs, Model.clampInt(setting("idleCycleMs", 1100), 1100, 16, 20000))
  // Exponent of the easing curve. 2 matches RunCat; higher keeps the cat slow
  // until load really climbs.
  readonly property real curve: Model.clamp(Model.toNumber(setting("curve", 2), 2), 0.1, 8)
  readonly property bool smooth: boolSetting("smooth", true)
  readonly property int smoothMs: Model.clampInt(setting("smoothMs", 500), 500, 0, 5000)
  // CPU percentage at or below which the sleeping cat appears (0 disables it,
  // apart from a truly idle machine landing on a full zero).
  readonly property int idleThreshold: Model.clampInt(setting("idleThreshold", 0), 0, 0, 100)
  readonly property bool invertSpeed: boolSetting("invertSpeed", false)

  // cat — the sprite alone; percent — the figure alone; both — sprite + figure.
  // A vertical bar has no room beside the sprite, so it always keeps the cat.
  readonly property string display: enumSetting("display", "cat", ["cat", "percent", "both"])
  readonly property bool showCat: display !== "percent" || vertical
  readonly property bool showPercent: display !== "cat" && !vertical

  // Sprite size in px, and the percentage size. The bundled cat art fills
  // roughly 60% of its square canvas, so the default sits above the theme's
  // 16px icon canvas to read at the same weight as its neighbours.
  readonly property int spriteSize: Model.clampInt(setting("size", 22), 22, 8, 32)
  // The percentage follows the sprite through this fraction of its box, so the
  // two keep the same proportion at every size. 0.45 draws a 10px number on a
  // 22px cat box — about half the cat's painted height.
  readonly property real fontRatio: Model.clamp(Model.toNumber(setting("fontRatio", 0.45), 0.45), 0.15, 1.2)
  readonly property int proportionalTextSize: Model.clampInt(Math.round(root.spriteSize * root.fontRatio), 10, 6, 24)
  // An explicit fontSize pins the number; 0 keeps it tied to the cat.
  readonly property int textSize: {
    var v = Model.clampInt(setting("fontSize", 0), 0, 0, 24)
    return v > 0 ? v : root.proportionalTextSize
  }
  readonly property string tintSetting: stringSetting("spriteColor", "")
  // Empty follows the bar foreground, so the cat tracks the theme. Any QColor
  // string works when you want a fixed tint.
  readonly property color spriteColor: tintSetting !== "" ? tintSetting : button.foreground

  // Omaxian: no omarchy-launch-or-focus-tui; reuse the SysStats opener
  // (i3 floating term → btop, else x-terminal-emulator → btop/htop).
  readonly property string clickCommand: stringSetting(
    "clickCommand",
    "${OMARCHY_PATH:-$HOME/.local/share/omarchy}/shell/scripts/sysmon.sh"
  )
  // A command that prints the CPU percentage, e.g. "sensors | grep ...". Empty
  // reads /proc/stat directly.
  readonly property string cpuCommand: stringSetting("cpuCommand", "")
  // Optional sprite folders: numbered frames 0.svg/0.png, 1.svg/1.png, ...
  // Empty uses the bundled cat.
  readonly property string framesDir: stringSetting("framesDir", "")
  readonly property string idleFramesDir: stringSetting("idleFramesDir", "")

  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // -------------------------------------------------------------------- cpu

  property int cpuPercent: 0
  property bool hasSample: false
  property var previousJiffies: null

  function sample() {
    if (root.cpuCommand !== "") {
      if (!customProc.running) customProc.running = true
      return
    }
    statFile.reload()
    root.applyJiffies(statFile.text())
  }

  function applyJiffies(raw) {
    var current = Model.parseCpuJiffies(raw)
    if (!current) return
    var usage = Model.cpuUsage(root.previousJiffies, current)
    root.previousJiffies = current
    if (usage < 0) return
    root.cpuPercent = Math.round(usage)
    root.hasSample = true
  }

  function applyPercent(raw) {
    var usage = Model.parsePercentText(raw)
    if (usage < 0) return
    root.cpuPercent = Math.round(usage)
    root.hasSample = true
  }

  FileView {
    id: statFile
    path: root.cpuCommand === "" ? "/proc/stat" : ""
    blockAllReads: true
    printErrors: false
  }

  Process {
    id: customProc
    command: root.cpuCommand === "" ? [] : ["sh", "-c", root.cpuCommand]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyPercent(text)
    }
    stderr: StdioCollector { waitForEnd: true }
  }

  Timer {
    interval: root.sampleInterval
    running: true
    repeat: true
    onTriggered: root.sample()
  }

  // A delta needs two readings: take one now and a second shortly after so the
  // first frame does not wait out a whole interval.
  Timer {
    interval: 400
    running: true
    repeat: false
    onTriggered: root.sample()
  }

  // -------------------------------------------------------------- animation

  readonly property var builtinActiveFrames: [
    Qt.resolvedUrl("assets/active/0.svg"),
    Qt.resolvedUrl("assets/active/1.svg"),
    Qt.resolvedUrl("assets/active/2.svg"),
    Qt.resolvedUrl("assets/active/3.svg"),
    Qt.resolvedUrl("assets/active/4.svg")
  ]
  readonly property var builtinIdleFrames: [Qt.resolvedUrl("assets/idle/0.svg")]

  property var activeFrames: root.builtinActiveFrames
  property var idleFrames: root.builtinIdleFrames
  property int frameIndex: 0
  property var ticker: Model.createTicker(root.smoothMs)

  // Before the first reading the cat strolls rather than sleeps, so a bar
  // reload never starts on a pile of Z's.
  readonly property bool idlePose: !invertSpeed && hasSample && cpuPercent <= idleThreshold
  readonly property var frames: idlePose ? idleFrames : activeFrames
  readonly property int frameCount: frames ? frames.length : 0
  readonly property bool animating: showCat && frameCount > 1
  readonly property url currentFrame: frameCount > 0 ? frames[frameIndex % frameCount] : ""

  function updateTarget(immediate) {
    var utilization = root.invertSpeed
      ? 100 - root.cpuPercent
      : (root.idlePose ? 0 : root.cpuPercent)
    root.ticker.setTarget(
      Model.animationCycleMs(utilization, root.busyCycleMs, root.idleCycleMs, root.curve),
      immediate === true || !root.smooth
    )
  }

  function stepFrame() {
    if (!root.animating) {
      root.frameIndex = 0
      return
    }
    var result = root.ticker.advanceTo(Date.now(), root.frameCount)
    root.frameIndex = result.index
    // Re-arming the interval restarts the timer at the exact next boundary,
    // so frames stay even at any speed instead of quantising to one interval.
    frameTimer.interval = result.nextDelayMs
  }

  function restartAnimation() {
    root.ticker = Model.createTicker(root.smoothMs)
    root.updateTarget(true)
    root.stepFrame()
  }

  function shellQuote(path) {
    return "'" + String(path).replace(/'/g, "'\\''") + "'"
  }

  function scanFrames(dir, which) {
    if (dir === "") return
    scanProc.which = which
    scanProc.command = ["sh", "-c", "ls -1 " + shellQuote(dir) + " 2>/dev/null"]
    scanProc.running = true
  }

  function refreshFrames() {
    root.activeFrames = root.builtinActiveFrames
    root.idleFrames = root.builtinIdleFrames
    if (root.framesDir !== "") root.scanFrames(root.framesDir, "active")
    if (root.idleFramesDir !== "") root.scanFrames(root.idleFramesDir, "idle")
  }

  Process {
    id: scanProc
    command: []
    property string which: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var dir = scanProc.which === "idle" ? root.idleFramesDir : root.framesDir
        var list = Model.parseFrameList(text, dir)
        if (list.length === 0) return
        if (scanProc.which === "idle") root.idleFrames = list
        else root.activeFrames = list
      }
    }
    stderr: StdioCollector { waitForEnd: true }
  }

  Timer {
    id: frameTimer
    repeat: true
    running: root.animating
    onTriggered: root.stepFrame()
  }

  onCpuPercentChanged: root.updateTarget(false)
  onIdlePoseChanged: root.restartAnimation()
  onInvertSpeedChanged: root.restartAnimation()
  onBusyCycleMsChanged: root.updateTarget(false)
  onIdleCycleMsChanged: root.updateTarget(false)
  onCurveChanged: root.updateTarget(false)
  onSmoothMsChanged: root.restartAnimation()
  onAnimatingChanged: if (root.animating) root.restartAnimation()
  onFrameCountChanged: root.frameIndex = root.frameCount > 0 ? root.frameIndex % root.frameCount : 0
  onFramesDirChanged: if (root.framesDir !== "") root.scanFrames(root.framesDir, "active")
  onIdleFramesDirChanged: if (root.idleFramesDir !== "") root.scanFrames(root.idleFramesDir, "idle")

  Component.onCompleted: {
    root.refreshFrames()
    root.restartAnimation()
    root.sample()
  }

  // ---------------------------------------------------------------- actions

  function launchCommand() {
    if (root.clickCommand === "") return
    if (root.bar) root.bar.run(root.clickCommand)
    else Quickshell.execDetached(["bash", "-lc", root.clickCommand])
  }

  // The shell's updateEntryInline replaces the whole entry, so build the new
  // one from the config as it stands on disk rather than from this widget's
  // injected snapshot — otherwise a change would silently revert anything
  // changed since (an `omarchy bar set`, or a hand edit of shell.json).
  function currentEntry() {
    var config = root.bar && root.bar.shell ? root.bar.shell.shellConfig : null
    var layout = config && config.bar ? config.bar.layout : null
    var sections = ["left", "center", "right"]
    for (var s = 0; layout && s < sections.length; s++) {
      var entries = layout[sections[s]] || []
      for (var i = 0; i < entries.length; i++) {
        if (entries[i] && String(entries[i].id) === root.moduleName) return entries[i]
      }
    }
    return root.settings || {}
  }

  // One in-process config update per gesture, like the netspeed widget: a
  // shell round trip, not a subprocess, and no optimistic local copy that a
  // slower write could overwrite. That is what keeps fast scrolling from
  // bouncing between sizes.
  function persistSettings(values) {
    var entry = root.currentEntry()
    var next = { id: root.moduleName }
    for (var k in entry) if (k !== "id") next[k] = entry[k]

    var dirty = false
    for (var key in values) {
      if (next[key] === values[key]) continue
      next[key] = values[key]
      dirty = true
    }
    if (!dirty) return

    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function") {
      root.bar.shell.updateEntryInline(root.moduleName, next)
      return
    }
    // Omaxian has no `omarchy bar set` dispatcher; talk to the shell IPC
    // the same way upstream's omarchy-bar does.
    for (var fallbackKey in values) {
      Quickshell.execDetached([
        "omarchy-shell", "shell", "setBarWidget",
        root.moduleName, fallbackKey, JSON.stringify(values[fallbackKey]), "{}"
      ])
    }
  }

  function persistSetting(key, value) {
    var single = {}
    single[key] = value
    root.persistSettings(single)
  }

  function cycleDisplay() {
    var order = ["cat", "both", "percent"]
    root.persistSetting("display", order[(order.indexOf(root.display) + 1) % order.length])
  }

  // The wheel scales the pair: with the cat visible it drives the sprite and
  // re-ties the percentage to it (fontSize 0 follows fontRatio), so the number
  // can never outgrow the cat. With the cat hidden it steps the text alone.
  function nudgeSize(delta) {
    var step = delta > 0 ? 1 : -1
    if (root.showCat) {
      var nextSize = Model.clampInt(root.spriteSize + step, root.spriteSize, 8, 32)
      if (nextSize === root.spriteSize) return
      root.persistSettings({ size: nextSize, fontSize: 0 })
      return
    }
    if (root.showPercent) {
      var nextFont = Model.clampInt(root.textSize + step, root.textSize, 8, 24)
      if (nextFont !== root.textSize) root.persistSettings({ fontSize: nextFont })
    }
  }

  // WidgetButton tooltips are AutoText; strip markup from any clickCommand.
  function plainTip(value) {
    return String(value === undefined || value === null ? "" : value)
      .replace(/[\u0000-\u001f\u007f-\u009f]/g, "")
      .replace(/[<>&]/g, "")
      .slice(0, 160)
  }

  function tooltipText() {
    var tip = root.hasSample ? "CPU " + root.cpuPercent + "%" : "CPU …"
    tip += "\nLeft: " + (root.clickCommand === "" ? "—" : root.plainTip(root.clickCommand))
    tip += "\nRight: cat / cat+% / % · Middle: refresh · Scroll: resize"
    return tip
  }

  IpcHandler {
    target: "io.github.kaiizu.runcat"

    function refresh(): void {
      root.broadcast("sample")
    }

    function status(): string {
      return (root.hasSample ? root.cpuPercent + "%" : "—")
        + " · " + root.display + (root.idlePose ? " · idle" : "")
        + " · " + root.frameCount + " frames"
        + " · sprite " + root.spriteSize + " · text " + root.textSize
    }

    function cycleDisplay(): void { root.cycleDisplay() }
    function sizeUp(): void { root.nudgeSize(1) }
    function sizeDown(): void { root.nudgeSize(-1) }
  }

  // ----------------------------------------------------------------- layout

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    horizontalMargin: 5
    tooltipText: root.tooltipText()
    fixedWidth: root.vertical ? -1 : Math.ceil(contentRow.implicitWidth + button.scaledHorizontalMargin * 2)
    fixedHeight: root.vertical ? Style.bar.iconSlot : -1

    onPressed: function(pressedButton) {
      if (pressedButton === Qt.LeftButton) root.launchCommand()
      else if (pressedButton === Qt.MiddleButton) root.sample()
      else if (pressedButton === Qt.RightButton) root.cycleDisplay()
    }
    onWheelMoved: function(delta) {
      root.nudgeSize(delta > 0 ? 1 : -1)
    }

    Row {
      id: contentRow
      anchors.centerIn: parent
      spacing: root.showCat && root.showPercent ? Style.space(3) : 0

      Item {
        id: spriteSlot
        visible: root.showCat
        width: root.spriteSize
        height: root.spriteSize
        anchors.verticalCenter: parent.verticalCenter

        Image {
          id: sprite
          anchors.fill: parent
          source: root.currentFrame
          fillMode: Image.PreserveAspectFit
          smooth: true
          // Hidden and layered so the effect below can sample it as a texture,
          // exactly like the bar's tray does for symbolic icons.
          visible: false
          layer.enabled: true
          // Rasterize the SVG once at the largest size the widget can draw
          // (32px at the screen's pixel ratio). Tying this to the current
          // width would re-render every frame of a resize.
          sourceSize.width: Math.ceil(32 * Screen.devicePixelRatio)
          sourceSize.height: Math.ceil(32 * Screen.devicePixelRatio)
        }

        MultiEffect {
          anchors.fill: parent
          source: sprite
          colorization: 1.0
          colorizationColor: root.spriteColor
        }
      }

      Text {
        id: percentText
        visible: root.showPercent
        anchors.verticalCenter: parent.verticalCenter
        text: root.cpuPercent + "%"
        textFormat: Text.PlainText
        color: button.foreground
        font.family: root.fontFamily
        font.pixelSize: root.textSize
        renderType: Text.NativeRendering
      }
    }
  }
}

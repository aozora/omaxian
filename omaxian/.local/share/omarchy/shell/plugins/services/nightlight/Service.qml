import QtQuick
import Quickshell
import Quickshell.Io
import "NightlightModel.js" as NightlightModel

// X11 delta (§6): upstream drives Hyprland's `hyprsunset` via `hyprctl`.
// This profile uses `redshift` one-shot mode (`-P -O <temp>` / `-x` reset).
// redshift is stateless, so the panel tracks the applied temperature in a
// state file and `omarchy-toggle-nightlight` reads/writes the same one.
Item {
  id: root

  property var shell: null

  readonly property int nightTemperature: 4000
  readonly property int dayTemperature: 6500
  readonly property string stateFile: Quickshell.env("HOME") + "/.local/state/omarchy/nightlight.temp"

  property bool stateLoaded: false
  property var temperature: null
  readonly property bool enabled: stateLoaded && NightlightModel.isNightlight(temperature)

  property bool hasPendingTemperature: false
  property int pendingTemperature: 0

  function refresh() {
    if (!statusProbe.running) statusProbe.running = true
  }

  function setNightlight(value) {
    applyTemperature(value ? nightTemperature : dayTemperature)
  }

  function toggle() {
    setNightlight(!enabled)
  }

  function applyTemperature(temp) {
    root.temperature = temp
    root.stateLoaded = true

    if (applyProcess.running) {
      root.pendingTemperature = temp
      root.hasPendingTemperature = true
      return
    }
    runApply(temp)
  }

  function runApply(temp) {
    var t = Number(temp)
    var dir = Quickshell.env("HOME") + "/.local/state/omarchy"
    var file = root.stateFile
    // -P resets gamma ramps first so repeated toggles don't stack; -x is a
    // full reset for the day temperature. Then persist the applied value.
    // Paths and values stay in argv ($1…); the script string is constant.
    if (t >= root.dayTemperature) {
      applyProcess.command = [
        "bash", "-c",
        'redshift -x >/dev/null 2>&1 || true; mkdir -p -- "$1" && printf %s "$2" >"$3"',
        "nightlight-write", dir, String(t), file
      ]
    } else {
      applyProcess.command = [
        "bash", "-c",
        'redshift -P -O "$1" >/dev/null 2>&1 || true; mkdir -p -- "$2" && printf %s "$1" >"$3"',
        "nightlight-write", String(t), dir, file
      ]
    }
    applyProcess.running = true
  }

  Process {
    id: statusProbe
    property string stdoutBuf: ""
    property int maxStdout: 256
    property bool overflowed: false
    command: [
      "bash", "-c",
      'cat -- "$1" 2>/dev/null || printf %s "$2"',
      "nightlight-read", root.stateFile, String(root.dayTemperature)
    ]
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        if (statusProbe.overflowed) return
        statusProbe.stdoutBuf += chunk
        if (statusProbe.stdoutBuf.length > statusProbe.maxStdout) {
          statusProbe.overflowed = true
          statusProbe.stdoutBuf = ""
          statusProbe.signal(15)
          statusProbeKillTimer.start()
        }
      }
    }
    onStarted: {
      statusProbeKillTimer.stop()
      stdoutBuf = ""
      overflowed = false
    }
    onExited: function(exitCode) {
      statusProbeKillTimer.stop()
      var text = overflowed ? "" : String(stdoutBuf || "")
      stdoutBuf = ""
      overflowed = false
      if (exitCode !== 0) {
        root.temperature = root.dayTemperature
        root.stateLoaded = true
        return
      }
      root.temperature = NightlightModel.temperatureFromOutput(text)
      root.stateLoaded = true
    }
  }

  Timer {
    id: statusProbeKillTimer
    interval: 2000
    onTriggered: statusProbe.signal(9)
  }

  Process {
    id: applyProcess
    onExited: function() {
      if (root.hasPendingTemperature) {
        root.hasPendingTemperature = false
        root.runApply(root.pendingTemperature)
        return
      }
      root.refresh()
    }
  }

  Component.onCompleted: refresh()

  IpcHandler {
    target: "nightlight"

    function status(): string {
      return JSON.stringify({ enabled: root.enabled, temperature: root.temperature })
    }
    function refresh(): void { root.refresh() }
    function enable(): string { root.setNightlight(true); return "enabled" }
    function disable(): string { root.setNightlight(false); return "disabled" }
    function toggle(): string {
      var enabling = !root.enabled
      root.setNightlight(enabling)
      return enabling ? "enabled" : "disabled"
    }
  }
}

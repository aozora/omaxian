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
    // -P resets gamma ramps first so repeated toggles don't stack; -x is a
    // full reset for the day temperature. Then persist the applied value.
    var apply = (t >= root.dayTemperature)
      ? "redshift -x >/dev/null 2>&1 || true"
      : ("redshift -P -O " + t + " >/dev/null 2>&1 || true")
    applyProcess.command = ["bash", "-lc",
      "mkdir -p \"$(dirname '" + root.stateFile + "')\"; " +
      apply + "; printf '%s' " + t + " > \"" + root.stateFile + "\""]
    applyProcess.running = true
  }

  Process {
    id: statusProbe
    command: ["bash", "-lc", "cat \"" + root.stateFile + "\" 2>/dev/null || echo " + root.dayTemperature]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.temperature = NightlightModel.temperatureFromOutput(text)
        root.stateLoaded = true
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.temperature = root.dayTemperature
        root.stateLoaded = true
      }
    }
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

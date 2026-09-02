import QtQuick
import Quickshell
import Quickshell.Io

// X11 delta (§2b / §6): upstream is a 360-line Hyprland `IdleMonitor` service
// (idle → screensaver window / lock / DPMS wake, all via Hyprland events).
// This profile does manual lock only (scripts/i3_lock; AGENTS.md), so the
// idle-lock automation is dropped. What remains is the "stay awake" toggle
// the `StayAwake` bar indicator needs: it flips the same state file and
// drives `xset s` / DPMS so an X11 screensaver/blank is suppressed while on.
Item {
  id: root

  property var shell: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string stayAwakeStateDir: home + "/.local/state/omarchy/indicators"
  readonly property string stayAwakeStatePath: stayAwakeStateDir + "/stay-awake"

  property bool stayAwake: false
  property bool stayAwakeStateLoaded: false

  function refresh() {
    if (!stateProbe.running) stateProbe.running = true
  }

  // The indicator calls setIdleEnabled(currentActive): `active` is `stayAwake`,
  // so it's asking to flip to the other state.
  function setIdleEnabled(currentlyAwake) {
    setStayAwake(!currentlyAwake)
  }

  function setStayAwake(value) {
    root.stayAwake = value
    root.stayAwakeStateLoaded = true
    applyProc.command = ["bash", "-lc",
      "mkdir -p \"" + root.stayAwakeStateDir + "\"; " +
      (value
        ? "echo 1 > \"" + root.stayAwakeStatePath + "\"; xset s off -dpms"
        : "echo 0 > \"" + root.stayAwakeStatePath + "\"; xset s on +dpms; xset s default")]
    applyProc.running = true
  }

  Process {
    id: stateProbe
    command: ["bash", "-lc", "cat \"" + root.stayAwakeStatePath + "\" 2>/dev/null || echo 0"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var on = String(text || "").trim() === "1"
        root.stayAwakeStateLoaded = true
        // Re-assert `xset s off` on a fresh session that had stay-awake on.
        if (on) root.setStayAwake(true)
        else root.stayAwake = false
      }
    }
    onExited: root.stayAwakeStateLoaded = true
  }

  Process { id: applyProc }

  Component.onCompleted: refresh()

  IpcHandler {
    target: "idle"

    function status(): string {
      return JSON.stringify({ stayAwake: root.stayAwake })
    }
    function refresh(): void { root.refresh() }
    function stayAwakeOn(): string { root.setStayAwake(true); return "on" }
    function stayAwakeOff(): string { root.setStayAwake(false); return "off" }
    function toggle(): string {
      root.setStayAwake(!root.stayAwake)
      return root.stayAwake ? "on" : "off"
    }
  }
}

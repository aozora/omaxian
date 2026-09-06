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
    // Paths stay in argv ($1/$2); the script string is constant.
    if (value) {
      applyProc.command = [
        "bash", "-c",
        'mkdir -p -- "$1" && printf %s 1 >"$2" && xset s off -dpms',
        "idle-awake", root.stayAwakeStateDir, root.stayAwakeStatePath
      ]
    } else {
      applyProc.command = [
        "bash", "-c",
        'mkdir -p -- "$1" && printf %s 0 >"$2" && xset s on +dpms && xset s default',
        "idle-sleep", root.stayAwakeStateDir, root.stayAwakeStatePath
      ]
    }
    applyProc.running = true
  }

  Process {
    id: stateProbe
    property string stdoutBuf: ""
    property int maxStdout: 256
    property bool overflowed: false
    command: [
      "bash", "-c",
      'cat -- "$1" 2>/dev/null || printf %s 0',
      "idle-read", root.stayAwakeStatePath
    ]
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        if (stateProbe.overflowed) return
        stateProbe.stdoutBuf += chunk
        if (stateProbe.stdoutBuf.length > stateProbe.maxStdout) {
          stateProbe.overflowed = true
          stateProbe.stdoutBuf = ""
          stateProbe.signal(15)
          stateProbeKillTimer.start()
        }
      }
    }
    onStarted: {
      stateProbeKillTimer.stop()
      stdoutBuf = ""
      overflowed = false
    }
    onExited: function() {
      stateProbeKillTimer.stop()
      var text = overflowed ? "" : String(stdoutBuf || "")
      stdoutBuf = ""
      overflowed = false
      var on = String(text || "").trim() === "1"
      root.stayAwakeStateLoaded = true
      // Re-assert `xset s off` on a fresh session that had stay-awake on.
      if (on) root.setStayAwake(true)
      else root.stayAwake = false
    }
  }

  Timer {
    id: stateProbeKillTimer
    interval: 2000
    onTriggered: stateProbe.signal(9)
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

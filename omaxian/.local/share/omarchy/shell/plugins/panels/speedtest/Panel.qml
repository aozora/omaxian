import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// The shared gauge-cluster overlay (SpeedTestOverlay) dressed for the
// internet speed test: download and upload dials in Mbps, titled with the
// connection under test.
//
// Standalone panel plugin: summoning it starts a fresh run, dismissing it
// stops the traffic, so the download workers never keep saturating the link
// behind a closed overlay. The payload may carry the connection's display
// name -- {"connection": "MyWifi"} -- and the panel looks it up itself via
// omarchy-network-status when the caller doesn't know it.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property string connectionName: ""

  property bool running: false
  property bool expectedStop: false
  property bool pendingRun: false
  property string phase: ""        // "down" | "up" | ""
  property string stderrText: ""
  property string downloadMbps: ""
  property string uploadMbps: ""
  property string error: ""

  readonly property real downloadValue: toMbps(downloadMbps)
  readonly property real uploadValue: toMbps(uploadMbps)

  function toMbps(raw) {
    var value = parseFloat(raw)
    return isFinite(value) && value > 0 ? value : 0
  }

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (e) {}
    if (payload.connection !== undefined) root.connectionName = String(payload.connection)
    else refreshConnectionName()
    root.opened = true
    runSpeedTest()
  }

  function close() {
    root.opened = false
    root.pendingRun = false
    phaseTimer.stop()
    // Clear the phase before killing the process: onExited advances to the
    // upload phase when it still reads "down".
    root.phase = ""
    root.running = false
    if (speedTestProc.running) {
      root.expectedStop = true
      speedTestProc.running = false
    }
  }

  function dismiss() {
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "omarchy.speedtest")
    else close()
  }

  function refreshConnectionName() {
    root.connectionName = ""
    statusProc.running = false
    statusProc.running = true
  }

  function updateSpeedTestLine(line) {
    var value = parseFloat(line)
    if (!isFinite(value) || value < 0) return

    if (phase === "down") downloadMbps = String(value)
    else if (phase === "up") uploadMbps = String(value)
  }

  function runSpeedTest() {
    if (speedTestProc.running) {
      // A dismissal's SIGTERM is still in flight; Process.running stays true
      // until the child exits, so queue the fresh run for onExited.
      if (expectedStop) pendingRun = true
      return
    }
    error = ""
    downloadMbps = ""
    uploadMbps = ""
    running = true
    startPhase("down")
  }

  function startPhase(nextPhase) {
    expectedStop = false
    phase = nextPhase
    stderrText = ""
    speedTestProc.command = ["omarchy-network-speedtest", nextPhase]
    speedTestProc.running = true
    phaseTimer.restart()
  }

  function stopPhase() {
    phaseTimer.stop()
    if (speedTestProc.running) {
      expectedStop = true
      speedTestProc.running = false
      return
    }
    finishPhase()
  }

  function finishPhase() {
    if (phase === "down") {
      startPhase("up")
      return
    }

    phase = ""
    running = false
    expectedStop = false
  }

  Process {
    id: speedTestProc
    property string stderrBuf: ""
    property int maxStderr: 16384
    property bool overflowed: false
    stdout: SplitParser { onRead: function(line) { root.updateSpeedTestLine(line) } }
    stderr: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        if (speedTestProc.overflowed) return
        speedTestProc.stderrBuf += chunk
        if (speedTestProc.stderrBuf.length > speedTestProc.maxStderr) {
          speedTestProc.overflowed = true
          speedTestProc.stderrBuf = ""
          speedTestProc.signal(15)
          speedTestKillTimer.start()
        }
      }
    }
    onStarted: {
      speedTestKillTimer.stop()
      stderrBuf = ""
      overflowed = false
    }
    onExited: function(exitCode) {
      speedTestKillTimer.stop()
      phaseTimer.stop()
      root.stderrText = overflowed ? "" : String(stderrBuf || "").trim()
      stderrBuf = ""
      overflowed = false

      if (root.pendingRun) {
        root.pendingRun = false
        root.expectedStop = false
        if (root.opened) Qt.callLater(root.runSpeedTest)
        return
      }

      if (!root.expectedStop && exitCode !== 0) {
        root.error = root.stderrText || "Speed test failed"
        root.phase = ""
        root.running = false
        return
      }

      root.expectedStop = false
      root.finishPhase()
    }
  }

  Timer {
    id: speedTestKillTimer
    interval: 2000
    onTriggered: speedTestProc.signal(9)
  }

  Timer {
    id: phaseTimer
    interval: 5000
    repeat: false
    onTriggered: root.stopPhase()
  }

  // Names the connection under test when the summoner didn't. First tab
  // field is the kind, second the SSID (wifi) or device (ethernet).
  Process {
    id: statusProc
    property string stdoutBuf: ""
    property int maxStdout: 4096
    property bool overflowed: false
    command: ["omarchy-network-status"]
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        if (statusProc.overflowed) return
        statusProc.stdoutBuf += chunk
        if (statusProc.stdoutBuf.length > statusProc.maxStdout) {
          statusProc.overflowed = true
          statusProc.stdoutBuf = ""
          statusProc.signal(15)
          statusKillTimer.start()
        }
      }
    }
    onStarted: {
      statusKillTimer.stop()
      stdoutBuf = ""
      overflowed = false
    }
    onExited: function() {
      statusKillTimer.stop()
      var raw = overflowed ? "" : String(stdoutBuf || "").trim()
      stdoutBuf = ""
      overflowed = false
      if (!raw) return
      var fields = raw.split("\t")
      if (fields[0] === "wifi") root.connectionName = fields[1] || "Wi-Fi"
      else if (fields[0] === "ethernet") root.connectionName = "Ethernet"
    }
  }

  Timer {
    id: statusKillTimer
    interval: 2000
    onTriggered: statusProc.signal(9)
  }

  SpeedTestOverlay {
    fontFamily: Style.font.family
    layerNamespace: "omarchy-network-speedtest"
    title: root.connectionName
    leftLabel: "DOWNLOAD"
    rightLabel: "UPLOAD"
    runAgainTooltip: "Measure again via fast.com"
    running: root.running
    leftValue: root.downloadValue
    rightValue: root.uploadValue
    leftLive: root.running && root.phase === "down"
    rightLive: root.running && root.phase === "up"
    error: root.error
    open: root.opened
    onCloseRequested: root.dismiss()
    onRunAgainRequested: root.runSpeedTest()
  }
}

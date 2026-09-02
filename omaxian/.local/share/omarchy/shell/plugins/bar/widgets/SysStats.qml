import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Local (§6 decision 6): cpu / gpu / ram as 3 readouts — no omarchy
// equivalent. Reads /proc/stat +
// /proc/meminfo; GPU via scripts/gpu.sh (nvidia-smi / radeontop /
// intel_gpu_top by vendor). 2s poll.
// Phase 8: reshaped from a bare `Row` to a `BarWidget` so it slots into the
// plugins/bar registry.
BarWidget {
  id: root
  moduleName: "omaxian.sysstats"

  property real cpuPercent: 0
  property real ramPercent: 0
  property string gpuText: "󰓅 …"
  property var _prevCpu: null

  function pad2(n) {
    return String(Math.round(n)).padStart(2, "0")
  }

  function _parseCpuLine(text) {
    var line = text.split("\n")[0]
    var parts = line.trim().split(/\s+/).slice(1).map(Number)
    var idle = parts[3] + parts[4]
    var total = parts.reduce(function(a, b) { return a + b }, 0)
    return { idle: idle, total: total }
  }

  Timer {
    interval: 2000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      cpuProc.running = true
      ramProc.running = true
      gpuProc.running = true
    }
  }

  Process {
    id: cpuProc
    command: ["cat", "/proc/stat"]
    stdout: StdioCollector {
      onStreamFinished: {
        var cur = root._parseCpuLine(text)
        if (root._prevCpu) {
          var idleDelta = cur.idle - root._prevCpu.idle
          var totalDelta = cur.total - root._prevCpu.total
          if (totalDelta > 0) root.cpuPercent = Math.max(0, Math.min(100, 100 * (1 - idleDelta / totalDelta)))
        }
        root._prevCpu = cur
      }
    }
  }

  Process {
    id: ramProc
    command: ["cat", "/proc/meminfo"]
    stdout: StdioCollector {
      onStreamFinished: {
        var total = 0, avail = 0
        var lines = text.split("\n")
        for (var i = 0; i < lines.length; i++) {
          var m = lines[i].match(/^MemTotal:\s+(\d+)/)
          if (m) total = Number(m[1])
          m = lines[i].match(/^MemAvailable:\s+(\d+)/)
          if (m) avail = Number(m[1])
        }
        if (total > 0) root.ramPercent = Math.max(0, Math.min(100, 100 * (1 - avail / total)))
      }
    }
  }

  Process {
    id: gpuProc
    command: ["bash", Quickshell.shellDir + "/scripts/gpu.sh"]
    stdout: StdioCollector {
      onStreamFinished: {
        var t = text.trim()
        if (t.length > 0) root.gpuText = t
      }
    }
  }

  implicitWidth: statRow.implicitWidth
  implicitHeight: statRow.implicitHeight

  Row {
    id: statRow
    anchors.fill: parent
    spacing: Style.spacing.xxs

    WidgetButton {
      bar: root.bar
      anchors.verticalCenter: parent.verticalCenter
      fontSize: Style.font.body
      text: " " + root.pad2(root.cpuPercent) + "%"
      foreground: Color.bar.text
      horizontalMargin: 6
      verticalPadding: 4
      onPressed: root.bar.run(Quickshell.shellDir + "/scripts/sysmon.sh")
    }
    WidgetButton {
      bar: root.bar
      anchors.verticalCenter: parent.verticalCenter
      fontSize: Style.font.body
      text: root.gpuText
      foreground: Color.bar.text
      horizontalMargin: 6
      verticalPadding: 4
      onPressed: root.bar.run(Quickshell.shellDir + "/scripts/sysmon.sh")
    }
    WidgetButton {
      bar: root.bar
      anchors.verticalCenter: parent.verticalCenter
      fontSize: Style.font.body
      text: "﬙ " + root.pad2(root.ramPercent) + "%"
      foreground: Color.bar.text
      horizontalMargin: 6
      verticalPadding: 4
      onPressed: root.bar.run(Quickshell.shellDir + "/scripts/sysmon.sh")
    }
  }
}

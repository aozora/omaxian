import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Control Panel tab: display/monitor configuration. A fresh
// reimplementation of plugins/panels/monitor/Panel.qml's content — Control
// Panel is a standalone plugin, this file has no runtime dependency on the
// original.
//
// Deliberately simplified vs. the original: no keyboard D-pad cursor system
// (sectionIndex/pillIndex/moveCursor/activateCursor) — same mouse-only
// simplification as every other tab here. The original's D-pad also
// intercepted Tab for bar-panel-cycling, which is exactly the conflict
// Panel.qml's own header comment explains this plugin avoids by not giving
// any tab its own PanelKeyCatcher.
Item {
  id: root

  // Not `required`: injected by Control Panel's Loader.setSource() map —
  // see AudioTab.qml for the rationale.
  property QtObject bar: null
  property bool active: false

  property var outputs: []
  property bool lidPresent: false
  property bool lidClosed: false

  readonly property var connectedOutputs: Model.monitorToArray(root.outputs).filter(function(o) { return !!(o && o.connected) })

  implicitWidth: Style.space(380)
  implicitHeight: column.implicitHeight

  function refresh() {
    if (!listProc.running) listProc.running = true
  }

  function setMode(name, mode) {
    if (!name || !mode || setProc.running) return
    setProc.command = ["omarchy-monitor-set", name, mode]
    setProc.running = true
  }

  function setOff(name) {
    if (!name || setProc.running) return
    setProc.command = ["omarchy-monitor-set", name, "--off"]
    setProc.running = true
  }

  function toggleOutput(output) {
    if (!output) return
    if (output.enabled) { root.setOff(output.name); return }
    var mode = output.currentMode || output.preferredMode
    if (!mode) {
      var modes = Model.sortModes(output.modes || [])
      mode = modes.length > 0 ? modes[0] : ""
    }
    if (mode) root.setMode(output.name, mode)
  }

  function ingest(raw) {
    var text = String(raw || "").trim()
    if (!text) return
    try {
      var data = JSON.parse(text)
    } catch (e) {
      return
    }
    if (!data || typeof data !== "object") return
    if (Array.isArray(data.outputs)) root.outputs = data.outputs
    if (typeof data.lidPresent === "boolean") root.lidPresent = data.lidPresent
    if (typeof data.lidClosed === "boolean") root.lidClosed = data.lidClosed
  }

  onActiveChanged: if (active) refresh()

  Process {
    id: listProc
    command: ["omarchy-monitor-list"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.ingest(text) }
  }

  Process {
    id: setProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.ingest(text) }
  }

  Timer { interval: 3000; running: root.active; repeat: true; onTriggered: root.refresh() }

  Column {
    id: column
    width: parent.width
    spacing: Style.space(14)

    // ---------- Hero ----------
    Item {
      width: parent.width
      implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

      Text {
        id: heroIcon
        textFormat: Text.PlainText
        text: Model.monitorIconFor(root.outputs)
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.display
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Column {
        id: heroLabels
        anchors.left: heroIcon.right
        anchors.leftMargin: Style.space(14)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Text {
          text: "Monitor"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
          elide: Text.ElideRight
          width: parent.width
        }

        Text {
          textFormat: Text.PlainText
          text: Model.monitorStatusLine(root.outputs, root.lidPresent, root.lidClosed).toUpperCase()
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1.2
          elide: Text.ElideRight
          width: parent.width
        }
      }
    }

    PanelSeparator { foreground: root.bar.foreground }

    Column {
      width: parent.width
      spacing: Style.space(14)
      visible: root.connectedOutputs.length > 0

      Repeater {
        model: root.connectedOutputs

        Column {
          id: outputSection
          required property var modelData
          readonly property var output: modelData

          width: parent.width
          spacing: Style.space(8)

          Item {
            width: parent.width
            implicitHeight: Math.max(sectionHeader.implicitHeight, offButton.implicitHeight)

            PanelSectionHeader {
              id: sectionHeader
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: outputSection.output.name.toUpperCase()
                + (outputSection.output.isLaptopPanel ? " (LAPTOP)" : "")
                + (outputSection.output.primary ? " · PRIMARY" : "")
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            Button {
              id: offButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              visible: root.connectedOutputs.length >= 2
              text: outputSection.output.enabled ? "Off" : "On"
              fontSize: Style.font.bodySmall
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              bordered: true
              onClicked: root.toggleOutput(outputSection.output)
            }
          }

          Flow {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: Model.sortModes(outputSection.output.modes || [])

              Button {
                required property var modelData
                text: modelData
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
                active: modelData === outputSection.output.currentMode
                onClicked: root.setMode(outputSection.output.name, modelData)
              }
            }
          }
        }
      }
    }

    Text {
      visible: root.connectedOutputs.length === 0
      text: "No displays detected"
      color: Qt.darker(root.bar.foreground, 1.5)
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.italic: true
    }
  }
}

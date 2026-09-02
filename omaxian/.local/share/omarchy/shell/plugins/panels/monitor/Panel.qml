import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "omaxian.monitor"
  ipcTarget: "omaxian.monitor"
  // manageIpc: false so this panel can own the single IpcHandler the target
  // permits — needed for the refresh method below.
  manageIpc: false

  property var outputs: []
  property bool lidPresent: false
  property bool lidClosed: false
  property bool cursorActive: false
  property int sectionIndex: 0
  property int pillIndex: 0

  readonly property var connectedOutputs: (root.outputs || []).filter(function(o) { return !!(o && o.connected) })

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
    if (output.enabled) {
      root.setOff(output.name)
      return
    }
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

  function moveCursor(dx, dy) {
    if (!root.cursorActive) {
      root.cursorActive = true
      return
    }
    var sections = root.connectedOutputs
    if (sections.length === 0) return

    if (dy !== 0) {
      root.sectionIndex = Math.max(0, Math.min(sections.length - 1, root.sectionIndex + dy))
      var modesForSection = Model.sortModes(sections[root.sectionIndex].modes || [])
      root.pillIndex = Math.max(0, Math.min(Math.max(0, modesForSection.length - 1), root.pillIndex))
    } else if (dx !== 0) {
      var section = sections[root.sectionIndex]
      var modes = section ? Model.sortModes(section.modes || []) : []
      if (modes.length === 0) return
      root.pillIndex = Math.max(0, Math.min(modes.length - 1, root.pillIndex + dx))
    }
  }

  function activateCursor() {
    if (!root.cursorActive) return
    var sections = root.connectedOutputs
    if (root.sectionIndex < 0 || root.sectionIndex >= sections.length) return
    var output = sections[root.sectionIndex]
    var modes = Model.sortModes(output.modes || [])
    if (root.pillIndex < 0 || root.pillIndex >= modes.length) return
    root.setMode(output.name, modes[root.pillIndex])
  }

  IpcHandler {
    target: "omaxian.monitor"

    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
    function refresh() { root.refresh() }
  }

  onOpenedChanged: {
    if (opened) {
      refresh()
      cursorActive = false
      sectionIndex = 0
      pillIndex = 0
    }
  }

  Process {
    id: listProc
    command: ["omarchy-monitor-list"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.ingest(text) }
  }

  Process {
    id: setProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.ingest(text) }
  }

  Timer { interval: 3000; running: root.opened; repeat: true; onTriggered: root.refresh() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Model.iconFor(root.outputs)
    tooltipText: ""
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero: icon · title/status ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: Model.iconFor(root.outputs)
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
              text: Model.statusLine(root.outputs, root.lidPresent, root.lidClosed).toUpperCase()
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

        PanelSeparator {
          foreground: root.bar.foreground
        }

        // ---------- One section per connected output ----------
        Column {
          width: parent.width
          spacing: Style.space(14)
          visible: root.connectedOutputs.length > 0

          Repeater {
            model: root.connectedOutputs

            Column {
              id: outputSection
              required property var modelData
              required property int index
              readonly property var output: modelData
              readonly property int outputIndex: index

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
                id: pillRow
                width: parent.width
                spacing: Style.space(6)

                Repeater {
                  model: Model.sortModes(outputSection.output.modes || [])

                  Button {
                    required property var modelData
                    required property int index
                    text: modelData
                    fontSize: Style.font.bodySmall
                    foreground: root.bar.foreground
                    fontFamily: root.bar.fontFamily
                    horizontalPadding: Style.spacing.controlPaddingX
                    verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                    bordered: true
                    active: modelData === outputSection.output.currentMode
                    hasCursor: root.cursorActive && root.sectionIndex === outputSection.outputIndex && root.pillIndex === index
                    onClicked: root.setMode(outputSection.output.name, modelData)
                    onHovered: function(h) {
                      if (h) {
                        root.cursorActive = true
                        root.sectionIndex = outputSection.outputIndex
                        root.pillIndex = index
                      }
                    }
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
  }
}

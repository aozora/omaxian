import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Item {
  id: root

  property var shell: null
  property var pluginRegistry: null
  property var barWidgetRegistry: null
  property color foreground: Commons.Color.popups.text

  readonly property string fontFamily: Style.font.family
  readonly property color muted: Qt.darker(root.foreground, 1.45)

  property var sections: []
  property string statusMessage: ""
  property bool loading: false

  function reload() {
    if (infoProc.running) {
      infoProc.signal(15)
      infoKill.start()
    }
    root.loading = true
    root.statusMessage = ""
    root.sections = []
    infoProc.stdoutBuf = ""
    infoProc.overflowed = false
    infoProc.running = true
  }

  function applyPayload(text) {
    root.loading = false
    var raw = String(text || "").trim()
    if (!raw.length) {
      root.statusMessage = "No system info returned"
      root.sections = []
      return
    }
    try {
      var data = JSON.parse(raw)
      root.sections = Array.isArray(data.sections) ? data.sections : []
      if (!root.sections.length)
        root.statusMessage = "Empty system info"
    } catch (e) {
      root.statusMessage = "Could not parse system info"
      root.sections = []
    }
  }

  Component.onCompleted: root.reload()

  Process {
    id: infoProc
    property string stdoutBuf: ""
    property int maxStdout: 262144
    property bool overflowed: false
    command: ["omarchy-system-info"]
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        if (infoProc.overflowed) return
        infoProc.stdoutBuf += chunk
        if (infoProc.stdoutBuf.length > infoProc.maxStdout) {
          infoProc.overflowed = true
          infoProc.stdoutBuf = ""
          infoProc.signal(15)
          infoKill.start()
        }
      }
    }
    onStarted: {
      infoKill.stop()
      stdoutBuf = ""
      overflowed = false
    }
    onExited: function(code) {
      infoKill.stop()
      var text = overflowed ? "" : String(stdoutBuf || "")
      stdoutBuf = ""
      overflowed = false
      if (code !== 0 && !text.length) {
        root.loading = false
        root.statusMessage = "omarchy-system-info failed (exit " + code + ")"
        root.sections = []
        return
      }
      root.applyPayload(text)
    }
  }

  Timer {
    id: infoKill
    interval: 400
    repeat: false
    onTriggered: {
      if (infoProc.running) infoProc.signal(9)
    }
  }

  Flickable {
    id: flick
    anchors.fill: parent
    clip: true
    contentWidth: width
    contentHeight: col.implicitHeight
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: col
      width: flick.width
      spacing: Style.space(10)

      Item {
        width: parent.width
        height: Math.max(aboutTitle.implicitHeight, refreshBtn.implicitHeight)

        Text {
          id: aboutTitle
          textFormat: Text.PlainText
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "About"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Button {
          id: refreshBtn
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: root.loading ? "Loading…" : "Refresh"
          enabled: !root.loading
          bordered: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.reload()
        }
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        wrapMode: Text.Wrap
        visible: root.statusMessage.length > 0
        text: root.statusMessage
        color: Commons.Color.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        wrapMode: Text.Wrap
        visible: root.loading && root.sections.length === 0 && root.statusMessage.length === 0
        text: "Gathering system info…"
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Repeater {
        model: root.sections

        delegate: Column {
          required property var modelData
          width: col.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: String(modelData.title || "")
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Repeater {
            model: modelData.rows || []

            delegate: Row {
              required property var modelData
              width: col.width
              spacing: Style.space(12)

              Text {
                textFormat: Text.PlainText
                width: Style.space(110)
                text: String(modelData.label || "")
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width - Style.space(110) - parent.spacing
                wrapMode: Text.Wrap
                text: String(modelData.value || "")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }
          }
        }
      }
    }
  }
}

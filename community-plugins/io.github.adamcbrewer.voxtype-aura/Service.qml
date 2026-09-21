import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.I3
import Quickshell.Io
import qs.Commons

// Omaxian (X11/i3): upstream used the compositor focused-monitor API plus a
// layer-shell PanelWindow. Here: Quickshell.I3 for the focused output, and an
// OSD-style 1px host strip + grabFocus:false PopupWindow so picom does not
// black out tiled clients and dictation never steals keyboard focus.

Item {
  id: root

  property string state: "idle"
  property int animationFrame: 0
  property var audioSamples: []

  readonly property string pluginRoot: decodeURIComponent(String(Qt.resolvedUrl("."))
    .replace(/^file:\/\//, "")).replace(/\/$/, "")
  readonly property string statusBin: pluginRoot + "/bin/aura-status"
  readonly property string audioBin: pluginRoot + "/bin/aura-audio"

  readonly property bool active: state === "recording" || state === "transcribing" || state === "success"
  readonly property color successColor: Qt.hsla(0.33, Math.max(0.35, Color.accent.hslSaturation), Color.accent.hslLightness, 1)
  readonly property color stateColor: state === "recording" ? Color.urgent
    : state === "success" ? successColor : Color.accent
  readonly property string label: state === "recording" ? "LISTENING"
    : state === "success" ? "TRANSCRIBED" : "TRANSCRIBING"
  readonly property string iconFontFamily: "JetBrainsMono Nerd Font"
  readonly property string focusedScreenName: I3.focusedMonitor
    ? String(I3.focusedMonitor.name || "") : ""
  readonly property var activeScreen: {
    for (var i = 0; i < Quickshell.screens.length; i++) {
      if (Quickshell.screens[i].name === focusedScreenName) return Quickshell.screens[i]
    }
    return Quickshell.screens.length ? Quickshell.screens[0] : null
  }
  readonly property real screenW: activeScreen ? activeScreen.width : 0
  readonly property int cardWidth: 320
  readonly property int cardHeight: 76

  function update(raw) {
    try {
      var data = JSON.parse(String(raw || "{}"))
      var nextState = String(data.alt || data.class || "idle")
      if (nextState === "recording" || nextState === "transcribing") {
        if (nextState === "recording" && state !== "recording") audioSamples = []
        if (nextState === "transcribing" && state !== "transcribing") animationFrame = 0
        state = nextState
      } else if (state === "transcribing") {
        state = "success"
      } else if (state !== "success") {
        state = "idle"
      }
    } catch (error) {
      state = "idle"
    }
  }

  function updateAudio(raw) {
    try {
      var data = JSON.parse(String(raw || "{}"))
      if (state !== "recording" || typeof data.peak !== "number") return

      var next = audioSamples.slice()
      next.push(Math.max(0, Math.min(1, data.peak)))
      while (next.length > 40) next.shift()
      audioSamples = next
    } catch (error) {
    }
  }

  function barHeight(index) {
    if (state === "success") return 5

    if (state === "recording" && audioSamples.length) {
      var sampleIndex = Math.min(audioSamples.length - 1,
        Math.floor(index * (audioSamples.length - 1) / 7))
      return 5 + Math.min(1, audioSamples[sampleIndex] * 20) * 16
    }

    var distance = Math.abs(index - (animationFrame % 15))
    distance = Math.min(distance, 15 - distance)
    return 5 + Math.max(0, 16 - distance * 5)
  }

  Process {
    id: statusProcess

    command: [root.statusBin]
    running: true
    stdout: SplitParser {
      onRead: function(data) { root.update(data) }
    }
    onExited: function() {
      root.state = "idle"
      statusRetry.restart()
    }
  }

  Process {
    id: audioBridge

    command: [root.audioBin]
    running: true
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(data) { root.updateAudio(data) }
    }
    onExited: function() {
      audioRetry.restart()
    }
  }

  Timer {
    id: audioRetry

    interval: 1000
    onTriggered: audioBridge.running = true
  }

  Timer {
    id: statusRetry

    interval: 1000
    onTriggered: statusProcess.running = true
  }

  Timer {
    interval: 80
    repeat: true
    running: root.state === "transcribing"
    onTriggered: root.animationFrame = (root.animationFrame + 1) % 120
  }

  Timer {
    interval: 1300
    running: root.state === "success"
    onTriggered: root.state = "idle"
  }

  // 1px host strip: PopupWindow anchor only. Never a full-screen transparent
  // PanelWindow (picom glx unredirects those and paints clients black).
  PanelWindow {
    id: host

    visible: root.active && root.activeScreen !== null
    screen: root.activeScreen
    anchors { top: true; left: true; right: true }
    implicitHeight: 1
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
  }

  PopupWindow {
    id: surface

    visible: root.active && root.activeScreen !== null
    color: "transparent"
    surfaceFormat.opaque: false
    implicitWidth: root.cardWidth
    implicitHeight: root.cardHeight
    // Static false: latched at create time. Must not steal keyboard/pointer
    // from the window receiving dictated text.
    grabFocus: false

    anchor {
      window: host
      edges: Edges.Top | Edges.Left
      gravity: Edges.Bottom | Edges.Right
      adjustment: PopupAdjustment.Slide
      rect.width: 1
      rect.height: 1
      rect.x: Math.round(Math.max(0, (root.screenW - root.cardWidth) / 2))
      rect.y: Style.gapsOut
    }

    Rectangle {
      id: glowSource

      visible: false
      width: 292
      height: 50
      anchors.centerIn: parent
      radius: Math.min(height / 2, Style.cornerRadius)
      color: root.stateColor
    }

    MultiEffect {
      anchors.fill: glowSource
      source: glowSource
      autoPaddingEnabled: true
      blurEnabled: true
      blur: 0.9
      blurMax: 18
      blurMultiplier: 1
      opacity: 0.42
      scale: 1.02
    }

    Rectangle {
      width: 292
      height: 50
      anchors.centerIn: parent
      radius: Math.min(height / 2, Style.cornerRadius)
      color: Util.alpha(Color.background, 0.94)
      border.width: 1
      border.color: root.stateColor

      Row {
        anchors.fill: parent
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        spacing: 18

        Text {
          width: 24
          height: parent.height
          verticalAlignment: Text.AlignVCenter
          horizontalAlignment: Text.AlignHCenter
          text: root.state === "success" ? "\uf00c" : "\uf130"
          color: root.stateColor
          font.family: root.iconFontFamily
          font.pixelSize: 20
          renderType: Text.NativeRendering
        }

        Item {
          width: 80
          height: parent.height

          Row {
            anchors.centerIn: parent
            spacing: 5

            Repeater {
              model: 8

              Rectangle {
                required property int index

                width: 3
                height: root.barHeight(index)
                anchors.verticalCenter: parent.verticalCenter
                radius: 1.5
                color: root.stateColor

                Behavior on height {
                  NumberAnimation { duration: 85; easing.type: Easing.OutCubic }
                }
              }
            }
          }
        }

        Text {
          width: 116
          height: parent.height
          verticalAlignment: Text.AlignVCenter
          horizontalAlignment: Text.AlignRight
          text: root.label
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.weight: Font.Medium
          font.letterSpacing: 1.2
          renderType: Text.NativeRendering
        }
      }
    }
  }
}

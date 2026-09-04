import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import qs.Services
import "Model.js" as Model

// Control Panel tab: audio output/input/per-app streams. A fresh
// reimplementation of plugins/panels/audio/Panel.qml's content — Control
// Panel is a standalone plugin, this file has no runtime dependency on the
// original (see Panel.qml's header comment).
//
// Deliberately simplified vs. the original:
//  - No keyboard-cursor navigation (focusSection/selectedIndex/moveCursor).
//    Every control is mouse-driven, same interaction model as the
//    Wallpaper/Theme tabs; row highlight follows plain hover instead of a
//    shared panel-wide cursor position.
//  - No DSP-passthrough sink resolution (omarchy-audio-output-sink /
//    -sink-availability) — volume/mute act on Audio.defaultAudioSink
//    directly. Regresses only setups routing through a speaker-tuning/
//    EasyEffects sink chain.
//  - No wheel-to-adjust-volume on the (now removed) standalone bar icon —
//    matches Wallpaper/Theme, which never had that either.
Item {
  id: root

  // Not `required`: Panel.qml loads this tab via Loader.setSource() and
  // injects `bar` in the initial-property map. A required prop would reject
  // URL-only loads (empty pane, no icon-side failure).
  property QtObject bar: null
  property bool active: false

  readonly property var sink: Audio.defaultAudioSink
  readonly property var source: Audio.defaultAudioSource
  readonly property var nodes: Audio.nodes ? Audio.nodes.values : []

  readonly property var candidateSinks: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n && n.isSink && !n.isStream) list.push(n)
    }
    return list
  }

  readonly property var candidateSources: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n && !n.isSink && !n.isStream && Model.isAudioSource(n)) {
        if ((n.name || "") === "quickshell") continue
        list.push(n)
      }
    }
    return list
  }

  readonly property var audioStreams: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (!n || !n.isStream || !Model.isPlaybackStream(n)) continue
      if (String(n.name || "").indexOf("omarchy_speaker_tuning") === 0) continue
      if (n.audio) list.push(n)
    }
    return list
  }

  readonly property real outputVolume: sink && sink.audio ? sink.audio.volume : 0
  readonly property bool outputMuted: sink && sink.audio ? sink.audio.muted : false
  readonly property real inputVolume: source && source.audio ? source.audio.volume : 0
  readonly property bool inputMuted: source && source.audio ? source.audio.muted : false
  readonly property bool hasOutput: !!(sink && sink.audio)
  readonly property bool hasInput: !!(source && source.audio)
  readonly property bool anyAudible: (hasOutput && !outputMuted) || (hasInput && !inputMuted)

  // Wider than the original standalone panel's 380 (which had the whole
  // popup to itself): here this tab's width is the *content* column next to
  // the tab sidebar, and 380 was cutting off the trailing OUTPUT/INPUT
  // percentage labels and squeezing device-row text against the edge.
  implicitWidth: Style.space(460)
  implicitHeight: column.implicitHeight

  function outputIcon(volume) {
    if (!sink || !sink.audio) return "󰝟"
    if (Model.isHeadphones(sink)) return "󰋋"
    if (outputMuted) return "󰝟"
    var v = volume === undefined ? outputVolume : volume
    if (v >= 0.67) return "󰕾"
    if (v >= 0.34) return "󰖀"
    if (v > 0) return "󰕿"
    return "󰝟"
  }

  function setOutputVolume(v) {
    if (!sink || !sink.audio) return outputVolume
    var volume = Math.max(0, Math.min(1, v))
    sink.audio.volume = volume
    return volume
  }

  function setInputVolume(v) {
    if (!source || !source.audio) return
    source.audio.volume = Math.max(0, Math.min(1, v))
  }

  function toggleOutputMute() { if (sink && sink.audio) sink.audio.muted = !sink.audio.muted }
  function toggleInputMute() { if (source && source.audio) source.audio.muted = !source.audio.muted }

  function toggleAllMuted() {
    var mute = anyAudible
    if (hasOutput) sink.audio.muted = mute
    if (hasInput) source.audio.muted = mute
  }

  function setDefaultSink(node) {
    if (!node) return
    Audio.preferredDefaultAudioSink = node
    if (node.index !== undefined && node.name)
      Quickshell.execDetached(["omarchy-audio-output-set-default", String(node.index), String(node.name)])
  }

  function setDefaultSource(node) {
    if (!node) return
    Audio.preferredDefaultAudioSource = node
    if (node.index !== undefined && node.name)
      Quickshell.execDetached(["omarchy-audio-input-set-default", String(node.index), String(node.name)])
  }

  function showVolumeOsd(volume) {
    if (!bar || !bar.shell) return
    bar.shell.summon("omarchy.osd", JSON.stringify({ icon: outputIcon(volume), value: Math.round(volume * 100) }))
  }

  Column {
    id: column
    width: parent.width
    spacing: Style.space(14)

    // ---------- Hero ----------
    Item {
      width: parent.width
      implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, powerSwitch.implicitHeight)

      Text {
        id: heroIcon
        textFormat: Text.PlainText
        text: root.outputIcon()
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.display
        opacity: root.outputMuted ? 0.5 : 1.0
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      ToggleSwitch {
        id: powerSwitch
        checked: root.anyAudible
        foreground: root.bar.foreground
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        onToggled: root.toggleAllMuted()
      }

      Column {
        id: heroLabels
        anchors.left: heroIcon.right
        anchors.leftMargin: Style.space(14)
        anchors.right: parent.right
        anchors.rightMargin: powerSwitch.width + Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Text {
          text: "Audio"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
          elide: Text.ElideRight
          width: parent.width
        }

        Text {
          textFormat: Text.PlainText
          text: Model.outputVolumeName(root.outputVolume, root.outputMuted).toUpperCase()
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

    // ---------- Output ----------
    Column {
      width: parent.width
      spacing: Style.space(6)

      Item {
        width: parent.width
        implicitHeight: Math.max(outputHeader.implicitHeight, outputPercent.implicitHeight)

        PanelSectionHeader {
          id: outputHeader
          text: "OUTPUT"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          id: outputPercent
          textFormat: Text.PlainText
          text: Math.round(root.outputVolume * 100) + "%"
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          opacity: root.outputMuted ? 0.5 : 1.0
        }
      }

      CursorSurface {
        width: parent.width
        height: outputSlider.implicitHeight + Style.spacing.controlGap
        hasCursor: outputHover.hovered
        foreground: root.bar.foreground
        outline: true

        PanelSlider {
          id: outputSlider
          bar: root.bar
          anchors.fill: parent
          anchors.leftMargin: Style.space(6)
          anchors.rightMargin: Style.space(6)
          minimum: 0
          maximum: 1
          step: 0.05
          value: root.outputVolume
          opacity: root.outputMuted ? 0.5 : 1.0
          enabled: !!root.sink
          onMoved: function(v) { root.setOutputVolume(v) }
          onReleased: function(v) { root.showVolumeOsd(v) }
          onRightClicked: root.toggleOutputMute()
        }

        HoverHandler { id: outputHover }
      }

      Repeater {
        model: root.candidateSinks

        SinkRow {
          required property var modelData
          width: column.width
          node: modelData
          bar: root.bar
          isActive: root.sink && modelData.index === root.sink.index
          onPicked: root.setDefaultSink(modelData)
        }
      }
    }

    // ---------- Input ----------
    PanelSeparator {
      visible: root.candidateSources.length > 0 || !!root.source
      foreground: root.bar.foreground
    }

    Column {
      width: parent.width
      spacing: Style.space(6)
      visible: root.candidateSources.length > 0 || !!root.source

      Item {
        width: parent.width
        implicitHeight: Math.max(inputHeader.implicitHeight, inputPercent.implicitHeight)

        PanelSectionHeader {
          id: inputHeader
          text: "INPUT"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          id: inputPercent
          textFormat: Text.PlainText
          text: Math.round(root.inputVolume * 100) + "%"
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          opacity: root.inputMuted ? 0.5 : 1.0
        }
      }

      CursorSurface {
        visible: !!root.source
        width: parent.width
        height: inputSlider.implicitHeight + Style.spacing.controlGap
        hasCursor: inputHover.hovered
        foreground: root.bar.foreground
        outline: true

        PanelSlider {
          id: inputSlider
          bar: root.bar
          anchors.fill: parent
          anchors.leftMargin: Style.space(6)
          anchors.rightMargin: Style.space(6)
          minimum: 0
          maximum: 1
          step: 0.05
          value: root.inputVolume
          opacity: root.inputMuted ? 0.5 : 1.0
          enabled: !!root.source
          onMoved: function(v) { root.setInputVolume(v) }
          onRightClicked: root.toggleInputMute()
        }

        HoverHandler { id: inputHover }
      }

      Repeater {
        model: root.candidateSources

        SourceRow {
          required property var modelData
          width: column.width
          node: modelData
          bar: root.bar
          isActive: root.source && modelData.index === root.source.index
          onPicked: root.setDefaultSource(modelData)
        }
      }
    }

    // ---------- Per-app streams ----------
    PanelSeparator {
      visible: root.audioStreams.length > 0
      foreground: root.bar.foreground
    }

    Column {
      width: parent.width
      spacing: Style.space(10)
      visible: root.audioStreams.length > 0

      PanelSectionHeader {
        text: "SOURCES"
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
      }

      Repeater {
        model: root.audioStreams

        StreamRow {
          required property var modelData
          width: column.width
          node: modelData
          bar: root.bar
        }
      }
    }

    PanelSeparator { foreground: root.bar.foreground }

    Button {
      text: "Volume control"
      bordered: true
      foreground: root.bar.foreground
      fontFamily: root.bar.fontFamily
      onClicked: Quickshell.execDetached(["pavucontrol"])
    }
  }

  component SinkRow: CursorSurface {
    id: sinkRow
    required property var node
    property bool isActive: false
    property QtObject bar: null
    signal picked()

    hasCursor: mouseArea.containsMouse
    current: isActive
    foreground: bar ? bar.foreground : Color.foreground
    implicitHeight: sinkInner.implicitHeight + Style.spacing.xl

    Row {
      id: sinkInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: Model.sinkGlyph(sinkRow.node)
        color: sinkRow.bar ? sinkRow.bar.foreground : Color.foreground
        font.family: sinkRow.bar ? sinkRow.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.title
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        textFormat: Text.PlainText
        text: Model.nodeLabel(sinkRow.node)
        color: sinkRow.bar ? sinkRow.bar.foreground : Color.foreground
        font.family: sinkRow.bar ? sinkRow.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        font.bold: sinkRow.isActive
        elide: Text.ElideRight
        width: parent.width - Style.space(22) - Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    MouseArea {
      id: mouseArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: sinkRow.picked()
    }
  }

  component SourceRow: CursorSurface {
    id: sourceRow
    required property var node
    property bool isActive: false
    property QtObject bar: null
    signal picked()

    hasCursor: mouseArea.containsMouse
    current: isActive
    foreground: bar ? bar.foreground : Color.foreground
    implicitHeight: sourceInner.implicitHeight + Style.spacing.xl

    Row {
      id: sourceInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: Model.sourceGlyph(sourceRow.node)
        color: sourceRow.bar ? sourceRow.bar.foreground : Color.foreground
        font.family: sourceRow.bar ? sourceRow.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.title
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        textFormat: Text.PlainText
        text: Model.nodeLabel(sourceRow.node)
        color: sourceRow.bar ? sourceRow.bar.foreground : Color.foreground
        font.family: sourceRow.bar ? sourceRow.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        font.bold: sourceRow.isActive
        elide: Text.ElideRight
        width: parent.width - Style.space(22) - Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    MouseArea {
      id: mouseArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: sourceRow.picked()
    }
  }

  component StreamRow: CursorSurface {
    id: streamRow
    required property var node
    property QtObject bar: null
    readonly property real streamVolume: node && node.audio ? node.audio.volume : 0
    readonly property bool streamMuted: node && node.audio ? node.audio.muted : false

    hasCursor: mouseArea.containsMouse
    foreground: bar ? bar.foreground : Color.foreground
    implicitHeight: streamColumn.implicitHeight + Style.spacing.xl

    Column {
      id: streamColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(2)

      Row {
        width: parent.width
        spacing: Style.space(8)

        Text {
          id: streamMuteIcon
          textFormat: Text.PlainText
          text: streamRow.streamMuted ? "󰝟" : "󰕾"
          color: streamRow.bar ? streamRow.bar.foreground : Color.foreground
          font.family: streamRow.bar ? streamRow.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.title
          width: Style.space(22)
          horizontalAlignment: Text.AlignHCenter
          anchors.verticalCenter: parent.verticalCenter
          opacity: streamRow.streamMuted ? 0.5 : 1.0

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: if (streamRow.node && streamRow.node.audio) streamRow.node.audio.muted = !streamRow.node.audio.muted
          }
        }

        Text {
          textFormat: Text.PlainText
          text: Model.rawStreamLabel(streamRow.node)
          color: streamRow.bar ? streamRow.bar.foreground : Color.foreground
          font.family: streamRow.bar ? streamRow.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          width: parent.width - streamMuteIcon.width - streamPct.width - Style.space(16)
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          id: streamPct
          textFormat: Text.PlainText
          text: Math.round(streamRow.streamVolume * 100) + "%"
          color: streamRow.bar ? Qt.darker(streamRow.bar.foreground, 1.5) : Color.foreground
          font.family: streamRow.bar ? streamRow.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
          width: Style.space(36)
          horizontalAlignment: Text.AlignRight
          anchors.verticalCenter: parent.verticalCenter
          opacity: streamRow.streamMuted ? 0.5 : 1.0
        }
      }

      PanelSlider {
        bar: streamRow.bar
        width: parent.width
        minimum: 0
        maximum: 1.5
        step: 0.05
        value: streamRow.streamVolume
        opacity: streamRow.streamMuted ? 0.5 : 1.0
        onMoved: function(v) { if (streamRow.node && streamRow.node.audio) streamRow.node.audio.volume = v }
        onRightClicked: if (streamRow.node && streamRow.node.audio) streamRow.node.audio.muted = !streamRow.node.audio.muted
      }
    }

    MouseArea {
      id: mouseArea
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      propagateComposedEvents: true
    }
  }
}

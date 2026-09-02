import QtQuick
import Quickshell
import qs.Ui
import qs.Services

// X11 delta (Phase 5): upstream reads `Quickshell.Services.Pipewire`
// (`Pipewire.defaultAudioSource`, `PwObjectTracker`, capture streams via
// `Pipewire.nodes`). That module is a stub here — everything comes from
// `Services/Audio.qml`'s pactl graph instead, including `_captures`
// (source-outputs), which is what lets `inUse` light when the mic is hot.
BarWidget {
  id: root
  moduleName: "omarchy.microphone"

  readonly property var source: Audio.defaultAudioSource
  readonly property bool muted: source && source.audio ? source.audio.muted : true
  readonly property real volume: source && source.audio ? source.audio.volume : 0
  readonly property var nodes: Audio.nodes ? Audio.nodes.values : []

  readonly property var activeStreams: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i]
      if (node && node.isStream && node.isSink === false && !(node.audio && node.audio.muted))
        list.push(node)
    }
    return list
  }

  readonly property bool inUse: activeStreams.length > 0 && !muted

  visible: source !== null
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function toggleMute() {
    if (source && source.audio) source.audio.muted = !source.audio.muted
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.muted ? "󰍭" : "󰍬"
    active: root.inUse
    tooltipText: root.muted ? "Microphone muted" : (root.inUse ? "Microphone in use" : "Microphone live")
    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.bar.run("omarchy-shell shell toggle omarchy.audio")
      else root.toggleMute()
    }
    onWheelMoved: function(delta) {
      if (!root.source || !root.source.audio) return
      var step = 0.05
      root.source.audio.volume = Math.max(0, Math.min(1, root.volume + (delta > 0 ? step : -step)))
    }
  }
}

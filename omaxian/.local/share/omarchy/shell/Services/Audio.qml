pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Audio state via `pactl`, NOT `Quickshell.Services.Pipewire` — this machine
// runs a real PulseAudio server and the local Quickshell build ships the
// Pipewire (and Mpris) QML modules as type-only stubs with no plugin `.so`,
// confirmed directly. `pactl` is the right layer regardless: a PipeWire box
// reaches the same API through `pipewire-pulse`, so this service follows
// whatever sound server is actually running with no code change.
//
// Two API surfaces on one singleton:
//   * minimal  — `volume`/`muted` + `setVolume`/`adjust`/`toggleMute`, the
//     master-output controls the `local.volume` bar widget uses. Backed by
//     scripts/volume.sh + volume-listen.sh (kept from the eww port).
//   * graph    — `nodes`/`defaultAudioSink`/`defaultAudioSource` +
//     `preferredDefaultAudioSink/Source`, a Pipewire-`nodes`-shaped view for
//     the `omarchy.audio` panel. Backed by `pactl -f json list` snapshots
//     refreshed off a `pactl subscribe` event stream. Node objects are
//     reused across refreshes so Repeaters don't churn; each carries a
//     writable `audio.volume`/`audio.muted` that pushes back through pactl.
QtObject {
  id: root

  // ---------------------------------------------------------------- minimal

  readonly property string scriptDir: Quickshell.shellDir + "/scripts"

  property int volume: 0
  property bool muted: false

  function setVolume(pct) {
    Quickshell.execDetached(["bash", scriptDir + "/volume.sh", "set", String(Math.round(pct))])
  }

  function adjust(deltaPct) {
    Quickshell.execDetached(["bash", scriptDir + "/volume.sh", deltaPct > 0 ? "up" : "down"])
  }

  function toggleMute() {
    Quickshell.execDetached(["bash", scriptDir + "/volume.sh", "mute-toggle"])
  }

  property Process listener: Process {
    id: listener
    command: ["bash", root.scriptDir + "/volume-listen.sh"]
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        var trimmed = String(line || "").trim()
        if (trimmed.length === 0) return
        try {
          var parsed = JSON.parse(trimmed)
          root.volume = Math.round(Number(parsed.volume) || 0)
          root.muted = !!parsed.muted
        } catch (e) {
          // malformed line from a mid-write pactl subscribe event; next
          // line resyncs, nothing to recover here.
        }
      }
    }
  }

  // ------------------------------------------------------------------ graph

  property var _sinks: []
  property var _sources: []
  property var _streams: []    // sink-inputs  (playback per-app streams)
  property var _captures: []   // source-outputs (capture streams — mic in use)
  // Shape-compatible with Pipewire.nodes (`.values` is the flat list).
  readonly property var nodes: ({ values: root._sinks.concat(root._sources).concat(root._streams).concat(root._captures) })

  property string _defaultSinkName: ""
  property string _defaultSourceName: ""
  readonly property var defaultAudioSink: root._findByName(root._sinks, root._defaultSinkName)
  readonly property var defaultAudioSource: root._findByName(root._sources, root._defaultSourceName)

  // Assigning a node here switches the default (mirrors
  // Pipewire.preferredDefaultAudioSink). The panel also fires
  // omarchy-audio-output-set-default itself (it moves live streams too), so
  // this is the lightweight path for any other caller.
  property var preferredDefaultAudioSink: null
  property var preferredDefaultAudioSource: null
  onPreferredDefaultAudioSinkChanged: {
    if (preferredDefaultAudioSink && preferredDefaultAudioSink.name)
      Quickshell.execDetached(["pactl", "set-default-sink", String(preferredDefaultAudioSink.name)])
  }
  onPreferredDefaultAudioSourceChanged: {
    if (preferredDefaultAudioSource && preferredDefaultAudioSource.name)
      Quickshell.execDetached(["pactl", "set-default-source", String(preferredDefaultAudioSource.name)])
  }

  function _findByName(list, name) {
    if (!name) return null
    for (var i = 0; i < list.length; i++)
      if (list[i] && String(list[i].name) === String(name)) return list[i]
    return null
  }

  // kind:index -> node object, so identity survives refreshes.
  property var _index: ({})

  property Component _nodeComponent: Component {
    QtObject {
      id: nd
      property int index: -1
      property string kind: "sink"          // "sink" | "source" | "stream" | "capture"
      property string name: ""
      property string description: ""
      property string nickname: ""
      property string type: ""              // media.class
      property var properties: ({})
      readonly property bool ready: true
      readonly property bool isSink: kind === "sink" || kind === "stream"
      readonly property bool isStream: kind === "stream" || kind === "capture"
      // Non-null for every node here (all three kinds are audio), matching
      // how the panel treats a truthy `.audio` as "this is an audio node".
      property bool _applying: false
      property QtObject audio: QtObject {
        property real volume: 0
        property bool muted: false
        onVolumeChanged: if (!nd._applying) nd._pushVolume(volume)
        onMutedChanged: if (!nd._applying) nd._pushMuted(muted)
      }

      function _target() {
        return kind === "stream"  ? ["sink-input", String(index)]
             : kind === "capture" ? ["source-output", String(index)]
             : kind === "source"  ? ["source", String(index)]
             : ["sink", String(index)]
      }
      function _pushVolume(v) {
        var t = _target()
        var pct = Math.max(0, Math.round(v * 100))
        Quickshell.execDetached(["pactl", "set-" + t[0] + "-volume", t[1], pct + "%"])
      }
      function _pushMuted(m) {
        var t = _target()
        Quickshell.execDetached(["pactl", "set-" + t[0] + "-mute", t[1], m ? "1" : "0"])
      }
      // Called by the service with fresh pactl data; guarded so the writes
      // above don't fire back at pactl.
      function _apply(data) {
        _applying = true
        name = data.name; description = data.description; nickname = data.nickname
        type = data.type; properties = data.properties; index = data.index
        if (Math.abs(audio.volume - data.volume) > 0.001) audio.volume = data.volume
        if (audio.muted !== data.muted) audio.muted = data.muted
        _applying = false
      }
    }
  }

  function _chanAvg(volObj) {
    if (!volObj) return 0
    var keys = Object.keys(volObj), sum = 0, n = 0
    for (var i = 0; i < keys.length; i++) {
      var raw = volObj[keys[i]]
      var v = raw && raw.value !== undefined ? Number(raw.value) : NaN
      if (!isNaN(v)) { sum += v; n++ }
    }
    if (n === 0) return 0
    return (sum / n) / 65536   // PA_VOLUME_NORM
  }

  function _mkData(entry, kind) {
    var p = entry.properties || {}
    var name = (kind === "stream" || kind === "capture")
      ? (p["application.name"] || p["media.name"] || entry.name || (kind + " " + entry.index))
      : (entry.name || "")
    return {
      index: Number(entry.index),
      kind: kind,
      name: String(name),
      description: String(entry.description || p["node.description"] || ""),
      nickname: String(p["node.nick"] || ""),
      type: String(p["media.class"] || ""),
      properties: p,
      volume: root._chanAvg(entry.volume),
      muted: !!entry.mute
    }
  }

  function _syncKind(entries, kind, outList) {
    var seen = {}
    var list = []
    for (var i = 0; i < entries.length; i++) {
      var data = root._mkData(entries[i], kind)
      // Playback streams only for the "stream" kind (skip capture / monitors /
      // the shell's own probe).
      if (kind === "stream") {
        var mc = data.type
        if (mc && mc.indexOf("Output") === -1 && mc.indexOf("Sink") === -1) continue
      }
      if ((kind === "source" || kind === "capture") && data.name === "quickshell") continue
      var key = kind + ":" + data.index
      seen[key] = true
      var node = root._index[key]
      if (!node) {
        node = root._nodeComponent.createObject(root, { index: data.index, kind: kind })
        root._index[key] = node
      }
      node._apply(data)
      list.push(node)
    }
    // Drop nodes that vanished.
    var keys = Object.keys(root._index)
    for (var k = 0; k < keys.length; k++) {
      if (keys[k].indexOf(kind + ":") === 0 && !seen[keys[k]]) {
        var gone = root._index[keys[k]]
        delete root._index[keys[k]]
        if (gone && gone.destroy) gone.destroy()
      }
    }
    return list
  }

  function _ingest(jsonText) {
    var data
    try { data = JSON.parse(String(jsonText || "{}")) } catch (e) { return }
    root._sinks = root._syncKind(data.sinks || [], "sink", root._sinks)
    root._sources = root._syncKind(data.sources || [], "source", root._sources)
    root._streams = root._syncKind(data.sink_inputs || [], "stream", root._streams)
    root._captures = root._syncKind(data.source_outputs || [], "capture", root._captures)
  }

  function refresh() {
    if (!_graphProc.running) _graphProc.running = true
    _defaultProc.running = true
  }

  property Process _graphProc: Process {
    id: _graphProc
    command: ["pactl", "-f", "json", "list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._ingest(text)
    }
  }

  property Process _defaultProc: Process {
    id: _defaultProc
    command: ["bash", "-lc", "printf '%s\\n%s\\n' \"$(pactl get-default-sink)\" \"$(pactl get-default-source)\""]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        root._defaultSinkName = (lines[0] || "").trim()
        root._defaultSourceName = (lines[1] || "").trim()
      }
    }
  }

  // Coalesce bursts of subscribe events into one refresh.
  property Timer _debounce: Timer {
    interval: 120
    onTriggered: root.refresh()
  }

  property Process _subscribe: Process {
    command: ["pactl", "subscribe"]
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        var s = String(line || "")
        if (s.indexOf("sink") !== -1 || s.indexOf("source") !== -1
            || s.indexOf("server") !== -1 || s.indexOf("card") !== -1)
          root._debounce.restart()
      }
    }
  }

  Component.onCompleted: refresh()
}

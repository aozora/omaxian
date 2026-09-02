.pragma library

// Control Panel — pure-JS helpers per tab. Fresh implementations, not
// imports from the original widgets (plugins/panels/audio/, .../bluetooth/,
// .../monitor/) — see Panel.qml's header comment for why.

// ---------------------------------------------------------------- Audio tab

function friendlyDeviceLabel(text) {
  var label = String(text || "").trim()
  label = label.replace(/^sof-soundwire\s+/i, "")
  label = label.replace(/^built-?in audio\s+/i, "")
  label = label.replace(/\s+Output$/i, "")
  label = label.replace(/\s+Input$/i, "")
  label = label.replace(/\bMicrophones\b/g, "Microphone")
  return label
}

function nodeProps(node) {
  return node && node.ready && node.properties ? node.properties : {}
}

function nodeLabel(node) {
  if (!node) return "Unknown"
  var p = nodeProps(node)
  var nickname = friendlyDeviceLabel(node.nickname || node.nick || p["node.nick"] || p["device.profile.description"] || "")
  if (nickname) return nickname
  return friendlyDeviceLabel(node.description || p["node.description"] || node.name || "Unknown")
}

function isHeadphones(node) {
  if (!node) return false
  var p = nodeProps(node)
  var blob = String([
    node.name, node.description, node.nickname,
    p["device.icon-name"] || "",
    p["device.product.name"] || "",
    p["node.description"] || "",
    p["node.nick"] || ""
  ].join(" ")).toLowerCase()
  return blob.indexOf("headphone") !== -1
    || blob.indexOf("headset") !== -1
    || blob.indexOf("earbud") !== -1
    || blob.indexOf("earphone") !== -1
    || blob.indexOf("airpod") !== -1
}

function sinkGlyph(node) {
  if (!node) return "󰓃"
  if (isHeadphones(node)) return "󰋋"
  var p = nodeProps(node)
  var blob = String([
    node.name, node.description, node.nickname,
    p["device.icon-name"] || "",
    p["device.product.name"] || ""
  ].join(" ")).toLowerCase()
  if (blob.indexOf("bluetooth") !== -1) return "󰂯"
  if (blob.indexOf("hdmi") !== -1 || blob.indexOf("display") !== -1) return "󰍹"
  return "󰓃"
}

function sourceGlyph(node) {
  if (!node) return "󰍬"
  var p = nodeProps(node)
  var blob = String([
    node.name, node.description, node.nickname,
    p["device.icon-name"] || ""
  ].join(" ")).toLowerCase()
  if (blob.indexOf("headset") !== -1) return "󰋋"
  if (blob.indexOf("bluetooth") !== -1) return "󰂯"
  if (blob.indexOf("webcam") !== -1 || blob.indexOf("camera") !== -1) return "󰄀"
  return "󰍬"
}

function outputVolumeName(volume, muted) {
  if (muted) return "Muted"
  var p = Math.round(volume * 100)
  if (p === 0) return "Silenced"
  if (p >= 100) return "Concert hall"
  if (p >= 85) return "Party mode"
  if (p >= 70) return "Cranked up"
  if (p >= 50) return "Steady groove"
  if (p >= 30) return "Easy listening"
  if (p >= 15) return "Murmur"
  return "Whisper"
}

function isPlaybackStream(node) {
  if (!node || !node.isStream) return false
  if (node.isSink === true) return true
  var mediaClass = String(node.type || "")
  return mediaClass.indexOf("Stream/Output/Audio") !== -1
    || mediaClass.indexOf("AudioOutStream") !== -1
    || mediaClass.indexOf("Output") !== -1
}

function isAudioSource(node) {
  if (!node) return false
  if (node.audio) return true
  var mediaClass = String(node.type || "")
  return mediaClass.indexOf("Audio/Source") !== -1
    || mediaClass.indexOf("AudioSource") !== -1
    || mediaClass.indexOf("Source") !== -1
}

function rawStreamLabel(node) {
  if (!node) return "Stream"
  var p = nodeProps(node)
  return p["application.name"] || node.description || p["media.name"] || p["node.name"] || node.name || "Stream"
}

// ------------------------------------------------------------ Bluetooth tab

function deviceLabel(device) {
  if (!device) return ""
  return String(device.deviceName || device.name || "").trim()
}

function toArray(values) {
  if (!values) return []
  if (Array.isArray(values)) return values.slice()
  var length = Number(values.length || 0)
  if (!isFinite(length) || length <= 0) return []
  var list = []
  for (var i = 0; i < length; i++) list.push(values[i])
  return list
}

function isUuidLike(value) {
  var text = String(value || "").trim()
  if (text === "") return false
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(text)
    || /^[0-9a-f]{32}$/i.test(text)
    || /^0x[0-9a-f]{4,32}$/i.test(text)
    || /^0000[0-9a-f]{4}-0000-1000-8000-00805f9b34fb$/i.test(text)
}

function isAddressLike(value) {
  var text = String(value || "").trim()
  return /^([0-9a-f]{2}[:-]){5}[0-9a-f]{2}$/i.test(text)
}

function hasHumanName(device) {
  var label = deviceLabel(device)
  return label !== "" && !isUuidLike(label) && !isAddressLike(label)
}

function sortedByLabel(devices) {
  var list = toArray(devices)
  list.sort(function(a, b) { return deviceLabel(a).localeCompare(deviceLabel(b)) })
  return list
}

function deviceLists(devices) {
  var values = toArray(devices)
  var connected = []
  var known = []
  var discovered = []
  for (var i = 0; i < values.length; i++) {
    var d = values[i]
    if (!d || !hasHumanName(d)) continue
    if (d.connected) connected.push(d)
    else if (d.paired || d.bonded || d.trusted) known.push(d)
    else discovered.push(d)
  }
  return {
    connected: sortedByLabel(connected),
    known: sortedByLabel(known),
    discovered: sortedByLabel(discovered)
  }
}

function cloneMap(map) {
  var next = ({})
  for (var key in map || {}) next[key] = map[key]
  return next
}

function pendingAction(actions, address) {
  return address && actions && actions[address] ? actions[address] : ""
}

function withPendingAction(actions, address, action) {
  var next = cloneMap(actions)
  if (!address) return next
  if (action) next[address] = action
  else delete next[address]
  return next
}

// --------------------------------------------------------------- Monitor tab

function monitorToArray(value) {
  if (!value || typeof value.length !== "number") return []
  var out = []
  for (var i = 0; i < value.length; i++) out.push(value[i])
  return out
}

function laptopOutput(outputs) {
  var list = monitorToArray(outputs)
  for (var i = 0; i < list.length; i++) {
    if (list[i] && list[i].isLaptopPanel) return list[i]
  }
  return null
}

function enabledOutputs(outputs) {
  return monitorToArray(outputs).filter(function(o) { return !!(o && o.connected && o.enabled) })
}

function modeDims(mode) {
  var parts = String(mode || "").split("x")
  return { w: parseInt(parts[0], 10) || 0, h: parseInt(parts[1], 10) || 0 }
}

// Largest resolution first — the pill row reads left-to-right as best-to-worst.
function sortModes(modes) {
  var list = monitorToArray(modes)
  list.sort(function(a, b) {
    var da = modeDims(a), db = modeDims(b)
    return (db.w * db.h) - (da.w * da.h)
  })
  return list
}

function monitorIconFor(outputs) {
  var enabled = enabledOutputs(outputs)
  if (enabled.length === 0) return "󰍹"
  if (enabled.length >= 2) return "󰍺"
  var laptop = laptopOutput(outputs)
  if (laptop && laptop.enabled) return "󰌢"
  return "󰍹"
}

function monitorStatusLine(outputs, lidPresent, lidClosed) {
  var enabled = enabledOutputs(outputs)
  var laptop = laptopOutput(outputs)
  var laptopOn = !!(laptop && laptop.enabled)
  var externalCount = enabled.length - (laptopOn ? 1 : 0)
  var lidPrefix = (lidPresent && lidClosed) ? "Lid closed · " : ""

  if (enabled.length === 0) return lidPrefix + "No displays"
  if (laptopOn && externalCount === 0) return lidPrefix + "Laptop only"
  if (!laptopOn && externalCount > 0 && laptop) return lidPrefix + (externalCount === 1 ? "External" : externalCount + " displays")
  if (laptopOn && externalCount > 0) return lidPrefix + enabled.length + " displays · docked"
  return lidPrefix + enabled.length + " displays"
}

// -------------------------------------------------------------- Wallpaper tab

// Settings persisted to ~/.config/omarchy/wallpaper-settings.json — one key,
// `localFolder`, the directory the "From local folder" sub-tab scans. Same
// logic as plugins/bar/widgets/WallpaperModel.js; duplicated because the
// standalone Wallpapers widget is a separate plugin with no import path here.

function parseWallpaperSettings(raw) {
  var text = String(raw === undefined || raw === null ? "" : raw).trim()
  var parsed = null
  if (text) {
    try { parsed = JSON.parse(text) } catch (e) { parsed = null }
  }
  var source = (parsed && typeof parsed === "object") ? parsed : {}
  return {
    localFolder: (typeof source.localFolder === "string") ? source.localFolder.trim() : ""
  }
}

function serializeWallpaperSettings(settings) {
  var s = (settings && typeof settings === "object") ? settings : {}
  return JSON.stringify({
    localFolder: (typeof s.localFolder === "string") ? s.localFolder.trim() : ""
  }, null, 2)
}

// Arrays that cross a QML `property var` / Repeater `modelData` boundary
// arrive as QML-marshalled list objects: they index and iterate like arrays
// (and JSON.stringify happily walks them) but fail `Array.isArray()`, since
// they're not native JS Array instances. Coerce by duck-typing on `.length`
// instead, so every helper below works the same whether it's called with a
// freshly-parsed JSON array or one that's been round-tripped through a QML
// property.
function toArray(value) {
  if (!value || typeof value.length !== "number") return []
  var out = []
  for (var i = 0; i < value.length; i++) out.push(value[i])
  return out
}

function laptopOutput(outputs) {
  var list = toArray(outputs)
  for (var i = 0; i < list.length; i++) {
    if (list[i] && list[i].isLaptopPanel) return list[i]
  }
  return null
}

function enabledOutputs(outputs) {
  return toArray(outputs).filter(function(o) { return !!(o && o.connected && o.enabled) })
}

// Mirrors omarchy-monitor-apply's signature computation: sorted, "+"-joined
// connected output names, with the laptop panel dropped whenever the lid is
// closed and at least one other connected output remains.
function signatureFor(outputs, lidClosed) {
  var connected = toArray(outputs).filter(function(o) { return !!(o && o.connected) })
  var laptop = laptopOutput(connected)
  var names = connected.map(function(o) { return o.name })
  if (lidClosed && laptop && names.length > 1) {
    names = names.filter(function(n) { return n !== laptop.name })
  }
  names.sort()
  return names.join("+")
}

function modeDims(mode) {
  var parts = String(mode || "").split("x")
  return { w: parseInt(parts[0], 10) || 0, h: parseInt(parts[1], 10) || 0 }
}

// Largest resolution first — the pill row reads left-to-right as best-to-worst.
function sortModes(modes) {
  var list = toArray(modes)
  list.sort(function(a, b) {
    var da = modeDims(a), db = modeDims(b)
    return (db.w * db.h) - (da.w * da.h)
  })
  return list
}

function iconFor(outputs) {
  var enabled = enabledOutputs(outputs)
  if (enabled.length === 0) return "󰍹"
  if (enabled.length >= 2) return "󰍺"
  var laptop = laptopOutput(outputs)
  if (laptop && laptop.enabled) return "󰌢"
  return "󰍹"
}

function statusLine(outputs, lidPresent, lidClosed) {
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

if (typeof module !== "undefined") {
  module.exports = {
    toArray: toArray,
    laptopOutput: laptopOutput,
    enabledOutputs: enabledOutputs,
    signatureFor: signatureFor,
    modeDims: modeDims,
    sortModes: sortModes,
    iconFor: iconFor,
    statusLine: statusLine
  }
}

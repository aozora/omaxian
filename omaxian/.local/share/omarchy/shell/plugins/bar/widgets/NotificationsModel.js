.pragma library

// Pure helpers for the notification history: reading dunst's state, turning
// sender markup into plain text, and ordering the list.

var ENTITIES = { amp: "&", lt: "<", gt: ">", quot: "\"", apos: "'", nbsp: " " }

function decodeEntities(text) {
  return String(text || "").replace(/&(#x[0-9a-f]{1,6}|#\d{1,7}|[a-z]+);/gi, function(whole, name) {
    if (name.charAt(0) !== "#") {
      var named = ENTITIES[name.toLowerCase()]
      return named === undefined ? whole : named
    }
    var hex = name.charAt(1).toLowerCase() === "x"
    var code = parseInt(name.slice(hex ? 2 : 1), hex ? 16 : 10)
    return (code > 0 && code < 0x110000) ? String.fromCodePoint(code) : whole
  })
}

// Bodies carry the notification spec's markup. The panel draws plain text only,
// so drop the known tags (anything else, like "<3", is the sender's text) and
// then decode, so an escaped tag stays visible as typed.
function plainText(markup) {
  var text = String(markup || "")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<img\b[^>]*?\balt=(?:"([^"]*)"|'([^']*)')[^>]*>/gi, function(_, a, b) { return a || b || "" })
    .replace(/<\/?(?:a|b|i|u|s|em|strong|img|span|tt|big|small|sub|sup)\b[^<>]*>/gi, "")
  return decodeEntities(text).replace(/\r/g, "").replace(/\n{3,}/g, "\n\n").trim()
}

// An id alone repeats after dunst restarts; with the arrival time it doesn't.
function keyFor(entry) {
  return entry.id + ":" + entry.ts
}

// Returns null for anything that isn't the state script's output. `wallTimes`
// remembers when each entry arrived, from the first time it was seen: dunst's
// clock stops during suspend, so converting it later would understate the age.
function parseState(raw, nowMs, wallTimes) {
  var data
  try { data = JSON.parse(raw) } catch (e) { return null }
  if (!data || !Array.isArray(data.entries)) return null

  var times = {}
  var entries = data.entries.map(function(item) {
    var key = keyFor(item)
    var known = wallTimes ? wallTimes[key] : undefined
    var arrived = known !== undefined ? known : nowMs - Math.max(0, data.now - item.ts) / 1000
    times[key] = arrived
    return {
      key: key,
      id: item.id,
      app: String(item.app || "").trim(),
      summary: plainText(item.summary).replace(/\s+/g, " "),
      body: plainText(item.body),
      critical: item.urgency === "CRITICAL",
      low: item.urgency === "LOW",
      icon: String(item.icon || ""),
      arrived: arrived
    }
  })
  entries.sort(function(a, b) { return b.arrived - a.arrived })

  return { paused: data.paused === true, waiting: data.waiting || 0, entries: entries, wallTimes: times }
}

// Newest app first, each app's notifications together. `heading` is set on the
// first row of a group.
function grouped(entries) {
  var order = []
  var groups = {}
  for (var i = 0; i < entries.length; i++) {
    var name = "app:" + entries[i].app
    if (!groups[name]) {
      groups[name] = []
      order.push(name)
    }
    groups[name].push(entries[i])
  }

  var rows = []
  for (var g = 0; g < order.length; g++) {
    var members = groups[order[g]]
    for (var m = 0; m < members.length; m++) {
      var row = {}
      for (var field in members[m]) row[field] = members[m][field]
      row.heading = m === 0 ? (members[m].app || "Other") : ""
      row.groupSize = members.length
      rows.push(row)
    }
  }
  return rows
}

function unseenKeys(entries, seen) {
  var keys = {}
  for (var i = 0; i < entries.length; i++)
    if (!seen[entries[i].key]) keys[entries[i].key] = true
  return keys
}

function allKeys(entries) {
  var keys = {}
  for (var i = 0; i < entries.length; i++) keys[entries[i].key] = true
  return keys
}

function ageLabel(arrived, nowMs) {
  var minutes = Math.floor(Math.max(0, nowMs - arrived) / 60000)
  if (minutes < 1) return "now"
  if (minutes < 60) return minutes + "m"
  if (minutes < 60 * 24) return Math.floor(minutes / 60) + "h"
  return Math.floor(minutes / (60 * 24)) + "d"
}

// Only a local file is ever loaded: the path is the sender's to choose.
function iconUrl(path) {
  if (String(path || "").charAt(0) !== "/") return ""
  return "file://" + encodeURI(path).replace(/#/g, "%23").replace(/\?/g, "%3F")
}

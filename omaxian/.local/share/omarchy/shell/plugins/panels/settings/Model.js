.pragma library

// Pure helpers for omaxian.settings — JSON/TOML persistence, bar/plugin
// catalogues, and startup-app lists. No Qt; keep this unit-testable.
//
// Arrays that cross a QML `property var` into this pragma-library engine
// index and iterate like arrays but fail `Array.isArray()` (they are not
// native JS Array instances). Duck-type on `.length` so layout / kinds /
// schema still work after that hop.

var SECTIONS = ["left", "center", "right"]

function isArrayLike(value) {
  return !!value && typeof value === "object" && typeof value.length === "number"
}

function isPlainObject(value) {
  return !!value && typeof value === "object" && !isArrayLike(value)
}

function arrayFrom(v) {
  if (typeof v === "string" || !isArrayLike(v)) return []
  var out = []
  for (var i = 0; i < v.length; i++) out.push(v[i])
  return out
}

function canonicalId(id) {
  return String(id || "").trim()
}

function barEntryId(entry) {
  if (typeof entry === "string") return canonicalId(entry)
  if (entry && typeof entry === "object") return canonicalId(entry.id)
  return ""
}

function entrySettings(entry) {
  if (!isPlainObject(entry)) return {}
  var copy = {}
  for (var key in entry) {
    if (key === "id") continue
    copy[key] = entry[key]
  }
  return copy
}

function layoutSection(config, section) {
  if (!config || !config.bar || !config.bar.layout) return []
  return arrayFrom(config.bar.layout[section])
}

function findBarEntry(config, id) {
  var key = canonicalId(id)
  for (var s = 0; s < SECTIONS.length; s++) {
    var entries = layoutSection(config, SECTIONS[s])
    for (var i = 0; i < entries.length; i++) {
      if (barEntryId(entries[i]) === key)
        return { found: true, section: SECTIONS[s], index: i, entry: entries[i] }
    }
  }
  return { found: false }
}

function barWidgetsOnBar(config) {
  var out = []
  for (var s = 0; s < SECTIONS.length; s++) {
    var entries = layoutSection(config, SECTIONS[s])
    for (var i = 0; i < entries.length; i++) {
      var id = barEntryId(entries[i])
      if (id) out.push({ id: id, section: SECTIONS[s], index: i, entry: entries[i] })
    }
  }
  return out
}

function kindsOf(manifest) {
  return arrayFrom(manifest && manifest.kinds)
}

function isBarWidgetManifest(manifest) {
  return kindsOf(manifest).indexOf("bar-widget") !== -1
}

function isPluginsTabCandidate(manifest) {
  if (!manifest) return false
  var id = canonicalId(manifest.id)
  if (id === "omaxian.settings" || id === "omarchy.bar") return false
  var kinds = kindsOf(manifest)
  if (kinds.indexOf("bar") !== -1) return false
  var onlyBarWidget = kinds.length === 1 && kinds[0] === "bar-widget"
  if (onlyBarWidget) return false
  return kinds.indexOf("panel") !== -1
    || kinds.indexOf("overlay") !== -1
    || kinds.indexOf("service") !== -1
    || kinds.indexOf("menu") !== -1
}

function displayNameOf(manifest, fallbackId) {
  if (!manifest) return String(fallbackId || "")
  var meta = isPlainObject(manifest.barWidget) ? manifest.barWidget : {}
  return String(meta.displayName || manifest.name || fallbackId || "")
}

function widgetSchema(manifest) {
  if (!manifest || !isPlainObject(manifest.barWidget)) return []
  return arrayFrom(manifest.barWidget.schema)
}

function widgetDefaults(manifest) {
  if (!manifest || !isPlainObject(manifest.barWidget) || !isPlainObject(manifest.barWidget.defaults))
    return {}
  return manifest.barWidget.defaults
}

function defaultSectionOf(manifest) {
  var meta = manifest && isPlainObject(manifest.barWidget) ? manifest.barWidget : null
  var section = meta ? String(meta.defaultSection || "") : ""
  return SECTIONS.indexOf(section) !== -1 ? section : "right"
}

function schemaFieldValue(schemaItem, values, defaults) {
  var key = schemaItem && schemaItem.key !== undefined ? String(schemaItem.key) : ""
  if (!key) return undefined
  if (isPlainObject(values) && values[key] !== undefined) return values[key]
  if (isPlainObject(defaults) && defaults[key] !== undefined) return defaults[key]
  if (schemaItem.defaultValue !== undefined) return schemaItem.defaultValue
  return undefined
}

// ---- dock-settings.json

var DEFAULT_DOCK = { fullWidth: true, roundedCorners: false, hoverAnimation: true }

function parseDockSettings(raw) {
  var text = String(raw === undefined || raw === null ? "" : raw).trim()
  var parsed = null
  if (text) {
    try { parsed = JSON.parse(text) } catch (e) { parsed = null }
  }
  var source = isPlainObject(parsed) ? parsed : {}
  return {
    fullWidth: source.fullWidth === undefined ? DEFAULT_DOCK.fullWidth : !!source.fullWidth,
    roundedCorners: source.roundedCorners === undefined ? DEFAULT_DOCK.roundedCorners : !!source.roundedCorners,
    hoverAnimation: source.hoverAnimation === undefined ? DEFAULT_DOCK.hoverAnimation : !!source.hoverAnimation
  }
}

function serializeDockSettings(settings) {
  var s = isPlainObject(settings) ? settings : {}
  return JSON.stringify({
    fullWidth: s.fullWidth !== false,
    roundedCorners: !!s.roundedCorners,
    hoverAnimation: s.hoverAnimation !== false
  }, null, 2) + "\n"
}

// ---- wallpaper-settings.json

function parseWallpaperSettings(raw) {
  var text = String(raw === undefined || raw === null ? "" : raw).trim()
  var parsed = null
  if (text) {
    try { parsed = JSON.parse(text) } catch (e) { parsed = null }
  }
  var source = isPlainObject(parsed) ? parsed : {}
  return {
    localFolder: (typeof source.localFolder === "string") ? source.localFolder.trim() : ""
  }
}

function serializeWallpaperSettings(settings) {
  var s = isPlainObject(settings) ? settings : {}
  return JSON.stringify({
    localFolder: (typeof s.localFolder === "string") ? s.localFolder.trim() : ""
  }, null, 2) + "\n"
}

// ---- startup.json

function stripDesktop(id) {
  var value = String(id === undefined || id === null ? "" : id).trim()
  var lower = value.toLowerCase()
  // Filename of an id that itself ends with ".desktop"
  // (org.telegram.desktop.desktop). Do not peel a single trailing
  // ".desktop" — that is part of some Quickshell ids, and UI callers
  // already pass ids with the file extension omitted.
  if (lower.slice(-16) === ".desktop.desktop") return value.slice(0, -8)
  return value
}

function parseStartup(raw) {
  var text = String(raw === undefined || raw === null ? "" : raw).trim()
  if (!text) return { apps: [] }
  var parsed = null
  try { parsed = JSON.parse(text) } catch (e) { return { apps: [] } }
  var arr = isPlainObject(parsed) ? arrayFrom(parsed.apps) : []
  var out = []
  var seen = {}
  for (var i = 0; i < arr.length; i++) {
    var item = arr[i]
    var desktopId = ""
    var enabled = true
    if (typeof item === "string") {
      desktopId = stripDesktop(item)
    } else if (isPlainObject(item)) {
      desktopId = stripDesktop(item.desktopId || item.id || "")
      enabled = item.enabled !== false
    }
    if (!desktopId || seen[desktopId]) continue
    seen[desktopId] = true
    out.push({ desktopId: desktopId, enabled: enabled })
  }
  return { apps: out }
}

function serializeStartup(apps) {
  var arr = arrayFrom(apps)
  var out = []
  var seen = {}
  for (var i = 0; i < arr.length; i++) {
    var item = arr[i]
    var desktopId = stripDesktop(isPlainObject(item) ? (item.desktopId || item.id) : item)
    if (!desktopId || seen[desktopId]) continue
    seen[desktopId] = true
    out.push({
      desktopId: desktopId,
      enabled: isPlainObject(item) ? item.enabled !== false : true
    })
  }
  return JSON.stringify({ apps: out }, null, 2) + "\n"
}

// ---- user shell.toml

function parseShell(raw) {
  var parsed = {}
  var text = String(raw || "")
  if (!text) return parsed
  var lines = text.split("\n")
  var section = ""
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].replace(/^\s+|\s+$/g, "")
    if (!line || line.charAt(0) === "#") continue
    var sectionMatch = line.match(/^\[([A-Za-z0-9_-]+)\]\s*(#.*)?$/)
    if (sectionMatch) { section = sectionMatch[1]; continue }
    var stringKv = line.match(/^([A-Za-z0-9_-]+)\s*=\s*["']([^"']+)["']\s*(#.*)?$/)
    var numKv = line.match(/^([A-Za-z0-9_-]+)\s*=\s*(-?\d+(?:\.\d+)?)\s*(#.*)?$/)
    var widthKv = line.match(/^([A-Za-z0-9_-]+)\s*=\s*(-?\d+(?:\.\d+)?(?:\s+-?\d+(?:\.\d+)?){1,3})\s*(#.*)?$/)
    var bareKv = line.match(/^([A-Za-z0-9_-]+)\s*=\s*([A-Za-z][A-Za-z0-9_-]*)\s*(#.*)?$/)
    var kv = stringKv || numKv || widthKv || bareKv
    if (!kv || !section) continue
    parsed[section + "." + kv[1]] = kv[2]
  }
  return parsed
}

function upsertToml(raw, updates) {
  var parsed = parseShell(raw)
  if (!isPlainObject(updates)) return serializeShell(parsed)
  for (var key in updates) {
    if (updates[key] === undefined || updates[key] === null) continue
    parsed[String(key)] = String(updates[key])
  }
  return serializeShell(parsed)
}

function serializeShell(flat) {
  var sections = {}
  var order = []
  for (var fullKey in flat) {
    var dot = String(fullKey).indexOf(".")
    if (dot < 0) continue
    var section = fullKey.substr(0, dot)
    var key = fullKey.substr(dot + 1)
    if (!sections[section]) {
      sections[section] = {}
      order.push(section)
    }
    sections[section][key] = flat[fullKey]
  }
  var preferred = ["font", "spacing", "bar"]
  var seen = {}
  var lines = []
  function writeSection(name) {
    if (seen[name] || !sections[name]) return
    seen[name] = true
    if (lines.length) lines.push("")
    lines.push("[" + name + "]")
    var keys = Object.keys(sections[name]).sort()
    for (var i = 0; i < keys.length; i++) {
      var k = keys[i]
      var v = String(sections[name][k])
      if (/^-?\d+(?:\.\d+)?$/.test(v) || v === "true" || v === "false")
        lines.push(k + " = " + v)
      else
        lines.push(k + " = \"" + v.replace(/"/g, "") + "\"")
    }
  }
  for (var p = 0; p < preferred.length; p++) writeSection(preferred[p])
  for (var s = 0; s < order.length; s++) writeSection(order[s])
  return lines.length ? (lines.join("\n") + "\n") : ""
}

function tomlNumber(flat, key, fallback) {
  var raw = isPlainObject(flat) ? flat[key] : undefined
  var n = Number(raw)
  return isFinite(n) ? n : fallback
}

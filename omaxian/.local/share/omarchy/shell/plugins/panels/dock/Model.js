.pragma library

// Dock MVP — pinned-list persistence + window<->desktop-entry matching.
// Deliberately a fraction of upstream omarchy-dock's DockPinned.js (476
// lines, stacks/folders) + DockMatcher.js (1193 lines, CLI/web-app/brand
// heuristics): this MVP has no stacks and leans on DesktopEntry.startupClass
// (StartupWMClass) for matching, with a plain normalized-id fallback.

var DEFAULT_SETTINGS = {
    fullWidth: true,
    roundedCorners: false,
    hoverAnimation: true,
    background: "",
    opacity: 1,
    iconSize: 36,
    hoverScale: 1.3,
    cornerRadius: 0,
    islandGap: 0,
    runningIndicator: "dot",
    autoHide: false
}

function normalizeHex(value) {
    var s = String(value === undefined || value === null ? "" : value).trim()
    if (!s) return ""
    if (s.charAt(0) !== "#") s = "#" + s
    if (/^#[0-9A-Fa-f]{3}$/.test(s) || /^#[0-9A-Fa-f]{6}$/.test(s))
        return s.toLowerCase()
    return ""
}

function parseOpacity(value) {
    var n = Number(value)
    if (!isFinite(n)) return DEFAULT_SETTINGS.opacity
    if (n < 0) return 0
    if (n > 1) return 1
    return Math.round(n * 100) / 100
}

function parseIntClamped(value, fallback, min, max) {
    var n = Math.round(Number(value))
    if (!isFinite(n)) return fallback
    if (n < min) return min
    if (n > max) return max
    return n
}

function parseHoverScale(value) {
    var n = Number(value)
    if (!isFinite(n)) return DEFAULT_SETTINGS.hoverScale
    if (n < 1) return 1
    if (n > 2) return 2
    return Math.round(n * 100) / 100
}

function parseRunningIndicator(value) {
    var s = String(value === undefined || value === null ? "" : value).trim().toLowerCase()
    if (s === "dot" || s === "bar" || s === "none") return s
    return DEFAULT_SETTINGS.runningIndicator
}

function parseBool(value, fallback) {
    if (value === undefined || value === null || value === "") return fallback
    if (value === true || value === false) return value
    var s = String(value).trim().toLowerCase()
    if (s === "true" || s === "1" || s === "yes" || s === "on") return true
    if (s === "false" || s === "0" || s === "no" || s === "off") return false
    return fallback
}

function normalizeSettings(source) {
    var s = (source && typeof source === "object") ? source : {}
    var cornerRadius = DEFAULT_SETTINGS.cornerRadius
    if (s.cornerRadius !== undefined && s.cornerRadius !== null && s.cornerRadius !== "")
        cornerRadius = parseIntClamped(s.cornerRadius, DEFAULT_SETTINGS.cornerRadius, 0, 48)
    else if (s.roundedCorners === true || s.roundedCorners === "true")
        cornerRadius = 12
    return {
        fullWidth: parseBool(s.fullWidth, DEFAULT_SETTINGS.fullWidth),
        roundedCorners: cornerRadius > 0,
        hoverAnimation: parseBool(s.hoverAnimation, DEFAULT_SETTINGS.hoverAnimation),
        background: normalizeHex(s.background),
        opacity: parseOpacity(s.opacity),
        iconSize: parseIntClamped(s.iconSize, DEFAULT_SETTINGS.iconSize, 16, 96),
        hoverScale: parseHoverScale(s.hoverScale),
        cornerRadius: cornerRadius,
        islandGap: parseIntClamped(s.islandGap, DEFAULT_SETTINGS.islandGap, 0, 48),
        runningIndicator: parseRunningIndicator(s.runningIndicator),
        autoHide: parseBool(s.autoHide, DEFAULT_SETTINGS.autoHide)
    }
}

// Sparse layer: only keys explicitly present in the source object.
function sparseFromObject(source) {
    var s = (source && typeof source === "object") ? source : {}
    var out = {}
    if (s.fullWidth !== undefined) out.fullWidth = parseBool(s.fullWidth, DEFAULT_SETTINGS.fullWidth)
    if (s.hoverAnimation !== undefined) out.hoverAnimation = parseBool(s.hoverAnimation, DEFAULT_SETTINGS.hoverAnimation)
    if (s.background !== undefined) out.background = normalizeHex(s.background)
    if (s.opacity !== undefined) out.opacity = parseOpacity(s.opacity)
    if (s.iconSize !== undefined) out.iconSize = parseIntClamped(s.iconSize, DEFAULT_SETTINGS.iconSize, 16, 96)
    if (s.hoverScale !== undefined) out.hoverScale = parseHoverScale(s.hoverScale)
    if (s.cornerRadius !== undefined || s.roundedCorners !== undefined) {
        if (s.cornerRadius !== undefined && s.cornerRadius !== null && s.cornerRadius !== "")
            out.cornerRadius = parseIntClamped(s.cornerRadius, DEFAULT_SETTINGS.cornerRadius, 0, 48)
        else if (s.roundedCorners === true || s.roundedCorners === "true")
            out.cornerRadius = 12
        else if (s.roundedCorners === false || s.roundedCorners === "false")
            out.cornerRadius = 0
        out.roundedCorners = out.cornerRadius > 0
    }
    if (s.islandGap !== undefined) out.islandGap = parseIntClamped(s.islandGap, DEFAULT_SETTINGS.islandGap, 0, 48)
    if (s.runningIndicator !== undefined) out.runningIndicator = parseRunningIndicator(s.runningIndicator)
    if (s.autoHide !== undefined) out.autoHide = parseBool(s.autoHide, DEFAULT_SETTINGS.autoHide)
    return out
}

function applySparse(base, sparse) {
    var out = {}
    var k
    for (k in base) out[k] = base[k]
    for (k in sparse) out[k] = sparse[k]
    return normalizeSettings(out)
}

function mergeSettings(themeSparse, userSparse) {
    return applySparse(applySparse(DEFAULT_SETTINGS, themeSparse || {}), userSparse || {})
}

function parseTomlFlat(raw) {
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
        var stringKv = line.match(/^([A-Za-z0-9_-]+)\s*=\s*["']([^"']*)["']\s*(#.*)?$/)
        var numKv = line.match(/^([A-Za-z0-9_-]+)\s*=\s*(-?\d+(?:\.\d+)?)\s*(#.*)?$/)
        var bareKv = line.match(/^([A-Za-z0-9_-]+)\s*=\s*([A-Za-z][A-Za-z0-9_-]*)\s*(#.*)?$/)
        var kv = stringKv || numKv || bareKv
        if (!kv || !section) continue
        parsed[section + "." + kv[1]] = kv[2]
    }
    return parsed
}

function sparseFromTomlFlat(flat) {
    var f = flat || {}
    var src = {}
    if (f["dock.full-width"] !== undefined) src.fullWidth = f["dock.full-width"]
    if (f["dock.hover-animation"] !== undefined) src.hoverAnimation = f["dock.hover-animation"]
    if (f["dock.background"] !== undefined) src.background = f["dock.background"]
    if (f["dock.opacity"] !== undefined) src.opacity = f["dock.opacity"]
    if (f["dock.icon-size"] !== undefined) src.iconSize = f["dock.icon-size"]
    if (f["dock.hover-scale"] !== undefined) src.hoverScale = f["dock.hover-scale"]
    if (f["dock.corner-radius"] !== undefined) src.cornerRadius = f["dock.corner-radius"]
    if (f["dock.rounded-corners"] !== undefined) src.roundedCorners = f["dock.rounded-corners"]
    if (f["dock.island-gap"] !== undefined) src.islandGap = f["dock.island-gap"]
    if (f["dock.running-indicator"] !== undefined) src.runningIndicator = f["dock.running-indicator"]
    if (f["dock.auto-hide"] !== undefined) src.autoHide = f["dock.auto-hide"]
    return sparseFromObject(src)
}

function parseTomlSparse(raw) {
    return sparseFromTomlFlat(parseTomlFlat(raw))
}

function parseToml(raw) {
    return mergeSettings(parseTomlSparse(raw), {})
}

function settingsToTomlFlat(settings) {
    var s = normalizeSettings(settings)
    return {
        "dock.full-width": s.fullWidth ? "true" : "false",
        "dock.hover-animation": s.hoverAnimation ? "true" : "false",
        "dock.background": s.background || "",
        "dock.opacity": String(s.opacity),
        "dock.icon-size": String(s.iconSize),
        "dock.hover-scale": String(s.hoverScale),
        "dock.corner-radius": String(s.cornerRadius),
        "dock.island-gap": String(s.islandGap),
        "dock.running-indicator": s.runningIndicator,
        "dock.auto-hide": s.autoHide ? "true" : "false"
    }
}

function serializeTomlFlat(flat) {
    var f = flat || {}
    var keys = [
        "full-width", "hover-animation", "background", "opacity",
        "icon-size", "hover-scale", "corner-radius", "island-gap",
        "running-indicator", "auto-hide"
    ]
    var lines = [
        "# Omaxian dock appearance. Themes ship this as dock.toml;",
        "# ~/.config/omarchy/dock.toml overlays and survives theme switches.",
        "",
        "[dock]"
    ]
    var any = false
    for (var i = 0; i < keys.length; i++) {
        var k = keys[i]
        var v = f["dock." + k]
        if (v === undefined) continue
        any = true
        v = String(v)
        if (/^-?\d+(?:\.\d+)?$/.test(v) || v === "true" || v === "false")
            lines.push(k + " = " + v)
        else
            lines.push(k + " = \"" + v.replace(/"/g, "") + "\"")
    }
    if (!any) return ""
    return lines.join("\n") + "\n"
}

function serializeToml(settings) {
    return serializeTomlFlat(settingsToTomlFlat(settings))
}

function upsertToml(raw, updates) {
    var flat = parseTomlFlat(raw)
    var camel = sparseFromObject(updates || {})
    var keyMap = {
        fullWidth: "dock.full-width",
        hoverAnimation: "dock.hover-animation",
        background: "dock.background",
        opacity: "dock.opacity",
        iconSize: "dock.icon-size",
        hoverScale: "dock.hover-scale",
        cornerRadius: "dock.corner-radius",
        islandGap: "dock.island-gap",
        runningIndicator: "dock.running-indicator",
        autoHide: "dock.auto-hide"
    }
    var normalized = normalizeSettings(applySparse(DEFAULT_SETTINGS, camel))
    var fullFlat = settingsToTomlFlat(normalized)
    for (var ck in camel) {
        var tk = keyMap[ck]
        if (tk) flat[tk] = fullFlat[tk]
    }
    return serializeTomlFlat(flat)
}

function parseSettings(raw) {
    var text = String(raw === undefined || raw === null ? "" : raw).trim()
    if (!text) return normalizeSettings({})
    if (text.charAt(0) === "{" || text.charAt(0) === "[") {
        var parsed = null
        try { parsed = JSON.parse(text) } catch (e) { parsed = null }
        return normalizeSettings(parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : {})
    }
    return parseToml(text)
}

function parseSettingsSparse(raw) {
    var text = String(raw === undefined || raw === null ? "" : raw).trim()
    if (!text) return {}
    if (text.charAt(0) === "{") {
        var parsed = null
        try { parsed = JSON.parse(text) } catch (e) { parsed = null }
        return sparseFromObject(parsed && typeof parsed === "object" ? parsed : {})
    }
    return parseTomlSparse(text)
}

function serializeSettings(settings) {
    return serializeToml(settings)
}

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

function normalize(value) {
    return String(value === undefined || value === null ? "" : value).toLowerCase().replace(/[^a-z0-9]/g, "")
}

function parsePinned(raw) {
    var text = String(raw === undefined || raw === null ? "" : raw).trim()
    if (!text) return []
    var parsed = null
    try {
        parsed = JSON.parse(text)
    } catch (e) {
        return []
    }
    var arr = Array.isArray(parsed) ? parsed : (parsed && Array.isArray(parsed.pinned) ? parsed.pinned : [])
    var out = []
    for (var i = 0; i < arr.length; i++) {
        var id = stripDesktop(arr[i])
        if (id && out.indexOf(id) === -1) out.push(id)
    }
    return out
}

function serializePinned(pinnedList) {
    var arr = Array.isArray(pinnedList) ? pinnedList : []
    var cleaned = []
    for (var i = 0; i < arr.length; i++) {
        var id = stripDesktop(arr[i])
        if (id && cleaned.indexOf(id) === -1) cleaned.push(id)
    }
    return JSON.stringify({ pinned: cleaned }, null, 2)
}

function togglePinned(pinnedList, appId) {
    var arr = Array.isArray(pinnedList) ? pinnedList.slice() : []
    var id = stripDesktop(appId)
    if (!id) return arr
    var idx = arr.indexOf(id)
    if (idx !== -1) {
        arr.splice(idx, 1)
        return arr
    }
    arr.push(id)
    return arr
}

// Best desktop-entry match for a running window, in order of confidence:
// StartupWMClass (exact intent of the .desktop spec), then normalized
// desktop-id, then normalized exec basename.
function entryForWindow(win, entries) {
    if (!win || !win.appId) return null
    var target = normalize(win.appId)
    if (!target) return null

    var list = Array.isArray(entries) ? entries : []
    for (var i = 0; i < list.length; i++) {
        var e = list[i]
        if (e && e.startupClass && normalize(e.startupClass) === target) return e
    }
    for (var j = 0; j < list.length; j++) {
        var e2 = list[j]
        if (e2 && normalize(stripDesktop(e2.id)) === target) return e2
    }
    for (var k = 0; k < list.length; k++) {
        var e3 = list[k]
        if (!e3 || !e3.command || e3.command.length === 0) continue
        var exec = String(e3.command[0] || "")
        var base = exec.slice(exec.lastIndexOf("/") + 1)
        if (base && normalize(base) === target) return e3
    }
    return null
}

function findEntryById(entries, id) {
    var clean = stripDesktop(id)
    if (!clean) return null
    var list = Array.isArray(entries) ? entries : []
    for (var i = 0; i < list.length; i++) {
        if (list[i] && stripDesktop(list[i].id) === clean) return list[i]
    }
    return null
}

function windowsForEntry(windows, entry, fallbackAppId) {
    var list = Array.isArray(windows) ? windows : []
    var out = []
    for (var i = 0; i < list.length; i++) {
        var w = list[i]
        var matched = entry ? entryForWindow(w, [entry]) : null
        if (matched || (!entry && fallbackAppId && normalize(w.appId) === normalize(fallbackAppId))) {
            out.push(w)
        }
    }
    return out
}

// Pinned items (in order) + unpinned-but-running apps appended after, each
// shaped { id, entry, pinned, windows, running, urgent }.
function buildDockItems(pinnedList, windows, entries) {
    var pinned = Array.isArray(pinnedList) ? pinnedList : []
    var winList = Array.isArray(windows) ? windows : []
    var items = []
    var claimed = {} // conId -> true

    function markUrgent(wins) {
        for (var i = 0; i < wins.length; i++) if (wins[i].urgent) return true
        return false
    }

    for (var p = 0; p < pinned.length; p++) {
        var id = pinned[p]
        var entry = findEntryById(entries, id)
        var wins = windowsForEntry(winList, entry, id)
        for (var w = 0; w < wins.length; w++) claimed[wins[w].conId] = true
        items.push({
            id: id,
            entry: entry,
            pinned: true,
            windows: wins,
            running: wins.length > 0,
            urgent: markUrgent(wins)
        })
    }

    // Group remaining (unclaimed) windows by matched entry, or by raw appId
    // when no desktop entry matches.
    var order = []
    var groups = {}
    for (var i = 0; i < winList.length; i++) {
        var win = winList[i]
        if (claimed[win.conId]) continue
        var matchedEntry = entryForWindow(win, entries)
        var key = matchedEntry ? stripDesktop(matchedEntry.id) : ("raw:" + normalize(win.appId))
        if (!groups[key]) {
            groups[key] = { id: matchedEntry ? stripDesktop(matchedEntry.id) : win.appId, entry: matchedEntry, windows: [] }
            order.push(key)
        }
        groups[key].windows.push(win)
    }
    for (var g = 0; g < order.length; g++) {
        var grp = groups[order[g]]
        items.push({
            id: grp.id,
            entry: grp.entry,
            pinned: false,
            windows: grp.windows,
            running: true,
            urgent: markUrgent(grp.windows)
        })
    }

    return items
}

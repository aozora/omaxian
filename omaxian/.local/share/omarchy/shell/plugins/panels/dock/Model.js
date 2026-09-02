.pragma library

// Dock MVP — pinned-list persistence + window<->desktop-entry matching.
// Deliberately a fraction of upstream omarchy-dock's DockPinned.js (476
// lines, stacks/folders) + DockMatcher.js (1193 lines, CLI/web-app/brand
// heuristics): this MVP has no stacks and leans on DesktopEntry.startupClass
// (StartupWMClass) for matching, with a plain normalized-id fallback.

var DEFAULT_SETTINGS = {
    fullWidth: true,
    roundedCorners: false,
    hoverAnimation: true
}

function parseSettings(raw) {
    var text = String(raw === undefined || raw === null ? "" : raw).trim()
    var parsed = null
    if (text) {
        try {
            parsed = JSON.parse(text)
        } catch (e) {
            parsed = null
        }
    }
    var source = (parsed && typeof parsed === "object") ? parsed : {}
    return {
        fullWidth: source.fullWidth === undefined ? DEFAULT_SETTINGS.fullWidth : !!source.fullWidth,
        roundedCorners: source.roundedCorners === undefined ? DEFAULT_SETTINGS.roundedCorners : !!source.roundedCorners,
        hoverAnimation: source.hoverAnimation === undefined ? DEFAULT_SETTINGS.hoverAnimation : !!source.hoverAnimation
    }
}

function serializeSettings(settings) {
    var s = (settings && typeof settings === "object") ? settings : {}
    return JSON.stringify({
        fullWidth: s.fullWidth !== false,
        roundedCorners: !!s.roundedCorners,
        hoverAnimation: s.hoverAnimation !== false
    }, null, 2)
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

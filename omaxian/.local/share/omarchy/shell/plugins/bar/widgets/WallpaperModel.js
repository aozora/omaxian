.pragma library

// Wallpaper picker settings — persisted to
// ~/.config/omarchy/wallpaper-settings.json (same directory and JSON
// convention as dock-settings.json / dock-pinned.json). One key today:
// `localFolder`, the directory the "From local folder" tab scans.
//
// Duplicated verbatim in plugins/panels/controlpanel/Model.js
// (parseWallpaperSettings / serializeWallpaperSettings) — Control Panel is a
// separate, self-contained plugin and does not import from here.

function parseSettings(raw) {
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

function serializeSettings(settings) {
    var s = (settings && typeof settings === "object") ? settings : {}
    return JSON.stringify({
        localFolder: (typeof s.localFolder === "string") ? s.localFolder.trim() : ""
    }, null, 2)
}

// Prefer the live theme package / user overlay so edits under
// ~/.local/share/omarchy/themes/<name>/backgrounds show without re-running
// omarchy-theme-set. Fall back to the applied current/theme copy.
function themeBackgroundCandidates(home, omarchyPath, themeName) {
    var h = String(home || "")
    var name = String(themeName || "").trim()
    var omarchy = String(omarchyPath || (h + "/.local/share/omarchy"))
    var applied = h + "/.local/state/omarchy/current/theme/backgrounds"
    if (!name) return [applied]
    return [
        omarchy + "/themes/" + name + "/backgrounds",
        h + "/.config/omarchy/themes/" + name + "/backgrounds",
        applied
    ]
}

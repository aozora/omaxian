import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "AppSearch.js" as AppSearch

// Shared desktop-application library: the sorted entry list with hidden-entry
// filtering + an icon fallback index. Instance, exposed as shell.appLibrary
// (see shell.qml); consumed by the `omarchy.menu` palette (apps provider)
// and still owned by the shell host.
//
// X11 delta: upstream `services/AppLibrary.qml` also drives a Wayland
// launch-feedback OSD via `Quickshell.Wayland` / `ToplevelManager`
// (spinner while the launched window appears). None of that maps to X11 —
// dropped, along with `remove()` (no hide-from-launcher UI in this profile).
// `launch()` is `uwsm-app -- gtk-launch` → plain `gtk-launch`.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  property var configuredHiddenEntryIds: ({})
  property var desktopHiddenEntryIds: ({})

  // icon name -> file on disk, for icons Qt's themed lookup misses (installed
  // after this process started). Refreshed when the app list changes.
  property var iconIndex: ({})
  property var pendingIconIndex: ({})

  // Loose AppImages (no .desktop) found under the usual drop dirs, as
  // {name, path}. Flatpak + AppImageLauncher-integrated AppImages already
  // come through DesktopEntries (their .desktop lives in an
  // $XDG_DATA_DIRS/applications dir), so those are NOT rescanned here.
  property var appImages: []
  property var pendingAppImages: []

  signal appsChanged()

  function entryName(entry) {
    return AppSearch.entryName(entry)
  }

  function entryDisplayName(entry) {
    return AppSearch.entryDisplayName(entry)
  }

  function entrySubtext(entry) {
    return AppSearch.entrySubtext(entry)
  }

  function isHiddenEntry(entry) {
    var id = String((entry && entry.id) || "")
    return root.configuredHiddenEntryIds[id] === true || root.desktopHiddenEntryIds[id] === true
  }

  // "Backgammon-1.2.x86_64.AppImage" -> "Backgammon"
  function appImageDisplayName(path) {
    var base = String(path).split("/").pop()
    base = base.replace(/\.(AppImage|appimage)$/, "")
    base = base.replace(/[._-]?(x86_64|amd64|aarch64|arm64|linux)$/i, "")
    base = base.replace(/[ ._-]?v?\d[\d.]*$/, "")
    base = base.replace(/[._-]+/g, " ").trim()
    if (!base) return String(path).split("/").pop()
    return base.replace(/\b([a-z])/g, function(_, c) { return c.toUpperCase() })
  }

  function appImageEntries() {
    var list = root.appImages || []
    if (list.length === 0) return []
    // Drop any AppImage whose name already exists as a real desktop entry
    // (AppImageLauncher / appimaged integration).
    var taken = {}
    var vals = DesktopEntries.applications.values || []
    for (var i = 0; i < vals.length; i++)
      taken[String((vals[i] && vals[i].name) || "").toLowerCase()] = true
    var out = []
    for (var j = 0; j < list.length; j++) {
      var name = list[j].name
      if (taken[String(name).toLowerCase()]) continue
      out.push({
        id: "appimage://" + list[j].path,
        name: name,
        genericName: "AppImage",
        comment: list[j].path,
        icon: "application-x-executable",
        _appimagePath: list[j].path
      })
    }
    return out
  }

  function sortedEntries(query) {
    var values = (DesktopEntries.applications.values || []).concat(root.appImageEntries())
    // AppSearch returns scored wrappers `{ entry, score, key, name }`. Unwrap
    // to bare DesktopEntry / AppImage objects so dock matching can read
    // `.id` / `.startupClass` / `.command` directly. `omarchy.menu` accepts
    // either shape in mergeAppRows.
    return AppSearch.sortedEntries(values, query, function(entry) { return root.isHiddenEntry(entry) })
      .map(function(row) { return (row && row.entry) ? row.entry : row })
  }

  function refreshAppImages() {
    if (!appImageScan.running) appImageScan.running = true
  }

  function appImageScanCommand() {
    return [
      'for d in "$HOME/Applications" "$HOME/AppImages" "$HOME/.local/bin"',
      '        "$HOME/bin" "$HOME/Downloads" "$HOME/Desktop" /opt; do',
      '  [ -d "$d" ] && find "$d" -maxdepth 2 -type f \\( -iname "*.AppImage" \\) 2>/dev/null;',
      'done'
    ].join(' ')
  }

  function iconSource(icon) {
    var value = String(icon || "")
    if (value.length === 0) return Quickshell.iconPath("application-x-executable", true)
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    // Prefer Qt's theme lookup (size-aware) over the filesystem index — the
    // index is first-wins and often latches onto a 16×16 PNG before a larger
    // one, which the dock then upscales into blur.
    var themed = Quickshell.iconPath(value, true)
    if (themed.length > 0) return themed
    var found = root.iconIndex[value]
    if (found) return Util.fileUrl(found)
    return Quickshell.iconPath("application-x-executable", true)
  }

  function refreshIcons() {
    if (!iconIndexScan.running) iconIndexScan.running = true
  }

  // Launch via `setsid -f gtk-launch <filename>`.
  //  - `gtk-launch` (not `entry.execute()`): QS 0.3.0's Debian build compiles
  //    in the systemd launch path, and Devuan has no `systemd --user`, so
  //    `execute()` no-ops. `gtk-launch` parses Exec=/field-codes/Terminal=
  //    from the .desktop and resolves the id against the session
  //    XDG_DATA_DIRS (i3_bar force-adds the flatpak export dirs). Matches
  //    upstream omarchy minus its `uwsm-app` scope wrapper.
  //  - `setsid -f`: QS 0.3.0's `execDetached` does NOT fully detach on this
  //    build — when the direct child (`gtk-launch`) exits, the grandchild GUI
  //    app is signalled and dies. A new session via `setsid -f` keeps it
  //    alive (same reason the AppImage branch above already uses it).
  function launch(entryOrId, name) {
    // Defensive: unwrap a scored row `{ entry, score, key, name }` if one slips through.
    if (entryOrId && typeof entryOrId === "object" && entryOrId.entry && !entryOrId.id)
      entryOrId = entryOrId.entry

    // Loose AppImage pseudo-entry: chmod +x (some downloads aren't) then exec.
    if (entryOrId && entryOrId._appimagePath) {
      Quickshell.execDetached(["bash", "-c",
        'chmod +x -- "$1" 2>/dev/null; exec setsid -f -- "$1"', "bash", String(entryOrId._appimagePath)])
      return
    }

    var entry = (entryOrId && typeof entryOrId === "object")
      ? entryOrId
      : DesktopEntries.byId(String(entryOrId || ""))

    var id = String((entry && entry.id) || entryOrId || "")
    var desktopFile = root.gtkLaunchDesktopFile(id)
    if (desktopFile) {
      Quickshell.execDetached(["setsid", "-f", "gtk-launch", desktopFile])
      return
    }
    if (entry && entry.command && entry.command.length > 0)
      Quickshell.execDetached(["setsid", "-f"].concat(entry.command.map(String)))
  }

  // gtk-launch (GTK 3.24+) treats an argument that already ends with
  // ".desktop" as a complete filename and will not append the extension.
  // Quickshell's DesktopEntry.id is the basename minus one ".desktop", so
  // org.telegram.desktop must be passed as org.telegram.desktop.desktop —
  // otherwise gtk-launch looks up a missing org.telegram.desktop file and
  // the menu entry no-ops.
  function gtkLaunchDesktopFile(id) {
    var value = String(id || "").trim()
    if (!value) return ""
    var lower = value.toLowerCase()
    if (lower.slice(-16) === ".desktop.desktop") return value
    if (lower.slice(-8) === ".desktop") {
      if (DesktopEntries.byId(value)) return value + ".desktop"
      return value
    }
    return value + ".desktop"
  }

  function normalizeDesktopId(id) {
    var value = String(id || "").trim()
    var lower = value.toLowerCase()
    if (lower.slice(-16) === ".desktop.desktop") return value.slice(0, -8)
    if (lower.slice(-8) === ".desktop") {
      if (DesktopEntries.byId(value)) return value
      return value.slice(0, -8)
    }
    return value
  }

  function loadConfiguredHides(rawText) {
    var next = ({})
    var lines = String(rawText || "").split(/\n/)
    for (var i = 0; i < lines.length; i++) {
      var id = root.normalizeDesktopId(lines[i])
      if (id.length > 0) next[id] = true
    }
    root.configuredHiddenEntryIds = next
    root.appsChanged()
  }

  function loadDesktopHiddenEntries(rawText) {
    var next = ({})
    var lines = String(rawText || "").split(/\n/)
    for (var i = 0; i < lines.length; i++) {
      var id = root.normalizeDesktopId(lines[i])
      if (id.length > 0) next[id] = true
    }
    root.desktopHiddenEntryIds = next
    root.appsChanged()
  }

  function iconIndexScanCommand() {
    return [
      'dirs="$HOME/.icons $HOME/.local/share/icons";',
      'IFS=":"; for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do dirs="$dirs $d/icons"; done; unset IFS;',
      'for ext in svg png; do',
      '  for base in $dirs; do',
      '    [[ -d $base ]] && find "$base" \\( -path "*/apps/*" -o -path "*/devices/*" \\) -name "*.$ext" 2>/dev/null;',
      '  done;',
      '  find /usr/share/pixmaps -maxdepth 1 -name "*.$ext" 2>/dev/null;',
      'done'
    ].join(' ')
  }

  function indexIconLine(path) {
    var value = String(path || "").trim()
    if (value.length === 0) return
    var slash = value.lastIndexOf("/")
    var file = slash >= 0 ? value.slice(slash + 1) : value
    var dot = file.lastIndexOf(".")
    var name = dot > 0 ? file.slice(0, dot) : file
    if (name.length === 0) return
    var existing = root.pendingIconIndex[name]
    if (existing === undefined || root.iconPathScore(value) > root.iconPathScore(existing))
      root.pendingIconIndex[name] = value
  }

  // Higher is better: SVG / scalable beat sized PNGs; among PNGs prefer the
  // largest theme size directory (256x256 > 48x48 > 16x16).
  function iconPathScore(path) {
    var p = String(path || "")
    var lower = p.toLowerCase()
    if (lower.slice(-4) === ".svg") return 10000
    if (p.indexOf("/scalable/") !== -1) return 9999
    var m = p.match(/\/(\d+)x\d+\//)
    if (m) return Number(m[1])
    return 1
  }

  function hiddenEntryScanCommand() {
    var desktop = [Quickshell.env("XDG_CURRENT_DESKTOP"), Quickshell.env("XDG_SESSION_DESKTOP"), Quickshell.env("DESKTOP_SESSION")].filter(function(v) { return String(v || "").length > 0 }).join(":")
    var script = root.omarchyPath + "/shell/services/hidden-entries.sh"
    return Util.shellQuote(script) + " " + Util.shellQuote(desktop)
  }

  QtObject {
    id: hiddenEntryOutput
    property string text: ""
  }

  Process {
    id: hiddenEntryScan
    command: ["bash", "-c", root.hiddenEntryScanCommand()]
    stdout: SplitParser { onRead: function(line) { hiddenEntryOutput.text += line + "\n" } }
    onStarted: hiddenEntryOutput.text = ""
    onExited: root.loadDesktopHiddenEntries(hiddenEntryOutput.text)
  }

  Process {
    id: iconIndexScan
    command: ["bash", "-c", root.iconIndexScanCommand()]
    stdout: SplitParser { onRead: function(line) { root.indexIconLine(line) } }
    onStarted: root.pendingIconIndex = ({})
    onExited: root.iconIndex = root.pendingIconIndex
  }

  Process {
    id: appImageScan
    command: ["bash", "-c", root.appImageScanCommand()]
    stdout: SplitParser {
      onRead: function(line) {
        var p = String(line || "").trim()
        if (p.length > 0) root.pendingAppImages.push({ name: root.appImageDisplayName(p), path: p })
      }
    }
    onStarted: root.pendingAppImages = []
    onExited: root.appImages = root.pendingAppImages
  }

  Timer {
    id: iconIndexDebounce
    interval: 750
    onTriggered: if (!iconIndexScan.running) iconIndexScan.running = true
  }

  FileView {
    path: root.omarchyPath + "/default/omarchy/launcher.hides"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadConfiguredHides(text())
    onFileChanged: root.loadConfiguredHides(text())
    onLoadFailed: root.loadConfiguredHides("")
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() {
      hiddenEntryScan.running = true
      iconIndexDebounce.restart()
      root.appsChanged()
    }
  }

  Component.onCompleted: {
    hiddenEntryScan.running = true
    iconIndexScan.running = true
    appImageScan.running = true
  }
}

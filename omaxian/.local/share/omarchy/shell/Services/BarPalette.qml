pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// omaxian (deltas.md `local`). Commons/Color.qml is mirrored verbatim
// from upstream and exposes only the five foundational roles
// (foreground/background/accent/urgent/muted). The local Bar/widgets/* keep
// per-widget colour coding (mpd green, weather yellow, …) and a handful of
// popup surface roles the generic Ui/ kit doesn't define, so those live here
// instead of polluting the mirrored palette.
//
// Named tokens are read straight from the active theme's colors.toml (same
// file Color.qml loads); everything else is derived from Color's roles. When
// the real plugins/bar lands (Phase 8) with shell.toml surface roles, this
// file folds away.
QtObject {
  id: root

  readonly property string currentThemePath: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme"

  // ---- named colors.toml tokens (fallback = Catppuccin Macchiato) ---------
  property color red: "#ED8796"
  property color orange: "#F5A97F"
  property color yellow: "#EED49F"
  property color green: "#A6DA95"
  property color cyan: "#8BD5CA"
  property color blue: "#8AADF4"
  property color magenta: "#F5BDE6"
  property color brown: "#BE9B7B"
  property color selection: "#494D64"
  property color lighterBackground: "#363A4F"
  property color darkForeground: "#8087A2"

  function loadColors(raw) {
    var lines = String(raw || "").split("\n")
    function grab(name) {
      for (var i = 0; i < lines.length; i++) {
        var m = lines[i].match(new RegExp("^\\s*" + name + "\\s*=\\s*[\"']?(#[0-9A-Fa-f]{6})"))
        if (m) return m[1]
      }
      return ""
    }
    var v
    v = grab("red");                if (v) red = v
    v = grab("orange");             if (v) orange = v
    v = grab("yellow");             if (v) yellow = v
    v = grab("green");              if (v) green = v
    v = grab("cyan");               if (v) cyan = v
    v = grab("blue");               if (v) blue = v
    v = grab("magenta");            if (v) magenta = v
    v = grab("brown");              if (v) brown = v
    v = grab("selection");          if (v) selection = v
    v = grab("lighter_background"); if (v) lighterBackground = v
    v = grab("dark_foreground");    if (v) darkForeground = v
  }

  // Startup + best-effort live reload. omarchy-theme-set swaps the
  // current/theme symlink target atomically; watchChanges catches the write
  // in the common case. A guaranteed live path arrives with the Phase 3 IPC
  // host (omarchy-shell applyTheme).
  property FileView colorsFile: FileView {
    id: colorsFile
    path: root.currentThemePath + "/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadColors(text())
    onFileChanged: reload()
    onLoadFailed: {}
  }

  // ---- bar surface vocabulary (was Color.bar.* pre-Phase-2) --------------
  readonly property color separator: root.selection
  readonly property color menuLogo: Color.accent
  readonly property color chipBackground: root.lighterBackground
  readonly property color mpd: root.green
  readonly property color timer: root.cyan
  readonly property color weather: root.yellow
  readonly property color volume: root.green
  readonly property color bluetooth: root.blue
  readonly property color network: root.cyan
  readonly property color vpnOn: root.green
  readonly property color vpnOff: Color.muted
  readonly property color updates: root.orange
  readonly property color date: root.darkForeground
  readonly property color battery: root.green
  readonly property color power: root.red

  readonly property QtObject workspace: QtObject {
    readonly property color normalBackground: root.lighterBackground
    readonly property color normalText: Color.foreground
    readonly property color hoverBackground: root.selection
    readonly property color hoverText: Color.accent
    readonly property color activeBackground: Color.accent
    readonly property color activeText: Color.background
    readonly property color visibleBackground: root.selection
    readonly property color visibleText: root.cyan
    readonly property color urgentBackground: Color.urgent
    readonly property color urgentText: Color.background
  }

  // ---- popup roles the generic Ui/ kit doesn't define -------------------
  readonly property color popupSubtext: Color.muted
  readonly property color popupInputBackground: root.lighterBackground
  readonly property color popupHeaderAccent: Color.accent
  readonly property color popupHelpKeys: root.cyan
  readonly property color popupWeatherAccent: root.blue
}

// MediaHelper.js - helpers for the omaxian.media popup controller.
// Ported from MrDemonc/Omarchy-media-control (MediaHelper.js), with mpDris2
// (MPD -> MPRIS bridge) added to the native-player / icon / display-name
// tables so MPD reads the same as any other MPRIS source instead of falling
// through the generic "Media Player" fallback.

function normalizeSeconds(val) {
  var n = Number(val) || 0
  if (!isFinite(n) || n <= 0) return 0
  // MPRIS reports length/position in microseconds (> 1,000,000); some
  // bridges (mpDris2 included) already report seconds, so only divide when
  // the magnitude implies microseconds.
  if (n > 1000000) {
    return Math.round(n / 1000000)
  }
  return Math.round(n)
}

function isValidDuration(val) {
  var n = Number(val) || 0
  if (!isFinite(n) || n <= 0) return false
  var sec = normalizeSeconds(n)
  return sec > 5
}

function isWebPlayer(player) {
  if (!player) return false

  var str = (String(player.identity || "") + " " + String(player.desktopEntry || "") + " " + String(player.dbusName || "")).toLowerCase()

  // 1. Explicit native desktop/daemon players that are NEVER web browsers
  if (str.indexOf("spotify") !== -1 ||
      str.indexOf("vlc") !== -1 ||
      str.indexOf("mpv") !== -1 ||
      str.indexOf("amberol") !== -1 ||
      str.indexOf("cider") !== -1 ||
      str.indexOf("audacious") !== -1 ||
      str.indexOf("rhythmbox") !== -1 ||
      str.indexOf("clementine") !== -1 ||
      str.indexOf("strawberry") !== -1 ||
      str.indexOf("elisa") !== -1 ||
      str.indexOf("deadbeef") !== -1 ||
      str.indexOf("lollypop") !== -1 ||
      str.indexOf("quodlibet") !== -1 ||
      str.indexOf("celluloid") !== -1 ||
      str.indexOf("mpd") !== -1 ||
      str.indexOf("music player daemon") !== -1) {
    return false
  }

  // 2. Web browser applications
  if (str.indexOf("firefox") !== -1 ||
      str.indexOf("zen") !== -1 ||
      str.indexOf("chrome") !== -1 ||
      str.indexOf("chromium") !== -1 ||
      str.indexOf("brave") !== -1 ||
      str.indexOf("edge") !== -1 ||
      str.indexOf("opera") !== -1 ||
      str.indexOf("vivaldi") !== -1 ||
      str.indexOf("librewolf") !== -1 ||
      str.indexOf("waterfox") !== -1 ||
      str.indexOf("tor") !== -1 ||
      str.indexOf("epiphany") !== -1 ||
      str.indexOf("safari") !== -1 ||
      str.indexOf("browser") !== -1) {
    return true
  }

  return false
}

function formatTime(seconds) {
  var s = Math.max(0, Math.floor(Number(seconds) || 0))
  var m = Math.floor(s / 60)
  var sec = s % 60
  var h = Math.floor(m / 60)
  m = m % 60

  var secStr = sec < 10 ? "0" + sec : String(sec)
  if (h > 0) {
    var minStr = m < 10 ? "0" + m : String(m)
    return h + ":" + minStr + ":" + secStr
  }
  var minDisplay = m < 10 ? "0" + m : String(m)
  return minDisplay + ":" + secStr
}

function cleanArtUrl(url) {
  if (!url) return ""
  var s = String(url).trim()
  if (s === "") return ""
  if (s.indexOf("file://") === 0 || s.indexOf("http://") === 0 || s.indexOf("https://") === 0 || s.indexOf("qrc:/") === 0) {
    return s
  }
  if (s.indexOf("/") === 0) {
    return "file://" + s
  }
  return s
}

function getEffectiveArtUrl(player) {
  if (!player) return ""

  // 1. Direct player property
  if (player.trackArtUrl && String(player.trackArtUrl).trim() !== "") {
    return cleanArtUrl(player.trackArtUrl)
  }

  // 2. Metadata dictionary (if exposed by Quickshell)
  var webUrl = ""
  if (player.metadata) {
    var m = player.metadata
    if (m["mpris:artUrl"] && String(m["mpris:artUrl"]).trim() !== "") {
      return cleanArtUrl(m["mpris:artUrl"])
    }
    if (m["xesam:url"]) {
      webUrl = String(m["xesam:url"])
    }
  }

  if (!webUrl && player.url) {
    webUrl = String(player.url)
  }

  // 3. Extract thumbnail for YouTube playback in browsers
  if (webUrl) {
    var ytMatch = webUrl.match(/(?:youtu\.be\/|youtube\.com\/(?:embed\/|v\/|watch\?v=|watch\?.+&v=))([\w-]{11})/)
    if (ytMatch && ytMatch[1]) {
      return "https://img.youtube.com/vi/" + ytMatch[1] + "/hqdefault.jpg"
    }
  }

  return ""
}

function isProxyPlayer(player) {
  if (!player) return false
  var dbus = String(player.dbusName || "").toLowerCase()
  var desktop = String(player.desktopEntry || "").toLowerCase()
  return dbus.indexOf("playerctld") !== -1 || desktop === "playerctld"
}

function hasMetadata(player) {
  if (!player) return false
  return !!(player.trackTitle || player.trackArtist || player.identity || player.desktopEntry)
}

function playerKey(player) {
  if (!player) return ""
  return String(player.dbusName || player.desktopEntry || player.identity || "")
}

function playerIcon(player) {
  if (!player) return "󰝚"
  var name = (String(player.identity || "") + " " + String(player.desktopEntry || "") + " " + String(player.dbusName || "")).toLowerCase()
  if (name.indexOf("spotify") !== -1) return "󰓇"
  if (name.indexOf("firefox") !== -1 || name.indexOf("zen") !== -1) return "󰈹"
  if (name.indexOf("chrome") !== -1 || name.indexOf("chromium") !== -1 || name.indexOf("brave") !== -1) return "󰊠"
  if (name.indexOf("vlc") !== -1) return "󰕼"
  if (name.indexOf("mpv") !== -1) return "󰐊"
  if (name.indexOf("amberol") !== -1) return "󰎆"
  if (name.indexOf("cider") !== -1 || name.indexOf("apple") !== -1) return "󰀵"
  if (name.indexOf("youtube") !== -1) return "󰗃"
  if (name.indexOf("discord") !== -1) return "󰙯"
  if (name.indexOf("mpd") !== -1 || name.indexOf("music player daemon") !== -1) return "󰝛"
  return "󰝚"
}

function playerDisplayName(player) {
  if (!player) return "Media Player"
  if (player.identity && player.identity !== "") {
    var id = String(player.identity)
    var idLower = id.toLowerCase()
    if (idLower.indexOf("mozilla zen") !== -1) return "Zen Browser"
    if (idLower.indexOf("mozilla firefox") !== -1) return "Firefox"
    if (idLower.indexOf("music player daemon") !== -1) return "MPD"
    return id
  }
  if (player.desktopEntry && player.desktopEntry !== "") {
    var d = String(player.desktopEntry)
    return d.charAt(0).toUpperCase() + d.slice(1)
  }
  var dbus = String(player.dbusName || "")
  dbus = dbus.replace(/^org\.mpris\.MediaPlayer2\./, "")
  dbus = dbus.replace(/\.instance[0-9_]+$/, "")
  if (dbus.toLowerCase() === "mpd") return "MPD"
  if (dbus) return dbus.charAt(0).toUpperCase() + dbus.slice(1)
  return "Media Player"
}

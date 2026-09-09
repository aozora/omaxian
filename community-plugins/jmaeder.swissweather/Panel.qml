import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "lib/Model.js" as Model
import "lib/Net.js" as Net
import "lib/Places.js" as Places
import "lib/Symbols.js" as Symbols
import "lib/I18n.js" as I18n
import "ui"

// Swiss Weather panel: state, network, and the popup itself.
//
// Everything the plugin knows lives here; BarWidget.qml only owns the button.
// The three data sources are kept distinct throughout, because the difference
// between them is information the user needs:
//
//   measurements  data.geo.admin.ch VQHA80 — what an SMN station recorded,
//                 stamped with the minute it was recorded.
//   forecast      the MeteoSwiss forecast service — what is expected, with the
//                 10-90 % band around it.
//   location      the bundled index, plus at most one geolocation call ever.
//
// A failed refresh never clears what is on screen. Stale MeteoSwiss data with
// a visible timestamp is more useful than an empty panel, and the timestamp is
// what stops it from being misleading.
Panel {
  id: root
  moduleName: "jmaeder.swissweather"
  ipcTarget: "jmaeder.swissweather"
  manageIpc: false

  // --- bar wiring ----------------------------------------------------------

  property var anchorItem: null
  property var hostWidget: null
  property bool openedFromHotkey: false

  // The bar tracks the widget in its slot, not this nested panel, so anything
  // the bar identifies a panel by has to be that widget.
  readonly property var barIdentity: hostWidget || root

  function open() {
    openedFromHotkey = false
    setCenterHoverRevealSuppressed(false)
    root.controller.show()
    root.refresh()
  }

  function openFromHotkey() {
    openedFromHotkey = true
    root.controller.show()
    root.refresh()
    // Set after showing: showing hands over the popout coordinator, which
    // closes whichever panel was open, and that close clears the shared flag.
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
    // Reset to the overview so reopening never lands mid-search with a stale
    // query, but keep the chosen town and language.
    Qt.callLater(function() {
      if (!root.opened) root.showMain()
    })
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    // PluginBarApi exposes a readonly property; mutate via the setter.
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  // --- settings ------------------------------------------------------------

  // Floored at five minutes: this polls federal infrastructure shared by
  // everyone running the plugin, and the underlying data only moves every ten.
  readonly property int refreshMinutes: Math.min(180, Math.max(5, parseInt(setting("refreshMinutes", 15), 10) || 15))
  readonly property bool showTemperature: setting("showTemperature", false) === true
  readonly property bool detectLocation: setting("detectLocation", true) !== false

  // --- paths ---------------------------------------------------------------

  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy/plugins/jmaeder.swissweather"
  readonly property string statePath: stateDir + "/state.json"

  /**
   * Filesystem path of a file shipped inside the plugin directory.
   * Qt.resolvedUrl gives a percent-encoded file:// URL; FileView wants a plain
   * path, so each segment is decoded back.
   */
  function localPath(relative) {
    var url = String(Qt.resolvedUrl(relative))
    if (url.indexOf("file://") !== 0) return ""
    return url.substring(7).split("/").map(decodeURIComponent).join("/")
  }

  // --- persisted state -----------------------------------------------------

  property string language: I18n.defaultLanguage(Qt.locale().name)
  property string units: "metric"
  property var favourites: []
  property string activePointId: ""
  property string detectedPointId: ""
  property bool geoDetected: false
  property bool showWeatherWarnings: true
  property bool showHazardWarnings: true
  property bool notifyWarnings: false
  // Keys of the warnings already notified, so the same one does not pop up at
  // every refresh. Persisted, because the shell restarts often.
  property var seenWarnings: []

  // True while parseState is writing into the properties above, so the change
  // handlers that normally persist an edit stay quiet during a load.
  property bool restoringState: false

  function tr(key) { return I18n.t(root.language, key) }

  // --- units ---------------------------------------------------------------
  //
  // MeteoSwiss publishes metric and the panel converts locally, so switching
  // costs no request and works with the network down. Every displayed number
  // goes through fmt()/fmtRange(), which is what keeps a value and its unit
  // label from ever disagreeing.

  function unitLabel(quantity) {
    var imperial = root.units === "imperial"
    switch (quantity) {
      case "temperature": return tr(imperial ? "unitTemperatureImperial" : "unitTemperature")
      case "precipitation": return tr(imperial ? "unitPrecipitationImperial" : "unitPrecipitation")
      case "speed": return tr(imperial ? "unitWindImperial" : "unitWind")
      case "distance": return tr(imperial ? "unitDistanceImperial" : "unitDistance")
      case "elevation": return tr(imperial ? "unitAltitudeImperial" : "unitAltitude")
      case "sunshine": return tr("unitSunshine")
    }
    return ""
  }

  function conv(value, quantity) { return Model.convert(value, quantity, root.units) }
  function dec(quantity) { return Model.decimalsFor(quantity, root.units) }
  function fmt(value, quantity) { return Model.formatNumber(conv(value, quantity), dec(quantity)) }

  function fmtRange(low, high, quantity) {
    return Model.formatRange(conv(low, quantity), conv(high, quantity), dec(quantity))
  }

  // Smallest value-axis span a chart should show, in whichever unit is
  // active. A fixed 4 would be a sensible temperature window in °C and an
  // absurdly tight one in °F.
  function chartSpan(quantity) {
    var imperial = root.units === "imperial"
    switch (quantity) {
      case "temperature": return imperial ? 7 : 4
      case "precipitation": return imperial ? 0.04 : 1
      case "speed": return imperial ? 6 : 10
    }
    return 10
  }

  function setUnits(value) {
    var next = Model.normalizedUnits(value)
    if (next === root.units) return
    root.units = next
    saveState()
  }

  function setWarningCategory(category, enabled) {
    if (category === "hazard") root.showHazardWarnings = enabled === true
    else root.showWeatherWarnings = enabled === true
    saveState()
  }

  /**
   * Turns desktop notifications on or off.
   *
   * Switching them on marks whatever is already in force as seen, without
   * announcing it. Someone who ticks the box while a storm warning is on
   * screen is not asking to be told about that warning — they are asking about
   * the next one, and a popup repeating what they are already reading would be
   * the first impression of the feature.
   */
  function setNotifyWarnings(enabled) {
    root.notifyWarnings = enabled === true
    if (root.notifyWarnings) markWarningsSeen()
    saveState()
  }

  /** Records every current warning as already announced. */
  function markWarningsSeen() {
    var keys = root.seenWarnings.slice()
    var current = root.forecast ? root.forecast.warnings : []
    for (var i = 0; i < current.length; i++) {
      var key = Model.warningKey(current[i], root.activePointId)
      if (key !== "" && keys.indexOf(key) === -1) keys.push(key)
    }
    root.seenWarnings = keys.slice(-Model.MAX_SEEN_WARNINGS)
  }

  // At most this many popups from one refresh. MeteoSwiss can put half a dozen
  // warnings on one town at once, and six popups in a row is not information,
  // it is a wall — the panel is where the full list belongs.
  readonly property int maxNotificationsPerRefresh: 3

  /**
   * Announces warnings that are new, severe enough, and of a category the user
   * has left switched on.
   *
   * Called after every forecast that parses. Everything it sends is either a
   * literal from this file or MeteoSwiss text that Model has already stripped
   * of control characters and capped in length, and it is handed over as argv
   * — omarchy-notification-send is executed directly, with no shell to quote
   * for. The click command is a constant, never anything built from a warning.
   */
  function notifyNewWarnings() {
    if (!root.notifyWarnings || !root.forecast) return

    var warnings = root.forecast.warnings
    var keys = root.seenWarnings.slice()
    var sent = 0

    for (var i = 0; i < warnings.length; i++) {
      var warning = warnings[i]
      var key = Model.warningKey(warning, root.activePointId)
      if (key === "" || keys.indexOf(key) !== -1) continue

      // Seen is recorded even when the warning is not announced: a level 2
      // warning that is later raised to 3 gets a new key and is announced
      // then, but the same level 2 must not be reconsidered every refresh.
      keys.push(key)

      var wanted = warning.category === "hazard" ? root.showHazardWarnings : root.showWeatherWarnings
      if (!wanted || !Model.isNotifiable(warning)) continue
      if (sent >= root.maxNotificationsPerRefresh) continue

      sendWarningNotification(warning)
      sent++
    }

    root.seenWarnings = keys.slice(-Model.MAX_SEEN_WARNINGS)
    if (sent > 0 || keys.length !== root.seenWarnings.length) saveState()
  }

  // Towns the summary covers: the favourites, or whatever single town is on
  // screen when there are none yet.
  readonly property var summaryPlaces: {
    if (favourites.length > 0) {
      var out = []
      for (var i = 0; i < favourites.length && i < maxSummaryPlaces; i++) {
        var place = Places.byPointId(places, favourites[i].pointId)
        if (place) out.push(place)
      }
      return out
    }
    return activePlace ? [activePlace] : []
  }

  // Enough for anyone's list of towns, short enough that the notification is
  // still something the eye takes in at once rather than a report to read.
  readonly property int maxSummaryPlaces: 8

  /**
   * One line per town: temperature, precipitation, wind, sunshine.
   *
   * Costs no request. The measurements file is the whole SMN network in one
   * download — the panel shows one town's station at a time, but every other
   * town's station is already in memory, so a summary of a dozen towns is free
   * where a dozen forecasts would not be.
   */
  function weatherSummaryRows() {
    var rows = []
    for (var i = 0; i < summaryPlaces.length; i++) {
      var place = summaryPlaces[i]
      var station = Places.selectStation(stations, measurements, place.lat, place.lon,
                                         place.altitude, displayedParameters)
      var reading = station && measurements[station.abbr] ? measurements[station.abbr] : null

      var values = [
        fmt(reading ? reading.tre200s0 : null, "temperature") + " " + unitLabel("temperature"),
        fmt(reading ? reading.rre150z0 : null, "precipitation") + " " + unitLabel("precipitation"),
        fmt(reading ? reading.fu3010z0 : null, "speed") + " " + unitLabel("speed"),
        Model.formatNumber(reading ? reading.sre000z0 : null, 0) + " " + tr("unitSunshine")
      ]
      // The canton disambiguates here more than it does in the panel header:
      // the notification lists several towns at once and gives none of them a
      // map, a postal code or an altitude to be told apart by.
      rows.push({
        name: place.name + (place.canton ? " (" + place.canton + ")" : ""),
        values: values
      })
    }
    return rows
  }

  // The card renders the body in Liberation Sans at the title size
  // (NotificationCard.qml). Measuring in any other font would align nothing, so
  // the layout is given this metric rather than a guess.
  FontMetrics {
    id: summaryMetrics
    font.family: "Liberation Sans"
    font.pixelSize: Style.font.title
  }

  // What a row has to fit in, from the card's own measurements
  // (NotificationCard.qml): 380 points wide, a border on each side, and 12
  // points of margin inside that. Everything is asked of Style rather than
  // assumed, because a reader who sets a larger base font moves all three. The
  // body is capped at three lines, so a row that overruns does not just look
  // wrong — it wraps, and costs a town its place. Hence the point of slack for
  // whatever half-pixel the padding leaves behind.
  readonly property real summaryBodyWidth:
    Style.space(380) - 2 * Math.max(1, Style.space(2)) - 2 * Style.space(12) - 1

  /** The most recent minute any of the summarised stations reported. */
  function summaryTime() {
    var newest = null
    for (var i = 0; i < summaryPlaces.length; i++) {
      var place = summaryPlaces[i]
      var station = Places.selectStation(stations, measurements, place.lat, place.lon,
                                         place.altitude, displayedParameters)
      var reading = station && measurements[station.abbr] ? measurements[station.abbr] : null
      if (!reading || !reading.time) continue
      if (newest === null || reading.time.getTime() > newest.getTime()) newest = reading.time
    }
    return newest
  }

  /**
   * Sends the summary as a desktop notification.
   *
   * Deliberately unconditional: this one is asked for by a keypress, so the
   * tick that governs warning popups — which arrive uninvited — has nothing to
   * say about it.
   */
  function sendWeatherSummary() {
    var lines = Model.summaryTable(weatherSummaryRows(),
                                   function(text) { return summaryMetrics.advanceWidth(text) },
                                   summaryBodyWidth)
    var when = summaryTime()
    var headline = tr("summaryTitle") + (when !== null ? " · " + Model.formatClock(when) : "")

    Quickshell.execDetached([
      "omarchy-notification-send",
      "--app-name", "Swiss Weather",
      // No glyph. One weather symbol for a list of several towns could only be
      // one town's, and the icon slot costs 52 of the notification card's 380
      // points — enough that every town's line wraps and the card's three-line
      // body shows two towns instead of three.
      "-u", "low",
      headline,
      lines.length > 0 ? lines.join("\n") : tr("neverLoaded"),
      // The click command, as separate words and last: omarchy-notification-send
      // reads everything after --exec as the argv, so the headline and the body
      // have to be given before it, and a command passed as one quoted string
      // is refused.
      "--exec", "omarchy-shell", "jmaeder.swissweather", "toggle"
    ])
  }

  function sendWarningNotification(warning) {
    var town = root.activePlace ? root.activePlace.name : ""
    var headline = (town !== "" ? town + " · " : "") + warningTitle(warning)

    var validity = warningValidity(warning)
    var body = warning.lines.length > 0
      ? (warning.lines[0].label !== ""
         ? warning.lines[0].label + ": " + warning.lines[0].value
         : warning.lines[0].value)
      : ""
    var description = validity !== "" ? (body !== "" ? validity + " — " + body : validity) : body

    Quickshell.execDetached([
      "omarchy-notification-send",
      "--app-name", "Swiss Weather",
      // nf-fa-warning. A weather symbol would say what the sky is doing; this
      // says something is wrong, which is the point of the popup.
      "-g", "\uf071",
      "-u", warning.level >= 4 ? "critical" : "normal",
      headline,
      description,
      // Literal words, so that no part of a warning can ever become a command,
      // and last, because omarchy-notification-send reads everything after
      // --exec as the click command's argv.
      "--exec", "omarchy-shell", "jmaeder.swissweather", "toggle"
    ])
  }

  /** Warnings the user has asked to see, in the order MeteoSwiss sent them. */
  readonly property var visibleWarnings: {
    if (!forecast) return []
    var out = []
    for (var i = 0; i < forecast.warnings.length; i++) {
      var warning = forecast.warnings[i]
      var wanted = warning.category === "hazard" ? showHazardWarnings : showWeatherWarnings
      if (wanted) out.push(warning)
    }
    return out
  }

  /**
   * The visible warnings as a flat list ready to render, grouped by category.
   *
   * The two categories come mixed in one array from MeteoSwiss, and the panel
   * has a tick for each, so showing them mixed left "Natural hazards" as a
   * label on a checkbox and nothing else — a fire-danger warning looked like
   * one more weather line. Each entry carries the group header to draw above
   * it, empty for every entry but the first of its group.
   */
  readonly property var warningItems: {
    var out = []
    var groups = [
      { category: "weather", header: tr("weatherWarnings") },
      { category: "hazard", header: tr("naturalHazards") }
    ]
    for (var g = 0; g < groups.length; g++) {
      var first = true
      for (var i = 0; i < visibleWarnings.length; i++) {
        if (visibleWarnings[i].category !== groups[g].category) continue
        out.push({
          index: out.length,
          header: first ? groups[g].header : "",
          warning: visibleWarnings[i]
        })
        first = false
      }
    }
    return out
  }

  /** "Forest fire · Level 4 · High danger", as much of it as is known. */
  function warningTitle(warning) {
    var name = I18n.hazardName(language, warning.hazard)
    if (warning.level === null) return name
    var meaning = I18n.dangerLevelName(language, warning.level)
    return name + " · " + tr("dangerLevel") + " " + warning.level
      + (meaning !== "" ? " · " + meaning : "")
  }

  /**
   * The colours MeteoSwiss publishes for the five danger levels — green,
   * yellow, orange, red, dark red. The one place the panel leaves its
   * monochrome palette, because the level *is* a colour in the source: this is
   * the same encoding the warning map uses, and a reader who knows orange
   * knows what it means without reading a word.
   */
  function warningLevelColor(level) {
    var colours = ["green", "gold", "orange", "red", "darkred"]
    if (level === null || level < 1 || level > 5) return Qt.darker(fg, 1.6)
    return colours[Math.round(level) - 1]
  }

  /**
   * When a warning applies: "Thu 20.08 14:00 → Fri 21.08 14:00", or one end of
   * it when the service gives only one. A warning without its period is just a
   * paragraph about the weather; with it, the reader knows whether it is about
   * this afternoon or about tomorrow night.
   */
  function warningMoment(ms, withDate) {
    var date = new Date(ms)
    var clock = Model.formatClock(date)
    if (!withDate) return clock
    return I18n.weekday(language, date) + " " + Model.formatDayMonth(date) + " " + clock
  }

  function warningValidity(warning) {
    var hasFrom = warning.from !== null && warning.from !== undefined
    var hasTo = warning.to !== null && warning.to !== undefined
    if (hasFrom && hasTo) {
      // The end date is dropped when it falls on the start's day: "Thu 20.08
      // 14:00 → 22:00" says the same thing in half the width.
      var sameDay = Model.startOfDay(new Date(warning.from)).getTime()
        === Model.startOfDay(new Date(warning.to)).getTime()
      return warningMoment(warning.from, true) + " → " + warningMoment(warning.to, !sameDay)
    }
    if (hasTo) return tr("warningUntil") + " " + warningMoment(warning.to, true)
    if (hasFrom) return tr("warningFrom") + " " + warningMoment(warning.from, true)
    return ""
  }

  /**
   * One line of a warning body as rich text: the label MeteoSwiss put in front
   * of it in bold, the rest as written. Both halves come from the network and
   * both are escaped — see Model.escapeMarkup for why that is enough.
   */
  function warningLineText(line) {
    var value = Model.escapeMarkup(line.value)
    if (line.label === "") return value
    return "<b>" + Model.escapeMarkup(line.label) + "</b> " + value
  }

  function loadState(raw) {
    restoringState = true
    var state = Model.parseState(raw, I18n.LANGUAGES)

    // Precedence: what the user picked in the panel, then the shell.json
    // setting, then the system locale. The panel selector writes the state
    // file, so a choice made here outlives a shell.json default.
    var configured = I18n.normalize(setting("language", ""))
    root.language = state.language !== "" ? state.language
      : (String(setting("language", "")) !== "" ? configured : I18n.defaultLanguage(Qt.locale().name))

    root.units = state.units
    root.favourites = state.favourites
    root.activePointId = state.activePointId
    root.detectedPointId = state.detectedPointId
    root.geoDetected = state.geoDetected
    root.showWeatherWarnings = state.showWeatherWarnings
    root.showHazardWarnings = state.showHazardWarnings
    root.notifyWarnings = state.notifyWarnings
    root.seenWarnings = state.seenWarnings

    // Migration for state files written before the detected town was recorded
    // separately: detection had already run, so the town on screen is the best
    // available answer for where it put us. Costs no request, and stops the
    // "remove every favourite" path from dropping those users in Bern.
    if (root.geoDetected && root.detectedPointId === "" && root.activePointId !== "")
      root.detectedPointId = root.activePointId

    restoringState = false

    resolveStartingLocation()
  }

  function saveState() {
    if (restoringState) return
    saveDebounce.restart()
  }

  function flushState() {
    stateFile.setText(JSON.stringify(Model.serializeState({
      language: root.language,
      units: root.units,
      favourites: root.favourites,
      activePointId: root.activePointId,
      detectedPointId: root.detectedPointId,
      geoDetected: root.geoDetected,
      showWeatherWarnings: root.showWeatherWarnings,
      showHazardWarnings: root.showHazardWarnings,
      notifyWarnings: root.notifyWarnings,
      seenWarnings: root.seenWarnings
    }), null, 2) + "\n")
  }

  Timer {
    id: saveDebounce
    interval: 250
    repeat: false
    onTriggered: root.flushState()
  }

  // mkdir before the first write: FileView will not create the directory, and
  // a fixed argv array built from $HOME leaves nothing to inject into.
  Process {
    id: ensureStateDirProc
    command: ["mkdir", "-p", root.stateDir]
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.loadState(text())
    // First run: no file yet. Loading the empty state anyway is what gets the
    // defaults applied and the starting town resolved.
    onLoadFailed: root.loadState("")
  }

  // --- bundled indexes -----------------------------------------------------

  property var places: []
  property var stations: []
  property var webcams: []
  property var forecastPages: ({})

  FileView {
    id: placesFile
    path: root.localPath("data/places.csv")
    watchChanges: false
    printErrors: false
    onLoaded: {
      root.places = Places.parsePlaces(text())
      root.resolveStartingLocation()
    }
    onLoadFailed: root.places = []
  }

  FileView {
    id: forecastPagesFile
    path: root.localPath("data/forecast-pages.csv")
    watchChanges: false
    printErrors: false
    onLoaded: root.forecastPages = Places.parseForecastPages(text())
    onLoadFailed: root.forecastPages = ({})
  }

  FileView {
    id: stationsFile
    path: root.localPath("data/stations.csv")
    watchChanges: false
    printErrors: false
    onLoaded: root.stations = Places.parseStations(text())
    onLoadFailed: root.stations = []
  }

  FileView {
    id: webcamsFile
    path: root.localPath("data/webcams.csv")
    watchChanges: false
    printErrors: false
    onLoaded: root.webcams = Places.parseWebcams(text())
    onLoadFailed: root.webcams = []
  }

  // --- location ------------------------------------------------------------

  // Bern 3011 — the postal code that covers the Federal Palace, 184 m from
  // the building. Used when detection is switched off, when it fails, and when
  // it places the user outside Switzerland and Liechtenstein: every forecast
  // point this plugin can address is in those two countries, so for anywhere
  // else there is no honest answer, and the seat of the Confederation is the
  // least arbitrary way to say "somewhere in Switzerland" while the user picks
  // their own town.
  readonly property string fallbackPointId: "301100"

  // One detection attempt per shell session at most, on top of the persisted
  // "already detected" flag. A first run with the network down retries next
  // session rather than being written off forever.
  property bool geoAttempted: false

  readonly property var activePlace: Places.byPointId(places, activePointId)

  // The quantities the panel puts on screen, in the order they appear. Passed
  // to selectStation so the station chosen is one that is actually reporting
  // them — see the rationale there; roughly half the SMN network publishes no
  // precipitation, and any station can go quiet for a refresh.
  readonly property var displayedParameters: ["tre200s0", "rre150z0", "fu3010z0", "sre000z0"]

  // Empty for the Liechtenstein towns MeteoSwiss also covers, which are in no
  // canton, and for a handful of postal codes the register no longer lists.
  readonly property string activeCanton: activePlace && activePlace.canton
    ? activePlace.canton : ""

  // The MeteoSwiss weather cam nearest the selected town, or null. Only its
  // name, distance and page are used — see Net.webcamPageUrl for why the
  // picture itself is never fetched.
  readonly property var activeWebcam: activePlace
    ? Places.nearestWebcam(webcams, activePlace.lat, activePlace.lon) : null

  readonly property string activeWebcamUrl: activeWebcam
    ? Net.webcamPageUrl(activeWebcam.abbr, language) : ""

  // The map applications a MeteoSwiss town page links to at the bottom, in the
  // order that page lists them.
  readonly property var mapLinks: [
    { key: "precipitation", label: tr("mapPrecipitation") },
    { key: "clouds", label: tr("mapClouds") },
    { key: "wind", label: tr("mapWind") },
    { key: "hazards", label: tr("mapHazards") }
  ]

  readonly property var activeStation: activePlace
    ? Places.selectStation(stations, measurements, activePlace.lat, activePlace.lon,
                           activePlace.altitude, displayedParameters)
    : null

  readonly property bool activeIsFavourite: Model.indexOfPoint(favourites, activePointId) !== -1

  /**
   * MeteoSwiss's own page for this town, in the panel's language, or "" when
   * there is none. Empty for the handful of postal codes that address a PO box
   * rather than a place — the link is then hidden rather than pointed at a 404.
   */
  readonly property string activePageUrl: activePlace
    ? Net.localForecastUrl(activePlace.plz,
                           Places.pageSlug(forecastPages, activePlace.plz, language),
                           language)
    : ""

  /**
   * Decides which town to show. Called whenever the pieces it depends on
   * arrive — the index, the state file — because they land in either order.
   */
  function resolveStartingLocation() {
    if (places.length === 0) return
    if (activePointId !== "" && Places.byPointId(places, activePointId)) return

    if (favourites.length > 0) {
      setActivePoint(favourites[0].pointId)
      return
    }
    if (detectedPointId !== "" && Places.byPointId(places, detectedPointId)) {
      setActivePoint(detectedPointId)
      return
    }
    if (detectLocation && !geoDetected && !geoAttempted) {
      startDetection()
      return
    }
    setActivePoint(fallbackPointId)
  }

  function startDetection() {
    geoAttempted = true
    if (geoipProc.running) return
    var command = Net.geoipCommand()
    if (command === null) {
      setActivePoint(fallbackPointId)
      return
    }
    detecting = true
    geoipProc.command = command
    geoipProc.running = true
  }

  property bool detecting: false

  function applyDetection(raw) {
    detecting = false
    var detected = Model.parseGeoip(raw)
    if (detected === null) {
      // Leave geoDetected false so a later session can try again, and show
      // something in the meantime.
      setActivePoint(fallbackPointId)
      return
    }

    geoDetected = true

    // An address abroad still gets a Swiss town when it is close enough to the
    // border for that town to describe the same sky — Annemasse reads Geneva's
    // weather, Konstanz reads Kreuzlingen's. Past the limit in Places there is
    // no such town, and the default is the honest answer.
    var limit = detected.covered ? Infinity : Places.MAX_BORDER_DISTANCE_KM
    var nearest = Places.nearestPlaceWithin(places, detected.latitude, detected.longitude, limit)

    root.detectedPointId = nearest ? nearest.pointId : ""
    setActivePoint(nearest ? nearest.pointId : fallbackPointId)
    saveState()
  }

  function setActivePoint(pointId) {
    if (!Net.isPointId(pointId)) return

    // Re-selecting the town already shown is a no-op only when its data is
    // actually here. Removing a favourite and adding it straight back lands on
    // the same id with the forecast already cleared, and returning early there
    // left the panel permanently blank.
    if (root.activePointId === pointId && root.forecast !== null) return

    root.activePointId = pointId
    // Drop the previous town's forecast rather than showing it under the new
    // name for the second before the response lands.
    root.forecast = null
    root.forecastFailed = false
    root.forecastRetries = 0
    saveState()
    refreshForecast()
  }

  function cycleFavourite() {
    if (favourites.length === 0) return
    var index = Model.indexOfPoint(favourites, activePointId)
    setActivePoint(favourites[(index + 1) % favourites.length].pointId)
  }

  function addFavourite(place) {
    if (!place) return
    if (Model.indexOfPoint(favourites, place.pointId) !== -1) return
    // Model.MAX_FAVOURITES is a corrupt-file guard, not a product limit; the
    // panel does not stop the user at any particular number of towns.
    if (favourites.length >= Model.MAX_FAVOURITES) return
    var next = favourites.slice()
    next.push({ pointId: place.pointId, plz: place.plz, name: place.name, lat: place.lat, lon: place.lon })
    favourites = next
    saveState()
  }

  function removeFavourite(pointId) {
    var index = Model.indexOfPoint(favourites, pointId)
    if (index === -1) return
    var next = favourites.slice()
    next.splice(index, 1)
    favourites = next
    saveState()

    if (activePointId !== pointId) return

    // Removing the town on screen has to leave something on screen. The next
    // favourite if there is one, otherwise back to where detection put us —
    // which is the same state as a fresh install, and the reason
    // detectedPointId is remembered separately from the active town.
    if (next.length > 0) {
      setActivePoint(next[0].pointId)
      return
    }

    // No favourites left. Go back to where detection put us; if detection has
    // never successfully run, run it now — clearing every town is the user
    // asking for the unconfigured behaviour back. If it has run and we simply
    // do not know its answer, fall back rather than ask again: the README
    // promises at most one geolocation request ever, and that promise is worth
    // more than landing on the right city.
    if (detectedPointId !== "" && Places.byPointId(places, detectedPointId)) {
      setActivePoint(detectedPointId)
      return
    }
    if (detectLocation && !geoDetected && !geoAttempted) {
      startDetection()
      return
    }
    setActivePoint(fallbackPointId)
  }

  function setLanguage(value) {
    var next = I18n.normalize(value)
    if (next === root.language) return
    root.language = next
    saveState()
    // Warning texts come back translated, so the language change needs a
    // refetch to take effect on them.
    refreshForecast()
  }

  // --- live data -----------------------------------------------------------

  property var forecast: null
  property var measurements: ({})
  property bool forecastFailed: false
  property bool measurementsFailed: false
  property int forecastRetries: 0
  property int measurementRetries: 0

  readonly property var stationReading: (activeStation && measurements[activeStation.abbr])
    ? measurements[activeStation.abbr] : null

  readonly property var currentConditions: forecast && forecast.current ? forecast.current : null
  readonly property var graph: forecast && forecast.graph ? forecast.graph : null

  // Whole hour containing "now", which is the grid every published series sits
  // on and therefore the hour whose forecast band belongs beside the reading.
  //
  // This is a stored property rather than a binding on Date.now(): a binding
  // would be evaluated once and then never again, leaving the panel showing
  // yesterday's chart after midnight. The timer below advances it, and only
  // when the hour actually rolls over, so the derived series are rebuilt
  // hourly rather than every tick.
  property real currentHourMs: Math.floor(Date.now() / Model.HOUR_MS) * Model.HOUR_MS

  readonly property real todayStartMs: Model.startOfDay(new Date(currentHourMs)).getTime()
  readonly property real todayEndMs: todayStartMs + 24 * Model.HOUR_MS

  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: {
      var hour = Math.floor(Date.now() / Model.HOUR_MS) * Model.HOUR_MS
      if (hour !== root.currentHourMs) root.currentHourMs = hour
    }
  }

  function bandAt(minSeries, maxSeries) {
    if (!graph) return null
    var low = Model.valueAt(minSeries, currentHourMs)
    var high = Model.valueAt(maxSeries, currentHourMs)
    if (low === null && high === null) return null
    return { low: low, high: high }
  }

  readonly property var temperatureBand: graph ? bandAt(graph.temperatureMin, graph.temperatureMax) : null
  readonly property var windBand: graph ? bandAt(graph.windQ10, graph.windQ90) : null
  readonly property var precipitationHour: graph
    ? (Model.hourlyPrecipitation(graph, currentHourMs, currentHourMs + Model.HOUR_MS)[0] || null) : null
  readonly property var sunshineForecast: graph ? Model.valueAt(graph.sunshine, currentHourMs) : null

  /**
   * The temperature to show, and where it came from.
   *
   * The station is preferred because it is a measurement, but stations do fall
   * silent — so the forecast service's current value is the fallback. Both the
   * hero and the temperature cell read this one property: showing 24.2 in the
   * hero while the cell underneath showed a dash, because one had a fallback
   * and the other did not, is exactly the kind of quiet contradiction that
   * makes a panel untrustworthy.
   */
  readonly property var currentTemperature: {
    if (stationReading && stationReading.tre200s0 !== null)
      return { value: stationReading.tre200s0, fromStation: true }
    if (currentConditions && currentConditions.temperature !== null)
      return { value: currentConditions.temperature, fromStation: false }
    return null
  }

  // --- bar output ----------------------------------------------------------

  readonly property string barSymbol: {
    if (currentConditions && currentConditions.icon !== null) return Symbols.glyph(currentConditions.icon)
    // Only claim "no data" once a fetch has actually come back empty;
    // before that the widget stays hidden rather than flashing an error.
    if (forecastFailed) return Symbols.GLYPH_UNKNOWN
    return ""
  }

  readonly property string barLabel: {
    if (!showTemperature) return ""
    var temperature = stationReading ? stationReading.tre200s0
      : (currentConditions ? currentConditions.temperature : null)
    if (temperature === null || temperature === undefined) return ""
    return Math.round(temperature) + "°"
  }

  // --- network -------------------------------------------------------------

  function refresh() {
    forecastRetries = 0
    measurementRetries = 0
    refreshMeasurements()
    refreshForecast()
  }

  function refreshMeasurements() {
    if (measurementsProc.running) return
    var command = Net.measurementsCommand()
    if (command === null) return
    measurementsProc.command = command
    measurementsProc.running = true
  }

  // Point id the in-flight forecast request was issued for. Two things depend
  // on it, and both were wrong without it:
  //
  //   - a request already running for another town must be abandoned, not
  //     waited on. `refreshForecast` used to return early whenever the process
  //     was busy, so switching town mid-fetch cleared the panel and then never
  //     re-requested — blank until the refresh timer came round minutes later.
  //   - a response that arrives after the user has moved on must be dropped.
  //     Without the check, town A's forecast lands and is displayed under
  //     town B's name, which is worse than showing nothing.
  property string forecastRequestId: ""

  function refreshForecast() {
    if (!Net.isPointId(activePointId)) return
    if (forecastProc.running) {
      if (forecastRequestId === activePointId) return
      forecastProc.running = false // abandon the request for the old town
    }
    var command = Net.forecastCommand(activePointId, root.language)
    if (command === null) return
    forecastRequestId = activePointId
    forecastProc.command = command
    forecastProc.running = true
  }

  // Retries are few and spaced: a refresh that fails is almost always the
  // network being away, and hammering a federal endpoint through an outage
  // helps nobody. The periodic timer picks it up regardless.
  function retryDelay(attempt) {
    return Math.min(30000, 2500 * Math.pow(2, attempt))
  }

  Process {
    id: measurementsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseMeasurements(text)
        var count = 0
        for (var key in parsed) { count++; break }
        if (count === 0) {
          root.measurementsFailed = true
          if (root.measurementRetries < 3) {
            measurementRetryTimer.interval = root.retryDelay(root.measurementRetries)
            root.measurementRetries++
            measurementRetryTimer.restart()
          }
          return
        }
        root.measurements = parsed
        root.measurementsFailed = false
        root.measurementRetries = 0
      }
    }
  }

  Timer {
    id: measurementRetryTimer
    repeat: false
    onTriggered: root.refreshMeasurements()
  }

  Process {
    id: forecastProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // Late response for a town the user has already left.
        if (root.forecastRequestId !== root.activePointId) return

        var parsed = Model.parseForecast(text)
        if (!parsed.valid || parsed.current === null) {
          root.forecastFailed = true
          if (root.forecastRetries < 3) {
            forecastRetryTimer.interval = root.retryDelay(root.forecastRetries)
            root.forecastRetries++
            forecastRetryTimer.restart()
          }
          return
        }
        root.forecast = parsed
        root.forecastFailed = false
        root.forecastRetries = 0
        root.notifyNewWarnings()
      }
    }
  }

  Timer {
    id: forecastRetryTimer
    repeat: false
    onTriggered: root.refreshForecast()
  }

  Process {
    id: geoipProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyDetection(text)
    }
  }

  Timer {
    id: refreshTimer
    interval: root.refreshMinutes * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: ensureStateDirProc.running = true

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.openFromHotkey() }
    function close(): void { root.close() }
    function show(): void { root.openFromHotkey() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
    function next(): void { root.cycleFavourite() }

    // Open straight to one chart, so a keybind can go from nothing on screen
    // to the wind forecast in one press.
    function today(): void { root.openFromHotkey(); root.showDetail("today") }
    function week(): void { root.openFromHotkey(); root.showDetail("week") }
    function wind(): void { root.openFromHotkey(); root.showDetail("wind") }

    // A glance without a panel: one notification with the current readings for
    // every favourite. Omarchy's own weather widget answers SUPER CTRL ALT W
    // that way, and someone who replaced it with this plugin should not lose
    // the habit — see the README for the one-line rebind.
    function summary(): void { root.sendWeatherSummary() }
  }

  // --- view state ----------------------------------------------------------

  // "main" is the overview, "search" the town picker, "detail" the charts.
  property string view: "main"

  // The keyboard is the quickest way through this panel and nothing on screen
  // said so, which is the same as not having it. `h` — and the key cap in the
  // corner, for whoever never presses an unknown key — puts the list on top of
  // whichever view is open, over it rather than in it: it is a reminder, not a
  // place you navigate to.
  property bool helpOpen: false

  readonly property var helpRows: [
    { keys: "Enter", label: tr("helpSearch") },
    { keys: "1 … 9", label: tr("helpFavourite") },
    { keys: "1 2", label: tr("helpChartTabs") },
    { keys: "Tab", label: tr("helpPanels") },
    { keys: "Esc", label: tr("helpBack") },
    { keys: "h", label: tr("helpKeys") }
  ]
  property string detailTab: "today"
  property var searchResults: []
  property int searchIndex: 0

  function showMain() {
    view = "main"
    helpOpen = false
    searchResults = []
    if (searchField) searchField.text = ""
  }

  function showSearch() {
    view = "search"
    searchResults = []
    searchIndex = 0
    Qt.callLater(function() {
      if (!root.searchField) return
      root.searchField.text = ""
      root.searchField.forceActiveFocus()
    })
  }

  // Chart tabs a digit can reach, in the order they are shown. The wind view
  // is not among them: it has no tab of its own, being opened by clicking the
  // wind reading, and giving it a number would put back the second route into
  // it that the tab removal was meant to close.
  readonly property var digitTabs: ["today", "week"]

  /**
   * Digit shortcuts: a town on the main view, a chart tab in the detail view.
   *
   * The same keys do different things in the two views because in each one
   * they address what is on screen — the strip of towns, or the row of tabs.
   * The digits are not printed on the chips: a number in front of every town
   * is a permanent cost paid for something learned once, and the strip has to
   * stay readable as a list of places. 1 to 9 count the favourites, in their
   * own order — the detected town, which is not a favourite, has no number and
   * is already the one on screen.
   * Nothing else in the panel answers to a digit, so there is nothing for them
   * to collide with. Search is not affected: the key catcher is blocked while
   * the search field has the keyboard, or typing "1204" would switch town four
   * times instead of finding Genève.
   */
  function handleDigit(text) {
    if (String(text).length !== 1 || text < "1" || text > "9") return
    var index = parseInt(text, 10) - 1

    if (view === "detail") {
      if (index < digitTabs.length) detailTab = digitTabs[index]
      return
    }
    if (view !== "main") return
    if (index < favourites.length) setActivePoint(favourites[index].pointId)
  }

  function showDetail(tab) {
    detailTab = tab
    view = "detail"
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function runSearch() {
    searchResults = Places.search(places, searchField ? searchField.text : "")
    searchIndex = 0
  }

  function pickSearchResult(place) {
    if (!place) return
    addFavourite(place)
    setActivePoint(place.pointId)
    showMain()
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  /**
   * Hands one of the plugin's published documentation pages to the browser.
   *
   * Net.openCommand re-checks the URL against its own literal table and
   * returns null for anything else, so this cannot be turned into a general
   * "open whatever" by a later edit. execDetached takes argv, so there is no
   * shell in the path either.
   */
  function openLink(url) {
    var command = Net.openCommand(url)
    if (command === null) return
    Quickshell.execDetached(command)
  }

  // --- colours -------------------------------------------------------------

  readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
  readonly property color accentColor: Color.accent
  readonly property string uiFont: root.bar ? root.bar.fontFamily : Style.font.family

  // --- popup ---------------------------------------------------------------

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(520))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // The search field owns the keyboard while it is focused, otherwise j/k
      // would drive the panel cursor instead of typing a town name.
      blocked: root.view === "search"
      onCloseRequested: {
        if (root.helpOpen) root.helpOpen = false
        else if (root.view === "main") root.close()
        else root.showMain()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onReturnRequested: if (root.view === "main") root.showSearch()
      onTextKey: function(text) { if (!root.helpOpen) root.handleDigit(text) }

      // h never reaches onTextKey: PanelKeyCatcher reads h/j/k/l as arrows, the
      // vim habit every Omarchy panel honours, and accepts the key before any
      // handler here runs. Keys.forwardTo is looked at first, which is the one
      // place a panel can claim a letter the catcher has already spoken for —
      // and the only key claimed is h, so left/right still mean what they mean
      // everywhere else.
      Keys.forwardTo: [helpKey]

      Item {
        id: helpKey
        Keys.onPressed: function(event) {
          // Forwarding happens whatever the catcher is doing, so the search
          // field has to be excluded by hand: a town whose name starts with h
          // must be typeable.
          if (event.text !== "h" || root.view === "search") return
          root.helpOpen = !root.helpOpen
          event.accepted = true
        }
      }

      Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        // Same reasoning as the warnings box: the panel is capped to the
        // screen, so on a short screen there is already more content than
        // shows, and nothing said so.
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: content
          width: scroll.width
          spacing: Style.space(12)

          // ---------------------------------------------------- header

          Item {
            width: parent.width
            height: Math.max(title.implicitHeight, helpHint.implicitHeight)

            Row {
              id: title
              anchors.left: parent.left
              anchors.leftMargin: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)

              Text {
                visible: root.view !== "main"
                text: "" // nf-fa-chevron_left
                color: Qt.darker(root.fg, 1.4)
                font.family: root.uiFont
                font.pixelSize: Style.font.bodySmall
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText

                HoverHandler { cursorShape: Qt.PointingHandCursor }
                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -Style.space(6)
                  onClicked: root.showMain()
                }
              }

              // The Swiss flag, in its standard square format, drawn in the
              // theme's own colours rather than the national red: the panel is
              // monochrome, and a saturated flag beside dimmed small caps
              // would pull the eye away from the town name it introduces.
              SwissCross {
                width: Style.font.body
                height: width
                anchors.verticalCenter: parent.verticalCenter
                groundColor: Qt.darker(root.fg, 1.4)
                crossColor: Color.popups.background
                halo: false
              }

              Text {
                text: root.activePlace ? root.activePlace.name.toUpperCase()
                  : (root.detecting ? root.tr("locating") : root.tr("loading"))
                color: Qt.darker(root.fg, 1.3)
                font.family: root.uiFont
                font.pixelSize: Style.font.body
                font.letterSpacing: 1
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
              }

              // The canton, in the official two-letter form. That form is the
              // same in all three languages — ZH, VD, GR are codes, not words —
              // so nothing here changes when the panel language does, which is
              // exactly what makes it usable as a disambiguator: Switzerland
              // has several towns of the same name and the canton is how one
              // is told from another.
              Text {
                visible: root.activeCanton !== ""
                text: "(" + root.activeCanton + ")"
                color: Qt.darker(root.fg, 1.55)
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
              }

              Text {
                visible: root.activePlace !== null
                text: root.activePlace ? root.activePlace.plz : ""
                color: Qt.darker(root.fg, 1.8)
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
              }

              // Altitude belongs next to the name here more than it would
              // anywhere else: in Switzerland it is the single number that
              // explains why two towns twenty minutes apart read differently.
              Text {
                visible: root.activePlace !== null && root.activePlace.altitude !== null
                text: root.activePlace && root.activePlace.altitude !== null
                  ? root.fmt(root.activePlace.altitude, "elevation") + " " + root.unitLabel("elevation")
                  : ""
                color: Qt.darker(root.fg, 1.8)
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
              }
            }

            // The header's right half is empty, which makes it the one place a
            // hint can sit without competing with anything. It names the key
            // rather than offering a "?": the point is to teach the shortcut,
            // and someone who would rather click still can.
            KeyCap {
              id: helpHint
              anchors.right: parent.right
              anchors.rightMargin: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              label: "h"
              foreground: root.fg
              fontFamily: root.uiFont
              opacity: root.helpOpen || helpKeyHover.hovered ? 1 : 0.55
              Behavior on opacity { NumberAnimation { duration: 120 } }

              HoverHandler { id: helpKeyHover; cursorShape: Qt.PointingHandCursor }
              MouseArea {
                anchors.fill: parent
                anchors.margins: -Style.space(4)
                onClicked: root.helpOpen = !root.helpOpen
              }
            }
          }

          // ---------------------------------------------------- favourites

          Flow {
            width: parent.width - Style.space(8)
            x: Style.space(4)
            visible: root.view === "main"
            spacing: Style.space(6)

            // The detected town appears alongside the favourites without
            // being one, marked with a pin and offering to be pinned.
            PlaceChip {
              visible: root.activePlace !== null && !root.activeIsFavourite
              label: root.activePlace ? root.activePlace.name : ""
              glyph: ""
              selected: true
              removable: false
              foreground: root.fg
              accent: root.accentColor
              fontFamily: root.uiFont
              onActivated: root.addFavourite(root.activePlace)
            }

            Repeater {
              model: root.favourites

              PlaceChip {
                required property var modelData
                label: modelData.name
                selected: modelData.pointId === root.activePointId
                foreground: root.fg
                accent: root.accentColor
                fontFamily: root.uiFont
                onActivated: root.setActivePoint(modelData.pointId)
                onRemoveRequested: root.removeFavourite(modelData.pointId)
              }
            }

            PlaceChip {
              label: "+"
              removable: false
              foreground: root.fg
              accent: root.accentColor
              fontFamily: root.uiFont
              onActivated: root.showSearch()
            }
          }

          // ---------------------------------------------------- search view

          Loader {
            width: parent.width
            active: root.view === "search"
            visible: active
            sourceComponent: searchView
          }

          // ---------------------------------------------------- main view

          Loader {
            width: parent.width
            active: root.view === "main"
            visible: active
            sourceComponent: mainView
          }

          // ---------------------------------------------------- detail view

          Loader {
            width: parent.width
            active: root.view === "detail"
            visible: active
            sourceComponent: detailView
          }

          // ---------------------------------------------------- footer

          PanelSeparator { foreground: root.fg }

          // What the panel shows, and — set apart on the right — what leaves
          // it. The two category ticks decide what appears a few lines above;
          // the third puts a warning on the screen whether the panel is open
          // or not, which is a different kind of permission and should not
          // read as a third member of the same list.
          Item {
            width: parent.width
            height: Math.max(categoryTicks.implicitHeight, notifyTick.implicitHeight)

            Row {
              id: categoryTicks
              anchors.left: parent.left
              anchors.leftMargin: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              TickBox {
                label: root.tr("weatherWarnings")
                checked: root.showWeatherWarnings
                foreground: root.fg
                accent: root.accentColor
                fontFamily: root.uiFont
                onToggled: function(value) { root.setWarningCategory("weather", value) }
              }

              TickBox {
                label: root.tr("naturalHazards")
                checked: root.showHazardWarnings
                foreground: root.fg
                accent: root.accentColor
                fontFamily: root.uiFont
                onToggled: function(value) { root.setWarningCategory("hazard", value) }
              }
            }

            TickBox {
              id: notifyTick
              anchors.right: parent.right
              anchors.rightMargin: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              label: root.tr("notifications")
              checked: root.notifyWarnings
              foreground: root.fg
              accent: root.accentColor
              fontFamily: root.uiFont
              onToggled: function(value) { root.setNotifyWarnings(value) }
            }
          }

          // Last line of the panel: language, units, attribution. Below the
          // ticks rather than above them, because it is the line that says
          // what this panel is and where its numbers come from — read once,
          // then ignored — while the ticks are controls someone comes back to.
          //
          // The controls run from the left and the attribution is pinned to
          // the right, with the slack between them. Laying all three out from
          // the left instead needs about seventy pixels more than the panel
          // has, and the attribution wraps to a line of its own.
          Item {
            width: parent.width
            height: Math.max(choicesRow.implicitHeight, sourceLabel.implicitHeight) + Style.space(4)

            Row {
              id: choicesRow
              anchors.left: parent.left
              anchors.leftMargin: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(10)

              Row {
                id: languageRow
                spacing: Style.space(4)

                Repeater {
                  model: I18n.languageOptions()

                  Rectangle {
                    required property var modelData
                    readonly property bool current: modelData.value === root.language

                    width: languageText.implicitWidth + Style.space(14)
                    height: languageText.implicitHeight + Style.space(8)
                    radius: Style.cornerRadius
                    color: current ? Style.selectedFillFor(root.fg, root.accentColor)
                      : (languageHover.hovered ? Style.hoverFillFor(root.fg, root.accentColor) : "transparent")

                    Text {
                      id: languageText
                      anchors.centerIn: parent
                      text: modelData.value.toUpperCase()
                      color: parent.current ? Style.selectedStateColor(root.fg, root.accentColor) : Qt.darker(root.fg, 1.4)
                      font.family: root.uiFont
                      font.pixelSize: Style.font.caption
                      font.bold: parent.current
                      font.letterSpacing: 1
                      textFormat: Text.PlainText
                    }

                    HoverHandler { id: languageHover; cursorShape: Qt.PointingHandCursor }
                    MouseArea {
                      anchors.fill: parent
                      onClicked: root.setLanguage(modelData.value)
                    }
                  }
                }
              }

              // Group separator. Language, units and attribution are three
              // unrelated things on one line and the eye needs a break between
              // them; a pipe is the lightest mark that gives one without
              // drawing a rule across the panel.
              Text {
                height: languageRow.implicitHeight
                verticalAlignment: Text.AlignVCenter
                text: "|"
                color: Qt.darker(root.fg, 2.6)
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
                textFormat: Text.PlainText
              }

              // Metric or imperial. Converted locally — see Model.convert —
              // so the switch costs no request and works offline.
              Row {
                id: unitsRow
                spacing: Style.space(4)

                Repeater {
                  model: [
                    { value: "metric", label: root.tr("unitsMetric") },
                    { value: "imperial", label: root.tr("unitsImperial") }
                  ]

                  Rectangle {
                    required property var modelData
                    readonly property bool current: modelData.value === root.units

                    width: unitsText.implicitWidth + Style.space(14)
                    height: unitsText.implicitHeight + Style.space(8)
                    radius: Style.cornerRadius
                    color: current ? Style.selectedFillFor(root.fg, root.accentColor)
                      : (unitsHover.hovered ? Style.hoverFillFor(root.fg, root.accentColor) : "transparent")

                    Text {
                      id: unitsText
                      anchors.centerIn: parent
                      text: modelData.label
                      color: parent.current ? Style.selectedStateColor(root.fg, root.accentColor) : Qt.darker(root.fg, 1.4)
                      font.family: root.uiFont
                      font.pixelSize: Style.font.caption
                      font.bold: parent.current
                      textFormat: Text.PlainText
                    }

                    HoverHandler { id: unitsHover; cursorShape: Qt.PointingHandCursor }
                    MouseArea {
                      anchors.fill: parent
                      onClicked: root.setUnits(modelData.value)
                    }
                  }
                }
              }
            }

            // Required attribution for MeteoSwiss Open Data, and the honest
            // answer to "where did this number come from" — so both halves are
            // links: one to MeteoSwiss, one to the Open Data documentation that
            // specifies every parameter shown above.
            Row {
              id: sourceLabel
              anchors.right: parent.right
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              // This one is pinned to the attribution rather than trailing the
              // units, where it would read as a stray pipe with a gap after it.
              Text {
                text: "|"
                color: Qt.darker(root.fg, 2.6)
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
              }

              Text {
                text: root.tr("source")
                color: attributionHover.hovered ? root.fg : Qt.darker(root.fg, 1.9)
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
                font.underline: attributionHover.hovered
                textFormat: Text.PlainText

                HoverHandler { id: attributionHover; cursorShape: Qt.PointingHandCursor }
                MouseArea {
                  anchors.fill: parent
                  onClicked: root.openLink(Net.siteUrl(root.language))
                }
              }

              Text {
                text: "·"
                color: Qt.darker(root.fg, 2.2)
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
                textFormat: Text.PlainText
              }

              Text {
                text: root.tr("openData")
                color: openDataHover.hovered ? root.fg : Qt.darker(root.fg, 1.9)
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
                font.underline: openDataHover.hovered
                textFormat: Text.PlainText

                HoverHandler { id: openDataHover; cursorShape: Qt.PointingHandCursor }
                MouseArea {
                  anchors.fill: parent
                  onClicked: root.openLink(Net.openDataUrl())
                }
              }
            }
          }

        }
      }

      // Over the panel rather than in it: the list covers whichever view is
      // open and leaves on the same key that opened it, on Esc, or on a click
      // anywhere. Nothing underneath moves, so pressing h twice costs nothing.
      Rectangle {
        id: helpSheet
        anchors.fill: parent
        visible: root.helpOpen
        color: Color.popups.background
        radius: Style.cornerRadius

        property real capsWidth: 0

        MouseArea {
          anchors.fill: parent
          onClicked: root.helpOpen = false
        }

        Column {
          anchors.centerIn: parent
          width: parent.width - Style.space(56)
          spacing: Style.space(9)

          Text {
            text: root.tr("help").toUpperCase()
            color: Qt.darker(root.fg, 1.4)
            font.family: root.uiFont
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
            bottomPadding: Style.space(3)
            textFormat: Text.PlainText
          }

          Repeater {
            model: root.helpRows

            Item {
              required property var modelData
              width: parent.width
              height: Math.max(cap.implicitHeight, what.implicitHeight)

              KeyCap {
                id: cap
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                // Every cap as wide as the widest, so the descriptions start on
                // one line: a ragged left edge is exactly what a list of keys
                // must not have.
                width: Math.max(implicitWidth, helpSheet.capsWidth)
                label: modelData.keys
                foreground: root.fg
                fontFamily: root.uiFont
                Component.onCompleted: helpSheet.capsWidth = Math.max(helpSheet.capsWidth, implicitWidth)
              }

              Text {
                id: what
                anchors.left: cap.right
                anchors.leftMargin: Style.space(14)
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.label
                color: Qt.darker(root.fg, 1.5)
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
              }
            }
          }
        }
      }
    }
  }

  // --- main view -----------------------------------------------------------

  Component {
    id: mainView

    Column {
      spacing: Style.space(12)

      PanelSeparator { foreground: root.fg }

      // Hero: symbol, temperature, and the plain-language condition.
      Item {
        width: parent.width
        height: Math.max(heroLeft.height, conditionText.height) + Style.space(4)

        Row {
          id: heroLeft
          anchors.left: parent.left
          anchors.leftMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(14)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.barSymbol !== "" ? root.barSymbol : Symbols.GLYPH_UNKNOWN
            color: root.fg
            font.family: root.uiFont
            // Deliberately outside the Style.font.* scale: this is the one
            // decorative mark in the panel and it carries the glance value.
            font.pixelSize: Style.space(56)
            textFormat: Text.PlainText
          }

          Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              id: heroTemperature
              text: root.fmt(root.currentTemperature ? root.currentTemperature.value : null, "temperature")
              color: root.fg
              font.family: root.uiFont
              font.pixelSize: Style.space(44)
              font.bold: true
              textFormat: Text.PlainText
            }

            Text {
              text: root.unitLabel("temperature")
              color: Qt.darker(root.fg, 1.4)
              font.family: root.uiFont
              font.pixelSize: Style.font.subtitle
              anchors.top: heroTemperature.top
              anchors.topMargin: Style.space(8)
              textFormat: Text.PlainText
            }
          }
        }

        // The right half of the hero: the plain-language condition, and a link
        // to MeteoSwiss's own page for this town.
        //
        // The column takes its width from the space heroLeft leaves rather
        // than from its own children. Sizing it to the children while a child
        // anchored to its right edge would be a binding loop, and QML resolves
        // that by dropping the anchor — which is exactly how the link came out
        // invisible the first time.
        Column {
          id: conditionText
          anchors.right: parent.right
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(Style.space(80), parent.width - heroLeft.width - Style.space(30))
          spacing: Style.space(6)

          Text {
            id: conditionLabel
            width: parent.width
            horizontalAlignment: Text.AlignRight
            wrapMode: Text.WordWrap
            text: root.currentConditions ? Symbols.describe(root.currentConditions.icon, root.language) : ""
            color: Qt.darker(root.fg, 1.35)
            font.family: root.uiFont
            font.pixelSize: Style.font.bodySmall
            textFormat: Text.PlainText
          }

          // MeteoSwiss's own page for this town, in the panel's language. The
          // URL is looked up rather than derived — see Places.pageSlug — so it
          // is either correct or absent; there is no case where this opens
          // somebody else's forecast. Hidden for the handful of postal codes
          // that address a PO box rather than a place.
          Item {
            width: parent.width
            height: pageLinkRow.implicitHeight
            visible: root.activePageUrl !== ""

            Row {
              id: pageLinkRow
              anchors.right: parent.right
              spacing: Style.space(5)

              Text {
                text: root.tr("fullForecast")
                color: pageLinkHover.hovered ? root.fg : Qt.darker(root.fg, 1.75)
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
                font.underline: pageLinkHover.hovered
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
              }

              Text {
                text: "" // nf-fa-external_link
                color: pageLinkHover.hovered ? root.fg : Qt.darker(root.fg, 1.75)
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
              }
            }

            HoverHandler { id: pageLinkHover; cursorShape: Qt.PointingHandCursor }

            MouseArea {
              anchors.fill: pageLinkRow
              anchors.margins: -Style.space(4)
              onClicked: root.openLink(root.activePageUrl)
            }
          }
        }
      }

      // Provenance line: which station, how far away, and exactly when. This
      // is what makes the numbers above auditable rather than assertions.
      Text {
        x: Style.space(10)
        width: parent.width - Style.space(20)
        elide: Text.ElideRight
        text: {
          if (!root.stationReading) {
            // No station data at all yet — but the forecast may already be up,
            // in which case the hero is showing its value and should say so.
            if (root.currentConditions && root.currentConditions.time !== null) {
              return root.tr("forecastLabel") + " · "
                + Model.formatClock(new Date(root.currentConditions.time))
            }
            return root.tr("loading")
          }

          var when = Model.formatDate(root.stationReading.time) + " · " + Model.formatClock(root.stationReading.time)
          var where = root.activeStation
            ? root.tr("station") + " " + root.activeStation.name
              + " (" + Model.formatDistance(root.conv(root.activeStation.distanceKm, "distance"))
                + " " + root.unitLabel("distance") + ")"
            : ""
          var line = root.tr("measured") + " · " + when + (where !== "" ? " · " + where : "")
          // A station can report a timestamp and no values at all. Say that
          // plainly rather than leaving four dashes under a line that reads
          // like a confident measurement.
          if (root.activeStation && root.activeStation.coverage === 0) line += " · " + root.tr("stationSilent")
          return line
        }
        color: Qt.darker(root.fg, 1.7)
        font.family: root.uiFont
        font.pixelSize: Style.font.caption
        textFormat: Text.PlainText
      }

      // The four quantities the panel promises, each with its forecast band.
      //
      // Two columns rather than four: "PRECIPITATION (10 MIN)" needs more room
      // than a quarter of the popup, so four across would wrap the labels and
      // three across leaves one cell stranded on its own row. Fixing the width
      // makes it an even 2x2 whatever the theme's font size.
      Flow {
        id: statsFlow
        width: parent.width - Style.space(8)
        x: Style.space(4)
        spacing: Style.space(4)

        readonly property real cellWidth: Math.floor((width - spacing) / 2)

        StatCell {
          label: root.tr("temperature")
          value: root.fmt(root.currentTemperature ? root.currentTemperature.value : null, "temperature")
          unit: root.unitLabel("temperature")
          // Marked when the number is the forecast standing in for a silent
          // station, so the one non-measured value in this row says so.
          note: (root.currentTemperature && !root.currentTemperature.fromStation)
            ? root.tr("forecastLabel") : ""
          band: root.temperatureBand
            ? root.fmtRange(root.temperatureBand.low, root.temperatureBand.high, "temperature") : ""
          bandUnit: root.temperatureBand ? root.unitLabel("temperature") : ""
          width: statsFlow.cellWidth
          foreground: root.fg
          accent: root.accentColor
          fontFamily: root.uiFont
          interactive: true
          onActivated: root.showDetail("today")
        }

        StatCell {
          label: root.tr("precipitation") + " " + root.tr("tenMinuteInterval")
          value: root.fmt(root.stationReading ? root.stationReading.rre150z0 : null, "precipitation")
          unit: root.unitLabel("precipitation")
          band: root.precipitationHour
            ? root.fmtRange(root.precipitationHour.min, root.precipitationHour.max, "precipitation") : ""
          bandUnit: root.precipitationHour ? root.unitLabel("precipitation") + root.tr("perHour") : ""
          width: statsFlow.cellWidth
          foreground: root.fg
          accent: root.accentColor
          fontFamily: root.uiFont
          interactive: true
          onActivated: root.showDetail("today")
        }

        StatCell {
          label: root.tr("wind")
          value: root.fmt(root.stationReading ? root.stationReading.fu3010z0 : null, "speed")
          unit: root.unitLabel("speed")
          note: {
            if (!root.stationReading) return ""
            var direction = I18n.compass(root.language, root.stationReading.dkl010z0)
            var gust = root.stationReading.fu3010z1
            var parts = []
            if (direction !== "") parts.push(direction)
            if (gust !== null) parts.push(root.tr("gust") + " " + root.fmt(gust, "speed"))
            return parts.join(" · ")
          }
          band: root.windBand ? root.fmtRange(root.windBand.low, root.windBand.high, "speed") : ""
          bandUnit: root.windBand ? root.unitLabel("speed") : ""
          width: statsFlow.cellWidth
          foreground: root.fg
          accent: root.accentColor
          fontFamily: root.uiFont
          interactive: true
          onActivated: root.showDetail("wind")
        }

        StatCell {
          label: root.tr("sunshine") + " " + root.tr("tenMinuteInterval")
          value: Model.formatNumber(root.stationReading ? root.stationReading.sre000z0 : null, 0)
          unit: root.tr("unitSunshine")
          // Sunshine has no published quantile band; the plain forecast value
          // is shown instead, on its own per-hour scale.
          band: root.sunshineForecast !== null ? Model.formatNumber(root.sunshineForecast, 0) : ""
          bandUnit: root.sunshineForecast !== null
            ? root.tr("unitSunshine") + root.tr("perHour") : ""
          width: statsFlow.cellWidth
          foreground: root.fg
          accent: root.accentColor
          fontFamily: root.uiFont
          interactive: true
          onActivated: root.showDetail("today")
        }
      }

      // Warnings, rendered as plain text only — see Model.parseForecast, which
      // drops the HTML and link fields the service also sends.
      // Shown whenever the user has asked for at least one category, so that
      // ticking a box always changes something on screen — including saying
      // that there is nothing to report, which is itself the answer.
      Column {
        id: warningsColumn
        width: parent.width
        spacing: Style.space(4)
        visible: root.forecast !== null && (root.showWeatherWarnings || root.showHazardWarnings)

        PanelSectionHeader {
          x: Style.space(10)
          text: root.tr("warnings")
          foreground: root.fg
          fontFamily: root.uiFont
        }

        Text {
          x: Style.space(10)
          visible: root.visibleWarnings.length === 0
          text: root.tr("noWarnings")
          color: Qt.darker(root.fg, 1.8)
          font.family: root.uiFont
          font.pixelSize: Style.font.caption
          font.italic: true
          textFormat: Text.PlainText
        }

        // The warnings themselves, in a box of their own that scrolls.
        //
        // MeteoSwiss writes these at whatever length the situation needs: a
        // thunderstorm advisory is two lines, a standing cantonal fire ban is
        // several paragraphs of legal wording, and several warnings can be in
        // force at once. Left to grow, that block pushes the charts and the
        // footer off the bottom of a panel whose height the screen already
        // caps — the text is then unreachable rather than merely long. Bounded
        // and scrolled, the whole text stays readable and everything below it
        // stays where the user left it.
        Flickable {
          id: warningsScroll
          x: Style.space(10)
          width: warningsColumn.width - Style.space(20)
          visible: root.visibleWarnings.length > 0
          // Tall enough for a warning of ordinary length to be read without
          // touching the scrollbar, short enough to leave the rest of the
          // panel visible when it isn't.
          height: Math.min(contentHeight, Style.space(180))
          contentWidth: width
          contentHeight: warningsList.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          // Takes the wheel only when there is something to scroll, so that
          // over a short warning the panel's own scroll keeps working.
          interactive: contentHeight > height

          // On, and staying on, whenever there is text below the fold. The
          // stock `AsNeeded` bar fades out when the pointer is elsewhere, so
          // the one moment it is needed — the user reading a clipped warning
          // and having no idea more of it exists — is the moment it is
          // invisible. Painted in the theme foreground for the same reason:
          // the default bar is a grey that all but disappears on a dark panel.
          ScrollBar.vertical: ScrollBar {
            id: warningsBar
            policy: warningsScroll.contentHeight > warningsScroll.height
              ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff

            contentItem: Rectangle {
              implicitWidth: Style.space(4)
              radius: width / 2
              color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b,
                             warningsBar.pressed ? 0.6 : (warningsBar.hovered ? 0.45 : 0.3))
              Behavior on color { ColorAnimation { duration: 120 } }
            }

            background: Rectangle {
              implicitWidth: Style.space(4)
              radius: width / 2
              color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08)
            }
          }

          Column {
            id: warningsList
            // The gutter is reserved whether or not the bar is showing. Making
            // it conditional would feed the bar's own visibility back into the
            // wrapping width, and so into the height that decides whether the
            // bar is needed at all — a binding loop that settles by luck.
            width: warningsScroll.width - Style.space(8)
            spacing: Style.space(6)

            Repeater {
              model: root.warningItems

              Column {
                id: warningItem
                required property var modelData
                readonly property var warning: modelData.warning

                width: warningsList.width
                spacing: Style.space(2)

                // Which authority is warning, and about what class of thing.
                Text {
                  visible: warningItem.modelData.header !== ""
                  topPadding: warningItem.modelData.index === 0 ? 0 : Style.space(8)
                  text: warningItem.modelData.header.toUpperCase()
                  color: Qt.darker(root.fg, 2.0)
                  font.family: root.uiFont
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 1
                  textFormat: Text.PlainText
                }

                // The headline: what it is, how bad, and what "how bad" means.
                Row {
                  spacing: Style.space(6)

                  Rectangle {
                    width: Style.space(6)
                    height: width
                    radius: width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.warningLevelColor(warningItem.warning.level)
                  }

                  Text {
                    text: root.warningTitle(warningItem.warning)
                    color: root.fg
                    font.family: root.uiFont
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                  }
                }

                Text {
                  visible: text !== ""
                  leftPadding: Style.space(12)
                  text: root.warningValidity(warningItem.warning)
                  color: Qt.darker(root.fg, 1.9)
                  font.family: root.uiFont
                  font.pixelSize: Style.font.caption
                  textFormat: Text.PlainText
                }

                // The body, one labelled point per line as MeteoSwiss wrote it.
                Repeater {
                  model: warningItem.warning.lines

                  Text {
                    required property var modelData
                    width: warningItem.width
                    leftPadding: Style.space(12)
                    wrapMode: Text.WordWrap
                    text: root.warningLineText(modelData)
                    color: Qt.darker(root.fg, 1.4)
                    font.family: root.uiFont
                    font.pixelSize: Style.font.caption
                    // Rich text, exceptionally, and only because the panel
                    // writes the markup itself: every character that came from
                    // the network has been through Model.escapeMarkup.
                    textFormat: Text.StyledText
                  }
                }
              }
            }
          }
        }
      }

      // MeteoSwiss's animated maps, and the nearest weather cam.
      //
      // Links, not pictures. The maps are served to the website as an
      // undocumented vector encoding rather than as images, and the cam
      // pictures come from the commercial provider that films them — showing
      // one would mean telling a third party where the user lives, every
      // quarter of an hour. Both open the real MeteoSwiss page, in the panel's
      // language, which is also where the animation controls are.
      Column {
        id: mapsColumn
        width: parent.width
        spacing: Style.space(4)

        PanelSectionHeader {
          x: Style.space(10)
          text: root.tr("maps")
          foreground: root.fg
          fontFamily: root.uiFont
        }

        Flow {
          x: Style.space(10)
          width: mapsColumn.width - Style.space(20)
          spacing: Style.space(12)

          Repeater {
            model: root.mapLinks

            Text {
              required property var modelData
              text: modelData.label + " ↗"
              color: mapHover.hovered ? root.fg : Qt.darker(root.fg, 1.6)
              font.family: root.uiFont
              font.pixelSize: Style.font.caption
              font.underline: mapHover.hovered
              textFormat: Text.PlainText

              HoverHandler { id: mapHover; cursorShape: Qt.PointingHandCursor }
              MouseArea {
                anchors.fill: parent
                onClicked: root.openLink(Net.mapPageUrl(modelData.key, root.language))
              }
            }
          }
        }

        Text {
          x: Style.space(10)
          visible: root.activeWebcamUrl !== ""
          text: root.activeWebcam
            ? root.tr("nearestWebcam") + " : " + root.activeWebcam.name
              + " · " + Model.formatDistance(root.conv(root.activeWebcam.distanceKm, "distance"))
              + " " + root.unitLabel("distance") + " ↗"
            : ""
          color: webcamHover.hovered ? root.fg : Qt.darker(root.fg, 1.8)
          font.family: root.uiFont
          font.pixelSize: Style.font.caption
          font.underline: webcamHover.hovered
          textFormat: Text.PlainText

          HoverHandler { id: webcamHover; cursorShape: Qt.PointingHandCursor }
          MouseArea {
            anchors.fill: parent
            onClicked: root.openLink(root.activeWebcamUrl)
          }
        }
      }

      Text {
        x: Style.space(10)
        visible: root.forecastFailed || root.measurementsFailed
        text: (root.forecast === null && root.stationReading === null)
          ? root.tr("neverLoaded") : root.tr("unreachable")
        color: Color.urgent
        font.family: root.uiFont
        font.pixelSize: Style.font.caption
        textFormat: Text.PlainText
      }

    }
  }

  // --- search view ---------------------------------------------------------

  Component {
    id: searchView

    Column {
      id: searchColumn
      spacing: Style.space(8)

      TextField {
        id: searchFieldProxy
        x: Style.space(4)
        width: parent.width - Style.space(8)
        placeholderText: root.tr("searchPlaceholder")
        foreground: root.fg
        font.family: root.uiFont

        // The field lives in a Loader-instantiated component, so the panel
        // reaches it through this alias rather than by id.
        Component.onCompleted: root.searchField = searchFieldProxy
        Component.onDestruction: if (root.searchField === searchFieldProxy) root.searchField = null

        onTextChanged: searchDebounce.restart()

        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.showMain()
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            if (root.searchIndex < root.searchResults.length - 1) root.searchIndex++
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            if (root.searchIndex > 0) root.searchIndex--
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.pickSearchResult(root.searchResults[root.searchIndex])
            event.accepted = true
          }
        }
      }

      Text {
        x: Style.space(10)
        visible: root.searchResults.length === 0
        text: searchFieldProxy.text.length < 2 ? root.tr("searchHint") : root.tr("noResults")
        color: Qt.darker(root.fg, 1.8)
        font.family: root.uiFont
        font.pixelSize: Style.font.caption
        font.italic: true
        textFormat: Text.PlainText
      }

      Repeater {
        model: root.searchResults

        Rectangle {
          required property var modelData
          required property int index

          width: searchColumn.width - Style.space(8)
          x: Style.space(4)
          height: resultRow.implicitHeight + Style.space(10)
          radius: Style.cornerRadius
          color: index === root.searchIndex ? Style.hoverFillFor(root.fg, root.accentColor) : "transparent"

          Row {
            id: resultRow
            anchors.left: parent.left
            anchors.leftMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)

            Text {
              text: modelData.name
              color: root.fg
              font.family: root.uiFont
              font.pixelSize: Style.font.body
              textFormat: Text.PlainText
            }

            Text {
              text: modelData.plz
              color: Qt.darker(root.fg, 1.5)
              font.family: root.uiFont
              font.pixelSize: Style.font.bodySmall
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
            }

            Text {
              visible: modelData.altitude !== null
              text: modelData.altitude !== null ? Math.round(modelData.altitude) + " m" : ""
              color: Qt.darker(root.fg, 1.8)
              font.family: root.uiFont
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
            }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPositionChanged: root.searchIndex = index
            onClicked: root.pickSearchResult(modelData)
          }
        }
      }
    }
  }

  // The search field only exists while the search view is loaded, which is
  // rarely. Every use is guarded rather than propped up by a stand-in object,
  // so a stale reference cannot survive the view being torn down.
  property var searchField: null

  Timer {
    id: searchDebounce
    interval: 120
    repeat: false
    onTriggered: root.runSearch()
  }

  // --- detail view ---------------------------------------------------------

  Component {
    id: detailView

    Column {
      spacing: Style.space(10)

      // Two tabs, not three. The wind charts are reached by clicking the wind
      // reading, exactly like the temperature and precipitation charts are
      // reached by clicking theirs; a tab for wind alone made the same view
      // arrive by two different routes and implied the other two had tabs
      // somewhere as well. In the wind view neither tab is lit, and the
      // view's own heading says what is on screen.
      ButtonGroup {
        x: Style.space(4)
        options: [
          { value: "today", label: root.tr("tabToday") },
          { value: "week", label: root.tr("tabWeek") }
        ]
        value: root.detailTab
        foreground: root.fg
        accent: root.accentColor
        fontFamily: root.uiFont
        focusable: false
        onChanged: function(value) { root.detailTab = value }
      }

      PanelSeparator { foreground: root.fg }

      Loader {
        width: parent.width
        active: root.detailTab === "today"
        visible: active
        sourceComponent: todayView
      }

      Loader {
        width: parent.width
        active: root.detailTab === "week"
        visible: active
        sourceComponent: weekView
      }

      Loader {
        width: parent.width
        active: root.detailTab === "wind"
        visible: active
        sourceComponent: windView
      }

      Text {
        x: Style.space(10)
        text: root.tr("uncertainty")
        color: Qt.darker(root.fg, 1.9)
        font.family: root.uiFont
        font.pixelSize: Style.font.caption
        font.italic: true
        textFormat: Text.PlainText
      }
    }
  }

  // Points for today's hourly temperature, carrying the min/max band.
  readonly property var todayTemperature: {
    if (!graph) return []
    var mean = Model.sliceSeries(graph.temperature, todayStartMs, todayEndMs)
    var out = []
    for (var i = 0; i < mean.length; i++) {
      out.push({
        time: mean[i].time,
        value: conv(mean[i].value, "temperature"),
        min: conv(Model.valueAt(graph.temperatureMin, mean[i].time), "temperature"),
        max: conv(Model.valueAt(graph.temperatureMax, mean[i].time), "temperature")
      })
    }
    return out
  }

  readonly property var todayPrecipitation: {
    if (!graph) return []
    var hours = Model.hourlyPrecipitation(graph, todayStartMs, todayEndMs)
    var out = []
    for (var i = 0; i < hours.length; i++) {
      out.push({
        time: hours[i].time,
        value: conv(hours[i].value, "precipitation"),
        min: conv(hours[i].min, "precipitation"),
        max: conv(hours[i].max, "precipitation")
      })
    }
    return out
  }

  readonly property var todaySunshine: {
    if (!graph) return []
    var points = Model.sliceSeries(graph.sunshine, todayStartMs, todayEndMs)
    var out = []
    for (var i = 0; i < points.length; i++) {
      out.push({ time: points[i].time, value: points[i].value, min: null, max: null })
    }
    return out
  }

  // Wind runs 48 hours rather than one day: a wind chart that stops at
  // midnight cuts off exactly the part someone checking the wind cares about.
  readonly property real windWindowEndMs: todayStartMs + 48 * Model.HOUR_MS

  readonly property var windSeries: {
    if (!graph) return []
    var mean = Model.sliceSeries(graph.wind, todayStartMs, windWindowEndMs)
    var out = []
    for (var i = 0; i < mean.length; i++) {
      out.push({
        time: mean[i].time,
        value: conv(mean[i].value, "speed"),
        min: conv(Model.valueAt(graph.windQ10, mean[i].time), "speed"),
        max: conv(Model.valueAt(graph.windQ90, mean[i].time), "speed")
      })
    }
    return out
  }

  readonly property var gustSeries: {
    if (!graph) return []
    var mean = Model.sliceSeries(graph.gust, todayStartMs, windWindowEndMs)
    var out = []
    for (var i = 0; i < mean.length; i++) {
      out.push({
        time: mean[i].time,
        value: conv(mean[i].value, "speed"),
        min: conv(Model.valueAt(graph.gustQ10, mean[i].time), "speed"),
        max: conv(Model.valueAt(graph.gustQ90, mean[i].time), "speed")
      })
    }
    return out
  }

  /** Three-hourly entries within a window, as `{ time, icon, direction }`. */
  function threeHourly(fromMs, toMs) {
    if (!graph) return []
    var icons = Model.sliceSeries(graph.icon3h, fromMs, toMs)
    var out = []
    for (var i = 0; i < icons.length; i++) {
      out.push({
        time: icons[i].time,
        icon: icons[i].value,
        direction: Model.valueAt(graph.windDirection3h, icons[i].time),
        probability: Model.valueAt(graph.precipitationProbability3h, icons[i].time)
      })
    }
    return out
  }

  Component {
    id: todayView

    Column {
      spacing: Style.space(10)

      // Three-hourly symbols across the day, with precipitation probability.
      Row {
        x: Style.space(6)
        spacing: Style.space(2)

        Repeater {
          model: root.threeHourly(root.todayStartMs, root.todayEndMs)

          Column {
            required property var modelData
            width: Style.space(58)
            spacing: Style.space(2)

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: new Date(modelData.time).getHours() + " " + root.tr("hourSuffix")
              color: Qt.darker(root.fg, 1.7)
              font.family: root.uiFont
              font.pixelSize: Style.font.caption
              textFormat: Text.PlainText
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: Symbols.glyph(modelData.icon)
              color: root.fg
              font.family: root.uiFont
              font.pixelSize: Style.font.iconLarge
              textFormat: Text.PlainText
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              visible: modelData.probability !== null
              text: modelData.probability !== null ? Math.round(modelData.probability) + "%" : ""
              color: Qt.darker(root.fg, 1.7)
              font.family: root.uiFont
              font.pixelSize: Style.font.caption
              textFormat: Text.PlainText
            }
          }
        }
      }

      PanelSectionHeader {
        x: Style.space(10)
        text: root.tr("temperature") + " · " + root.unitLabel("temperature")
        foreground: root.fg
        fontFamily: root.uiFont
      }

      Chart {
        x: Style.space(6)
        width: parent.width - Style.space(12)
        height: Style.space(110)
        mode: "line"
        points: root.todayTemperature
        unit: root.unitLabel("temperature")
        decimals: root.dec("temperature")
        minimumSpan: root.chartSpan("temperature")
        foreground: root.fg
        accent: root.accentColor
        fontFamily: root.uiFont
      }

      PanelSectionHeader {
        x: Style.space(10)
        text: root.tr("precipitation") + " · " + root.unitLabel("precipitation") + root.tr("perHour")
        foreground: root.fg
        fontFamily: root.uiFont
      }

      Chart {
        x: Style.space(6)
        width: parent.width - Style.space(12)
        height: Style.space(90)
        mode: "bars"
        points: root.todayPrecipitation
        unit: root.unitLabel("precipitation")
        decimals: root.dec("precipitation")
        minimumSpan: root.chartSpan("precipitation")
        baselineAtZero: true
        foreground: root.fg
        accent: root.accentColor
        fontFamily: root.uiFont
      }

      PanelSectionHeader {
        x: Style.space(10)
        text: root.tr("sunshine") + " · " + root.tr("unitSunshine") + root.tr("perHour")
        foreground: root.fg
        fontFamily: root.uiFont
      }

      Chart {
        x: Style.space(6)
        width: parent.width - Style.space(12)
        height: Style.space(80)
        mode: "bars"
        points: root.todaySunshine
        unit: root.tr("unitSunshine")
        decimals: 0
        minimumSpan: 10
        baselineAtZero: true
        foreground: root.fg
        accent: root.accentColor
        fontFamily: root.uiFont
      }

      Text {
        x: Style.space(10)
        visible: root.graph !== null && root.graph.sunrise.length > 0
        text: {
          if (!root.graph || root.graph.sunrise.length === 0) return ""
          return root.tr("sunrise") + " " + Model.formatClock(new Date(root.graph.sunrise[0]))
            + "   " + root.tr("sunset") + " " + Model.formatClock(new Date(root.graph.sunset[0]))
        }
        color: Qt.darker(root.fg, 1.7)
        font.family: root.uiFont
        font.pixelSize: Style.font.caption
        textFormat: Text.PlainText
      }

      Text {
        x: Style.space(10)
        visible: root.todayTemperature.length === 0
        text: root.tr("noData")
        color: Qt.darker(root.fg, 1.8)
        font.family: root.uiFont
        font.pixelSize: Style.font.caption
        font.italic: true
        textFormat: Text.PlainText
      }
    }
  }

  Component {
    id: weekView

    Column {
      id: weekColumn
      spacing: Style.space(2)

      Repeater {
        model: root.forecast ? root.forecast.days : []

        Item {
          required property var modelData
          width: weekColumn.width - Style.space(12)
          x: Style.space(6)
          height: dayRow.implicitHeight + Style.space(12)

          Rectangle {
            anchors.fill: parent
            radius: Style.cornerRadius
            color: dayHover.hovered ? Style.hoverFillFor(root.fg, root.accentColor) : "transparent"
          }

          HoverHandler { id: dayHover }

          Row {
            id: dayRow
            anchors.left: parent.left
            anchors.leftMargin: Style.space(8)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(10)

            Column {
              width: Style.space(56)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(1)

              Text {
                text: I18n.weekday(root.language, modelData.date).toUpperCase()
                color: root.fg
                font.family: root.uiFont
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                textFormat: Text.PlainText
              }

              Text {
                text: Model.formatDayMonth(modelData.date)
                color: Qt.darker(root.fg, 1.7)
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
                textFormat: Text.PlainText
              }
            }

            Text {
              width: Style.space(28)
              anchors.verticalCenter: parent.verticalCenter
              text: Symbols.glyph(modelData.icon)
              color: root.fg
              font.family: root.uiFont
              font.pixelSize: Style.font.iconLarge
              textFormat: Text.PlainText
            }

            Row {
              width: Style.space(96)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              Text {
                text: Model.formatNumber(root.conv(modelData.temperatureMax, "temperature"), 0) + "°"
                color: root.fg
                font.family: root.uiFont
                font.pixelSize: Style.font.body
                textFormat: Text.PlainText
              }

              Text {
                text: Model.formatNumber(root.conv(modelData.temperatureMin, "temperature"), 0) + "°"
                color: Qt.darker(root.fg, 1.6)
                font.family: root.uiFont
                font.pixelSize: Style.font.body
                textFormat: Text.PlainText
              }
            }

            // Expected precipitation with its 10-90 % range. The range is what
            // separates "1 mm" from "1 mm, and it could be six".
            Column {
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(1)

              Text {
                text: root.fmt(modelData.precipitation, "precipitation") + " " + root.unitLabel("precipitation")
                color: Qt.darker(root.fg, 1.2)
                font.family: root.uiFont
                font.pixelSize: Style.font.bodySmall
                textFormat: Text.PlainText
              }

              Text {
                visible: text !== ""
                text: {
                  var range = root.fmtRange(modelData.precipitationMin, modelData.precipitationMax, "precipitation")
                  return range === "" ? "" : "‹ " + range + " ›"
                }
                color: Qt.darker(root.fg, 1.8)
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
                textFormat: Text.PlainText
              }
            }
          }
        }
      }

      Text {
        x: Style.space(10)
        visible: root.forecast === null || root.forecast.days.length === 0
        text: root.tr("noData")
        color: Qt.darker(root.fg, 1.8)
        font.family: root.uiFont
        font.pixelSize: Style.font.caption
        font.italic: true
        textFormat: Text.PlainText
      }
    }
  }

  Component {
    id: windView

    Column {
      spacing: Style.space(10)

      PanelSectionHeader {
        x: Style.space(10)
        text: root.tr("wind") + " · " + root.unitLabel("speed")
        foreground: root.fg
        fontFamily: root.uiFont
      }

      Chart {
        x: Style.space(6)
        width: parent.width - Style.space(12)
        height: Style.space(130)
        mode: "line"
        points: root.windSeries
        secondary: root.gustSeries
        secondaryLabel: root.tr("gust")
        unit: root.unitLabel("speed")
        decimals: root.dec("speed")
        minimumSpan: root.chartSpan("speed")
        baselineAtZero: true
        hourLabelStep: 6
        foreground: root.fg
        accent: root.accentColor
        fontFamily: root.uiFont
      }

      Text {
        x: Style.space(10)
        text: "— " + root.tr("wind") + "    ·· " + root.tr("gust")
        color: Qt.darker(root.fg, 1.8)
        font.family: root.uiFont
        font.pixelSize: Style.font.caption
        textFormat: Text.PlainText
      }

      PanelSectionHeader {
        x: Style.space(10)
        text: root.tr("wind") + " · 3 h"
        foreground: root.fg
        fontFamily: root.uiFont
      }

      // Direction strip. MeteoSwiss reports the direction the wind blows
      // *from*, so the compass letter is that bearing while the arrow is
      // turned to point where the air is going — which is how an arrow reads.
      Row {
        x: Style.space(6)
        spacing: Style.space(2)

        Repeater {
          model: root.threeHourly(root.todayStartMs, root.todayEndMs)

          Column {
            required property var modelData
            width: Style.space(58)
            spacing: Style.space(2)

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: new Date(modelData.time).getHours() + " " + root.tr("hourSuffix")
              color: Qt.darker(root.fg, 1.7)
              font.family: root.uiFont
              font.pixelSize: Style.font.caption
              textFormat: Text.PlainText
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              visible: modelData.direction !== null
              text: "↑"
              rotation: modelData.direction !== null ? modelData.direction + 180 : 0
              color: root.fg
              font.family: root.uiFont
              font.pixelSize: Style.font.icon
              textFormat: Text.PlainText
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: I18n.compass(root.language, modelData.direction)
              color: Qt.darker(root.fg, 1.7)
              font.family: root.uiFont
              font.pixelSize: Style.font.caption
              textFormat: Text.PlainText
            }
          }
        }
      }

      Text {
        x: Style.space(10)
        visible: root.windSeries.length === 0
        text: root.tr("noData")
        color: Qt.darker(root.fg, 1.8)
        font.family: root.uiFont
        font.pixelSize: Style.font.caption
        font.italic: true
        textFormat: Text.PlainText
      }
    }
  }
}

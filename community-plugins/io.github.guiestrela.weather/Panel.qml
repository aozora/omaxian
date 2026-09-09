import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.guiestrela.weather"
  ipcTarget: "io.github.guiestrela.weather"
  manageIpc: false

  property var anchorItem: null
  property bool openedFromHotkey: false

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel. Everything the bar identifies a panel by has to be that
  // widget: the popout coordinator (and with it the open-panel dot under the
  // pill) compares against `slot.activeItem`, and switchPanelFrom looks the
  // slot up the same way.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  function open() {
    openedFromHotkey = false
    setCenterHoverRevealSuppressed(false)
    root.controller.show()
    locationFile.reload()
    root.refresh()
  }

  function openFromHotkey() {
    openedFromHotkey = true
    root.controller.show()
    locationFile.reload()
    root.refresh()
    // Set after showing, not before: showing hands the popout coordinator
    // over, which closes whichever panel was open, and that close clears the
    // shared flag. Deferring means the panel taking over always wins, while
    // a handoff to a panel that does not manage the flag still leaves it
    // cleared rather than stuck on.
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    if (root.editingLocation) root.cancelEditingLocation()
    root.controller.hide()
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

  // Parsed wttr.in j1 response. Kept on failure so stale data stays visible.
  property var report: null
  property var dailyForecastReport: null
  property string wttrLocation: ""
  property string radarLatitude: ""
  property string radarLongitude: ""
  property bool activitiesExpanded: true
  property bool mapsExpanded: true
  // shellDir is the Omarchy shell root, not this plugin's directory.
  readonly property string helperPath: String(Qt.resolvedUrl("weather-helper.py")).replace(/^file:\/\//, "")
  readonly property string pythonPath: "/usr/bin/python3"
  readonly property int maxProcBytes: 262144
  readonly property int procDeadlineMs: 45000
  // QML does not always track dependencies read indirectly from JavaScript
  // functions. Bump this when a new auto-detected report supplies map
  // coordinates so hasRadarCoordinates is re-evaluated.
  property int mapRevision: 0

  property string radarGeocodeBuf: ""
  property string locationFileBuf: ""
  property string panelStateFileBuf: ""
  property string forecastBuf: ""
  property string dailyForecastBuf: ""
  property string geocodeBuf: ""
  property string locationProcBuf: ""

  function helperCmd() {
    var cmd = [root.pythonPath, "-I", "-S", root.helperPath]
    for (var i = 0; i < arguments.length; i++)
      cmd.push(arguments[i])
    return cmd
  }

  function appendBounded(buffer, chunk) {
    var next = String(buffer || "") + String(chunk || "")
    return next.length > root.maxProcBytes ? null : next
  }

  function openRadarInBrowser() {
    var lat = root.radarCoordinate("lat")
    var lon = root.radarCoordinate("lon")
    if (lat === "" || lon === "") return
    var url = "https://www.rainviewer.com/map?loc=" + encodeURIComponent(lat + "," + lon + ",8")
    Quickshell.execDetached([root.pythonPath, "-I", "-S", root.helperPath, "open", url])
  }

  function radarCoordinate(value) {
    var configured = parseFloat(String(value === "lat" ? configuredLocationState.latitude : configuredLocationState.longitude))
    if (!isNaN(configured)) return String(configured)
    var cached = value === "lat" ? radarLatitude : radarLongitude
    if (cached !== "") return cached
    var field = value === "lat" ? "latitude" : "longitude"
    if (!areaInfo || areaInfo[field] === undefined || areaInfo[field] === null) return ""

    // wttr.in returns these coordinates as plain strings. Keep accepting the
    // array/object shape used by some older responses as well.
    var raw = areaInfo[field]
    if (Array.isArray(raw)) raw = raw.length > 0 && raw[0] ? raw[0].value : ""
    else if (typeof raw === "object") raw = raw.value
    var coordinate = parseFloat(String(raw === undefined || raw === null ? "" : raw))
    return isNaN(coordinate) ? "" : String(coordinate)
  }

  function loadPanelState(raw) {
    try {
      var state = JSON.parse(String(raw || ""))
      if (state && typeof state === "object") {
        if (state.activitiesExpanded !== undefined) activitiesExpanded = state.activitiesExpanded !== false
        if (state.mapsExpanded !== undefined) mapsExpanded = state.mapsExpanded !== false
      }
    } catch (e) {
      // Missing or invalid state keeps the expanded defaults.
    }
  }

  function savePanelState() {
    panelStateSaveProc.command = root.helperCmd("write", "weather-panel.json", JSON.stringify({
      activitiesExpanded: activitiesExpanded,
      mapsExpanded: mapsExpanded
    }) + "\n")
    panelStateSaveProc.running = true
  }

  // Reading mapRevision here keeps the indirect coordinate reads observable.
  readonly property bool hasRadarCoordinates: {
    var revision = mapRevision
    return radarCoordinate("lat") !== "" && radarCoordinate("lon") !== ""
  }

  function scrollHorizontally(flickable, wheel) {
    var delta = wheel.pixelDelta.y !== 0 ? wheel.pixelDelta.y : wheel.pixelDelta.x
    if (delta === 0) delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x
    delta = (delta / 120) * Style.space(96)
    flickable.contentX = Math.max(0, Math.min(Math.max(0, flickable.contentWidth - flickable.width), flickable.contentX - delta))
    wheel.accepted = true
  }

  // Ensure coordinates for the Open radar button; map tiles are not loaded in-shell.
  function refreshRadar() {
    if (radarCoordinate("lat") !== "" && radarCoordinate("lon") !== "") return
    if (configuredLocation !== "" && !radarGeocodeProc.running) radarGeocodeProc.running = true
  }

  Process {
    id: radarGeocodeProc
    command: root.helperCmd("fetch", "https://geocoding-api.open-meteo.com/v1/search?name=" + encodeURIComponent(root.configuredLocation) + "&count=10&language=en&format=json", "5")
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        var next = root.appendBounded(root.radarGeocodeBuf, chunk)
        if (next === null) { root.radarGeocodeBuf = ""; radarGeocodeProc.signal(15); radarGeocodeKill.start(); return }
        root.radarGeocodeBuf = next
      }
    }
    onRunningChanged: if (running) radarGeocodeDeadline.restart(); else { radarGeocodeDeadline.stop(); radarGeocodeKill.stop() }
    onExited: function(exitCode) {
      var text = root.radarGeocodeBuf
      root.radarGeocodeBuf = ""
      if (exitCode !== 0) return
      try {
        var results = (JSON.parse(String(text || "")).results || []).slice(0, 10)
        var selected = results.length > 0 ? results[0] : null
        if (selected) {
          root.radarLatitude = String(selected.latitude)
          root.radarLongitude = String(selected.longitude)
          root.mapRevision++
        }
      } catch (e) {
        // Radar button stays hidden until coordinates are available.
      }
    }
  }
  Timer { id: radarGeocodeDeadline; interval: root.procDeadlineMs; onTriggered: { radarGeocodeProc.signal(15); radarGeocodeKill.start() } }
  Timer { id: radarGeocodeKill; interval: 2000; onTriggered: radarGeocodeProc.signal(9) }

  Timer {
    interval: 5 * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshRadar()
  }

  // Configured location, read from the weather.json state file (owned by
  // omarchy-weather-location). The query is the wttr.in path segment
  // (coordinates when stored, else the encoded name); empty means IP
  // auto-detect. The watch makes hand edits take effect live.
  property var configuredLocationState: ({ name: "", latitude: null, longitude: null })
  readonly property string configuredLocation: configuredLocationState.name
  readonly property string locationQuery: Model.wttrLocationQuery(configuredLocationState.name, configuredLocationState.latitude, configuredLocationState.longitude)

  // Keep the previous report visible while the new location loads. The
  // editor remains open with a spinner, so stale data is never presented
  // under the newly configured location label.
  onLocationQueryChanged: {
    // QML cannot reliably track coordinates read inside the map helper
    // functions. Force every map layer to rebuild for the new location.
    mapRevision++
    if (savingLocation) savingLocationQueryStarted = true
    forecastRetries = 0
    dailyForecastRetries = 0
    forecastProc.running = false
    dailyForecastProc.running = false
    Qt.callLater(root.refreshRadar)
    Qt.callLater(refresh)
  }

  Process {
    id: locationFile
    command: root.helperCmd("read", "weather.json")
    function reload() { if (!running) running = true }
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        var next = root.appendBounded(root.locationFileBuf, chunk)
        if (next === null) { root.locationFileBuf = ""; locationFile.signal(15); locationFileKill.start(); return }
        root.locationFileBuf = next
      }
    }
    onRunningChanged: if (running) locationFileDeadline.restart(); else { locationFileDeadline.stop(); locationFileKill.stop() }
    onExited: function(exitCode) {
      var text = root.locationFileBuf
      root.locationFileBuf = ""
      if (exitCode !== 0) {
        root.configuredLocationState = Model.parseLocationFile("")
        return
      }
      root.configuredLocationState = Model.parseLocationFile(text)
    }
  }
  Timer { id: locationFileDeadline; interval: root.procDeadlineMs; onTriggered: { locationFile.signal(15); locationFileKill.start() } }
  Timer { id: locationFileKill; interval: 2000; onTriggered: locationFile.signal(9) }

  Process {
    id: panelStateFile
    command: root.helperCmd("read", "weather-panel.json")
    function reload() { if (!running) running = true }
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        var next = root.appendBounded(root.panelStateFileBuf, chunk)
        if (next === null) { root.panelStateFileBuf = ""; panelStateFile.signal(15); panelStateFileKill.start(); return }
        root.panelStateFileBuf = next
      }
    }
    onRunningChanged: if (running) panelStateFileDeadline.restart(); else { panelStateFileDeadline.stop(); panelStateFileKill.stop() }
    onExited: function(exitCode) {
      var text = root.panelStateFileBuf
      root.panelStateFileBuf = ""
      if (exitCode === 0) root.loadPanelState(text)
    }
  }
  Timer { id: panelStateFileDeadline; interval: root.procDeadlineMs; onTriggered: { panelStateFile.signal(15); panelStateFileKill.start() } }
  Timer { id: panelStateFileKill; interval: 2000; onTriggered: panelStateFile.signal(9) }

  Process {
    id: panelStateSaveProc
    onRunningChanged: if (running) panelStateSaveDeadline.restart(); else { panelStateSaveDeadline.stop(); panelStateSaveKill.stop() }
  }
  Timer { id: panelStateSaveDeadline; interval: root.procDeadlineMs; onTriggered: { panelStateSaveProc.signal(15); panelStateSaveKill.start() } }
  Timer { id: panelStateSaveKill; interval: 2000; onTriggered: panelStateSaveProc.signal(9) }

  // The first read can race shell startup (observed sporadically), leaving a
  // stored location unhonored until the next file write. One delayed reload
  // self-corrects; if the first read was fine it's a no-op, since identical
  // state doesn't change locationQuery and so triggers no refetch.
  Timer {
    interval: 1500
    running: true
    onTriggered: locationFile.reload()
  }

  property int forecastRetries: 0
  property int dailyForecastRetries: 0

  // Click-to-edit state for the location label.
  property bool editingLocation: false
  property bool savingLocation: false
  property bool savingLocationQueryStarted: false
  property var locationSuggestions: []
  property int suggestionIndex: 0
  property string geocodePendingQuery: ""
  property string geocodeActiveQuery: ""

  // Shared hero/bar icon state, updated with each successful weather response.
  property string label: ""

  // wttr's current conditions when available; open-meteo's (bundled with the
  // much faster daily forecast fetch) fill the hero while wttr is in flight.
  readonly property bool hasConfiguredCoordinates: !isNaN(parseFloat(String(configuredLocationState.latitude))) && !isNaN(parseFloat(String(configuredLocationState.longitude)))
  readonly property var openMeteoCurrent: Model.openMeteoCurrentCondition(dailyForecastReport)
  readonly property var current: (hasConfiguredCoordinates && openMeteoCurrent) ? openMeteoCurrent : ((report && report.current_condition && report.current_condition[0]) ? report.current_condition[0] : openMeteoCurrent)
  readonly property var areaInfo: report && report.nearest_area && report.nearest_area[0] ? report.nearest_area[0] : null
  readonly property var forecastDays: buildForecastDays()
  readonly property var forecastTimeline: Model.buildForecastTimeline(report, dailyForecastReport, Qt.formatDate(new Date(), "yyyy-MM-dd"))
  readonly property var todayForecast: Model.todayForecast(report, dailyForecastReport, Qt.formatDate(new Date(), "yyyy-MM-dd"))
  readonly property var todayHourlyForecast: Model.openMeteoTodayHourlyForecast(dailyForecastReport, Qt.formatDate(new Date(), "yyyy-MM-dd"))
  readonly property var activities: Model.activityForecast(openMeteoCurrent, todayForecast)
  readonly property string reportCountry: areaInfo && areaInfo.country && areaInfo.country[0] ? areaInfo.country[0].value : ""

  readonly property bool useImperial: Model.shouldUseImperial(setting("unit", ""), Qt.locale().name, reportCountry)

  // Auto-refresh interval in minutes; clamped to a sane minimum.
  readonly property int refreshMinutes: Math.max(1, parseInt(setting("refreshMinutes", 15), 10) || 15)

  readonly property string reportLocation:  (configuredLocation || wttrLocation || (areaInfo && areaInfo.areaName && areaInfo.areaName[0] ? String(areaInfo.areaName[0].value || "") : "")).slice(0, 128)
  // Keep the location control available before the first location response.
  readonly property string locationDisplay: reportLocation || "Set location"
  readonly property string reportTempNum:   current ? String(useImperial ? current.temp_F : current.temp_C) : ""
  readonly property string tempUnit:        "°" + (useImperial ? "F" : "C")
  readonly property string reportFeels:     current ? formatTemp(useImperial ? current.FeelsLikeF : current.FeelsLikeC) : ""
  readonly property string reportWind:      current ? (useImperial ? (current.windspeedMiles + " mph") : (current.windspeedKmph + " km/h")) : ""
  readonly property string reportHumidity:  current ? (current.humidity + "%") : ""

  function refresh() {
    // Each full refresh cycle gets a fresh retry budget, so an earlier
    // exhausted round (e.g. waking with the network still down) doesn't
    // starve retries for the rest of the session.
    forecastRetries = 0
    dailyForecastRetries = 0
    if (!forecastProc.running) forecastProc.running = true
    if (root.locationQuery === "" && !locationProc.running) locationProc.running = true
    // With stored coordinates this fetches open-meteo right away — no need
    // to wait for the slow wttr response. Without them it's a no-op until
    // wttr reports the detected area.
    refreshDailyForecast(null)
  }

  function refreshDailyForecast(sourceReport) {
    if (dailyForecastProc.running) return

    var lat = parseFloat(String(root.configuredLocationState.latitude))
    var lon = parseFloat(String(root.configuredLocationState.longitude))
    if (isNaN(lat) || isNaN(lon)) {
      var area = sourceReport && sourceReport.nearest_area && sourceReport.nearest_area[0] ? sourceReport.nearest_area[0] : root.areaInfo
      if (!area) return
      lat = parseFloat(String(area.latitude || ""))
      lon = parseFloat(String(area.longitude || ""))
    }
    if (isNaN(lat) || isNaN(lon)) return

    var url = "https://api.open-meteo.com/v1/forecast"
      + "?latitude=" + encodeURIComponent(String(lat))
      + "&longitude=" + encodeURIComponent(String(lon))
      + "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"
      + "&hourly=temperature_2m,weather_code,is_day"
      + "&past_days=1"
      + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day"
      + "&forecast_days=6"
      + "&timezone=auto"
    dailyForecastProc.command = root.helperCmd("fetch", url, "5")
    dailyForecastProc.running = true
  }

  // ---- Location editing. Clicking the location label swaps it for a search
  //      field; picking a geocoded suggestion persists name + coordinates to
  //      the module's shell.json entry. An empty commit returns to auto.
  function startEditingLocation() {
    editingLocation = true
    savingLocation = false
    savingLocationQueryStarted = false
    locationSuggestions = []
    suggestionIndex = 0
    Qt.callLater(function() {
      locationField.text = root.configuredLocation
      locationField.selectAll()
      locationField.forceActiveFocus()
    })
  }

  function cancelEditingLocation() {
    editingLocation = false
    savingLocation = false
    savingLocationQueryStarted = false
    locationSuggestions = []
    geocodeDebounce.stop()
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function commitLocation() {
    var location = Model.locationCommit(locationField.text, locationSuggestions, suggestionIndex)
    if (location.name === "") {
      clearLocation()
      return
    }
    savingLocation = true
    savingLocationQueryStarted = false
    configuredLocationState = {
      name: location.name,
      latitude: location.latitude,
      longitude: location.longitude
    }
    persistLocation(location.name, location.latitude, location.longitude)
  }

  function clearLocation() {
    configuredLocationState = { name: "", latitude: null, longitude: null }
    persistLocation("", null, null)
    wttrLocation = ""
    cancelEditingLocation()
  }

  function pickSuggestion(suggestion) {
    if (!suggestion) return
    savingLocation = true
    savingLocationQueryStarted = false
    configuredLocationState = {
      name: suggestion.name,
      latitude: suggestion.latitude,
      longitude: suggestion.longitude
    }
    persistLocation(suggestion.name, suggestion.latitude, suggestion.longitude)
  }

  function finishSavingLocation() {
    if (savingLocation && savingLocationQueryStarted) cancelEditingLocation()
  }

  function persistLocation(name, latitude, longitude) {
    if (name && latitude !== null && longitude !== null)
      locationSaveProc.command = ["omarchy-weather-location", "--set", name, latitude + "," + longitude]
    else if (name)
      locationSaveProc.command = ["omarchy-weather-location", "--set", name]
    else
      locationSaveProc.command = ["omarchy-weather-location", "--clear"]
    locationSaveProc.running = true
  }

  // Debounced geocoding. Only one curl runs at a time; if the query moved on
  // while a fetch was in flight, the latest query is fetched right after.
  function requestGeocode() {
    var query = locationField.text.trim()
    if (query.length < 2) {
      locationSuggestions = []
      return
    }
    geocodePendingQuery = query
    if (!geocodeProc.running) startGeocode()
  }

  function startGeocode() {
    geocodeActiveQuery = geocodePendingQuery
    geocodeProc.command = root.helperCmd("fetch",
      "https://geocoding-api.open-meteo.com/v1/search?name=" + encodeURIComponent(geocodeActiveQuery) + "&count=5&language=en&format=json", "5")
    geocodeProc.running = true
  }

  function buildForecastDays() {
    return Model.buildForecastDays(report, dailyForecastReport, Qt.formatDate(new Date(), "yyyy-MM-dd"))
  }

  function openMeteoForecastDays() {
    return Model.openMeteoForecastDays(dailyForecastReport, Qt.formatDate(new Date(), "yyyy-MM-dd"))
  }

  function wttrNextForecastDays() {
    return Model.wttrNextForecastDays(report, Qt.formatDate(new Date(), "yyyy-MM-dd"))
  }

  function isFutureForecastDate(dateString) {
    return Model.isFutureForecastDate(dateString, Qt.formatDate(new Date(), "yyyy-MM-dd"))
  }

  function roundedTemp(value) {
    return Model.roundedTemp(value)
  }

  function celsiusToFahrenheit(value) {
    return Model.celsiusToFahrenheit(value)
  }

  function formatTemp(value) {
    return Model.formatTemp(value, useImperial)
  }

  function dayName(dateString) {
    return Model.dayName(dateString, function(date) { return Qt.formatDate(date, "dddd") })
  }

  // Bare degree value (no unit letter), used in the forecast row.
  function bareTempForDay(day, kind) {
    return Model.bareTempForDay(day, kind, useImperial)
  }

  // Representative icon for a forecast day: the hourly entry nearest noon.
  function dayIcon(day) {
    return Model.dayIcon(day)
  }

  function forecastIcon(day, night) {
    if (!day || day.openMeteoWeatherCode === undefined || day.openMeteoWeatherCode === null)
      return root.dayIcon(day)
    return Model.iconForOpenMeteoCode(day.openMeteoWeatherCode, night)
  }

  function forecastDayLabel(dateString) {
    var today = Qt.formatDate(new Date(), "yyyy-MM-dd")
    var date = new Date(today + "T12:00:00")
    date.setDate(date.getDate() - 1)
    var yesterday = Qt.formatDate(date, "yyyy-MM-dd")
    if (String(dateString).slice(0, 10) === yesterday) return "YESTERDAY"
    if (String(dateString).slice(0, 10) === today) return "TODAY"
    return root.dayName(dateString).slice(0, 3).toUpperCase()
  }

  function showDailyDetails(dateString) {
    return root.forecastDayLabel(dateString) !== "YESTERDAY"
  }

  function forecastPrecipitation(day) {
    if (!day || day.precipitationProbability === undefined || day.precipitationProbability === null || day.precipitationProbability === "") return ""
    return Math.round(Number(day.precipitationProbability)) + "% rain"
  }

  function hourlyTemperature(hour) {
    if (!hour) return ""
    return root.useImperial ? hour.tempF + "°" : hour.tempC + "°"
  }

  function hourlyTime(hour) {
    return hour && hour.time ? String(hour.time).slice(11, 16) : ""
  }

  function iconForOpenMeteoCode(code) {
    return Model.iconForOpenMeteoCode(code)
  }

  // Mirrors omarchy-weather-icon's wttr.in code → nerd-font glyph mapping.
  function iconForCode(code, night) {
    return Model.iconForCode(code, night)
  }

  Process {
    id: forecastProc
    command: root.helperCmd("fetch", "https://wttr.in/" + root.locationQuery + "?format=j1", "10")
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        var next = root.appendBounded(root.forecastBuf, chunk)
        if (next === null) { root.forecastBuf = ""; forecastProc.signal(15); forecastKill.start(); return }
        root.forecastBuf = next
      }
    }
    onRunningChanged: if (running) forecastDeadline.restart(); else { forecastDeadline.stop(); forecastKill.stop() }
    onExited: function(exitCode) {
      var text = root.forecastBuf
      root.forecastBuf = ""
      var raw = String(text || "").trim()
      if (exitCode !== 0 || !raw) {
        root.scheduleForecastRetry()
        return
      }
      try {
        var parsed = Model.normalizeWttrResponse(JSON.parse(raw))
        if (!parsed) throw new Error("Invalid wttr response")
        root.report = parsed
        root.mapRevision++
        if (!root.hasConfiguredCoordinates)
          root.label = Model.provisionalCurrentIcon(parsed.current_condition && parsed.current_condition[0], root.label)
        root.forecastRetries = 0
        if (Model.weatherResponseCompletesSave(root.hasConfiguredCoordinates, "wttr"))
          root.finishSavingLocation()
        // Stored coordinates already drove the fast open-meteo fetch from
        // refresh(); only auto-detect needs the area wttr reported.
        if (isNaN(parseFloat(String(root.configuredLocationState.latitude))))
          root.refreshDailyForecast(parsed)
      } catch (e) {
        // Keep last-good report visible, but try again shortly.
        root.scheduleForecastRetry()
      }
    }
  }
  Timer { id: forecastDeadline; interval: root.procDeadlineMs; onTriggered: { forecastProc.signal(15); forecastKill.start() } }
  Timer { id: forecastKill; interval: 2000; onTriggered: forecastProc.signal(9) }

  // wttr.in can be slow or flaky, especially for a location it hasn't
  // cached yet. Retry a few times before leaving it to the refresh timer.
  function scheduleForecastRetry() {
    if (forecastRetries >= 3) return
    forecastRetries++
    forecastRetryTimer.restart()
  }

  Timer {
    id: forecastRetryTimer
    interval: 2500
    onTriggered: if (!forecastProc.running) forecastProc.running = true
  }

  // With configured coordinates this fetch is the only thing that updates the
  // bar icon, so a dropped response (e.g. waking before the network is back)
  // must retry rather than wait out the refresh timer with a stale icon.
  function scheduleDailyForecastRetry() {
    if (dailyForecastRetries >= 3) return
    dailyForecastRetries++
    dailyForecastRetryTimer.restart()
  }

  Timer {
    id: dailyForecastRetryTimer
    interval: 2500
    onTriggered: root.refreshDailyForecast(null)
  }

  Process {
    id: dailyForecastProc
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        var next = root.appendBounded(root.dailyForecastBuf, chunk)
        if (next === null) { root.dailyForecastBuf = ""; dailyForecastProc.signal(15); dailyForecastKill.start(); return }
        root.dailyForecastBuf = next
      }
    }
    onRunningChanged: if (running) dailyForecastDeadline.restart(); else { dailyForecastDeadline.stop(); dailyForecastKill.stop() }
    onExited: function(exitCode) {
      var text = root.dailyForecastBuf
      root.dailyForecastBuf = ""
      var raw = String(text || "").trim()
      if (exitCode !== 0 || !raw) {
        root.scheduleDailyForecastRetry()
        return
      }
      try {
        var parsed = JSON.parse(raw)
        var parsedCurrent = Model.openMeteoCurrentCondition(parsed)
        root.dailyForecastReport = parsed
        root.label = Model.currentIcon(parsedCurrent, root.label)
        root.dailyForecastRetries = 0
        if (Model.weatherResponseCompletesSave(root.hasConfiguredCoordinates, "open-meteo"))
          root.finishSavingLocation()
      } catch (e) {
        // Keep last-good daily forecast visible, but try again shortly.
        root.scheduleDailyForecastRetry()
      }
    }
  }
  Timer { id: dailyForecastDeadline; interval: root.procDeadlineMs; onTriggered: { dailyForecastProc.signal(15); dailyForecastKill.start() } }
  Timer { id: dailyForecastKill; interval: 2000; onTriggered: dailyForecastProc.signal(9) }

  Process {
    id: geocodeProc
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        var next = root.appendBounded(root.geocodeBuf, chunk)
        if (next === null) { root.geocodeBuf = ""; geocodeProc.signal(15); geocodeKill.start(); return }
        root.geocodeBuf = next
      }
    }
    onRunningChanged: if (running) geocodeDeadline.restart(); else { geocodeDeadline.stop(); geocodeKill.stop() }
    onExited: function(exitCode) {
      var text = root.geocodeBuf
      root.geocodeBuf = ""
      root.locationSuggestions = root.editingLocation ? Model.parseGeocodingResults(text) : []
      root.suggestionIndex = 0
      if (root.geocodePendingQuery !== root.geocodeActiveQuery) Qt.callLater(root.startGeocode)
    }
  }
  Timer { id: geocodeDeadline; interval: root.procDeadlineMs; onTriggered: { geocodeProc.signal(15); geocodeKill.start() } }
  Timer { id: geocodeKill; interval: 2000; onTriggered: geocodeProc.signal(9) }

  Timer {
    id: geocodeDebounce
    interval: 300
    onTriggered: root.requestGeocode()
  }

  Process {
    id: locationSaveProc
    onRunningChanged: if (running) locationSaveDeadline.restart(); else { locationSaveDeadline.stop(); locationSaveKill.stop() }
    onExited: function(exitCode) {
      if (exitCode !== 0 || !root.savingLocation) return

      // The state helper handles changed locations. Explicitly refresh here too so
      // saving the already-active location cannot strand the spinner.
      locationFile.reload()
      if (!root.savingLocationQueryStarted) {
        root.savingLocationQueryStarted = true
        root.forecastRetries = 0
        root.dailyForecastRetries = 0
        forecastProc.running = false
        dailyForecastProc.running = false
        Qt.callLater(root.refresh)
      }
    }
  }
  Timer { id: locationSaveDeadline; interval: root.procDeadlineMs; onTriggered: { locationSaveProc.signal(15); locationSaveKill.start() } }
  Timer { id: locationSaveKill; interval: 2000; onTriggered: locationSaveProc.signal(9) }

  Process {
    id: locationProc
    command: root.helperCmd("fetch", "https://wttr.in/?format=%l", "4")
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        var next = root.appendBounded(root.locationProcBuf, chunk)
        if (next === null) { root.locationProcBuf = ""; locationProc.signal(15); locationProcKill.start(); return }
        root.locationProcBuf = next
      }
    }
    onRunningChanged: if (running) locationProcDeadline.restart(); else { locationProcDeadline.stop(); locationProcKill.stop() }
    onExited: function(exitCode) {
      var text = root.locationProcBuf
      root.locationProcBuf = ""
      if (exitCode !== 0) return
      var raw = String(text || "").trim()
      if (!raw) return
      root.wttrLocation = raw.split(",")[0].slice(0, 128)
    }
  }
  Timer { id: locationProcDeadline; interval: root.procDeadlineMs; onTriggered: { locationProc.signal(15); locationProcKill.start() } }
  Timer { id: locationProcKill; interval: 2000; onTriggered: locationProc.signal(9) }

  Component.onDestruction: {
    radarGeocodeProc.signal(15)
    locationFile.signal(15)
    panelStateFile.signal(15)
    panelStateSaveProc.signal(15)
    forecastProc.signal(15)
    dailyForecastProc.signal(15)
    geocodeProc.signal(15)
    locationSaveProc.signal(15)
    locationProc.signal(15)
  }

  Timer {
    id: refreshTimer
    interval: root.refreshMinutes * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  IpcHandler {
    target: root.ipcTarget

    function open() { root.openFromHotkey() }
    function close() { root.close() }
    function show() { root.openFromHotkey() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
    function edit() { root.openFromHotkey(); root.startEditingLocation() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    // Location TextField owns Escape while editing (cancel); otherwise ESC
    // must dismiss the panel. Mirrored on KeyboardPanel so its Application
    // Shortcut stays disabled during edit even if focus drifts.
    escapeBlocked: root.editingLocation
    contentWidth: Style.space(500)
    contentHeight: panel.fittedContentHeight(weatherColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editingLocation
      onReturnRequested: root.startEditingLocation()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      // Belt-and-braces with KeyboardPanel's Escape Shortcut / Keys.onPressed
      // (same pattern as Media.qml): keeps dismiss working when a child stole
      // activeFocus after a click inside the scroll area.
      Keys.onEscapePressed: function(event) {
        if (root.editingLocation) return
        root.close()
        event.accepted = true
      }

      Flickable {
        id: weatherScroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: weatherColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: weatherColumn
          width: Style.space(500)
          spacing: Style.space(14)

      // ---- Hero row: big icon + temp on the left; location and stats stacked on the right.
      Item {
        width: parent.width
        height: Math.max(heroLeft.height, heroRight.height)

        Row {
          id: heroLeft
          anchors.left: parent.left
          anchors.leftMargin: Style.space(16)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(16)

          Text {
            textFormat: Text.PlainText
            id: heroIcon
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 5
            text: root.label || "—"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            // Decorative condition glyph, scaled from the active theme.
            font.pixelSize: Style.font.displayLarge * 2.25
          }

          Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              id: tempBig
              text: root.reportTempNum || "—"
              textFormat: Text.PlainText
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              // Hero temperature read-out, scaled from the active theme.
              font.pixelSize: Style.font.displayLarge * 2
              font.bold: true

              MouseArea {
                id: tempHover
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton

                PanelToolTip {
                  visible: tempHover.containsMouse
                  text: "Temperature: " + (root.reportTempNum || "—") + root.tempUnit
                  fontFamily: root.bar.fontFamily
                }
              }
            }
            Text {
              text: root.current ? root.tempUnit : ""
              textFormat: Text.PlainText
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.display
              anchors.top: tempBig.top
              anchors.topMargin: Style.space(10)
            }

          }
        }

        Column {
          id: heroRight
          // The edit row contains a 190px field, spacing, and a clear button.
          // Reserve enough width for all of it so it cannot escape the panel.
          width: Math.max(weatherStats.implicitWidth, root.editingLocation ? Style.space(230) : Style.space(150))
          anchors.right: parent.right
          anchors.rightMargin: Style.space(70)
          anchors.top: parent.top
          anchors.topMargin: Style.space(8)
          spacing: Style.space(12)

          Row {
            visible: !root.editingLocation
            spacing: Style.space(6)

            Text {
              textFormat: Text.PlainText
              text: ""  // nf-fa-map_marker
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
            }

            Item {
              width: cityName.implicitWidth
              height: cityName.implicitHeight

              Text {
                id: cityName
                anchors.fill: parent
                text: root.locationDisplay.toUpperCase()
                textFormat: Text.PlainText
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                font.letterSpacing: 1
              }

              MouseArea {
                id: cityHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.startEditingLocation()
              }
            }

          }

          Row {
            visible: root.editingLocation
            spacing: Style.space(6)

            TextField {
              id: locationField
              width: Style.space(190)
              enabled: !root.savingLocation
              placeholderText: "Search city"
              foreground: root.bar.foreground
              font.family: root.bar.fontFamily

              onTextChanged: if (root.editingLocation && !root.savingLocation) geocodeDebounce.restart()

              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  root.cancelEditingLocation()
                  event.accepted = true
                } else if (event.key === Qt.Key_Down) {
                  if (root.suggestionIndex < root.locationSuggestions.length - 1) root.suggestionIndex++
                  event.accepted = true
                } else if (event.key === Qt.Key_Up) {
                  if (root.suggestionIndex > 0) root.suggestionIndex--
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  root.commitLocation()
                  event.accepted = true
                }
              }
            }

            // Clear back to IP auto-detect. While a committed location is
            // loading, this same compact affordance becomes a spinner.
            Rectangle {
              width: Style.space(18)
              height: Style.space(18)
              anchors.verticalCenter: parent.verticalCenter
              radius: Math.min(4, Style.cornerRadius)
              color: !root.savingLocation && clearLocationArea.containsMouse ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"

              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: root.savingLocation ? "󰦖" : "✕"
                font.family: root.bar.fontFamily
                color: Qt.darker(root.bar.foreground, 1.4)
                font.pixelSize: Style.font.bodySmall

                RotationAnimator on rotation {
                  running: root.savingLocation
                  from: 0; to: 360
                  duration: 800
                  loops: Animation.Infinite
                }
              }

              MouseArea {
                id: clearLocationArea
                anchors.fill: parent
                enabled: !root.savingLocation
                hoverEnabled: true
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.clearLocation()
              }
            }
          }

          Row {
            id: weatherStats
            visible: !!root.current
            spacing: Style.space(20)

            Column {
              spacing: Style.space(5)
              Text {
                textFormat: Text.PlainText
                text: "FEELS"
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }
              Text {
                text: root.reportFeels
                textFormat: Text.PlainText
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
              }
            }

            Column {
              spacing: Style.space(5)
              Text {
                textFormat: Text.PlainText
                text: "WIND"
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }
              Text {
                text: root.reportWind
                textFormat: Text.PlainText
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
                MouseArea {
                  id: windHover
                  anchors.fill: parent
                  hoverEnabled: true
                  acceptedButtons: Qt.NoButton

                  PanelToolTip {
                    visible: windHover.containsMouse
                    text: "Wind: " + root.reportWind
                    fontFamily: root.bar.fontFamily
                  }
                }
              }
            }

            Column {
              spacing: Style.space(5)
              Text {
                textFormat: Text.PlainText
                text: "HUMID"
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }
              Text {
                text: root.reportHumidity
                textFormat: Text.PlainText
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
                MouseArea {
                  id: humidityHover
                  anchors.fill: parent
                  hoverEnabled: true
                  acceptedButtons: Qt.NoButton

                  PanelToolTip {
                    visible: humidityHover.containsMouse
                    text: "Humidity: " + root.reportHumidity
                    fontFamily: root.bar.fontFamily
                  }
                }
              }
            }
          }
        }

      }

      // ---- Geocoding suggestions while the location is being edited.
      Column {
        visible: root.editingLocation && !root.savingLocation && root.locationSuggestions.length > 0
        width: parent.width
        spacing: 0

        Repeater {
          model: root.locationSuggestions

          Rectangle {
            required property var modelData
            required property int index
            width: parent.width
            height: suggestionRow.implicitHeight + Style.space(12)
            radius: Style.cornerRadius
            color: index === root.suggestionIndex ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"

            Row {
              id: suggestionRow
              anchors.left: parent.left
              anchors.leftMargin: Style.space(16)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)

              Text {
                text: modelData.name
                textFormat: Text.PlainText
                color: index === root.suggestionIndex ? Style.hoverStateColor(root.bar.foreground, Color.accent) : root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
              }
              Text {
                visible: text !== ""
                text: modelData.description
                textFormat: Text.PlainText
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onPositionChanged: root.suggestionIndex = index
              onClicked: root.pickSuggestion(modelData)
            }
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        visible: !root.current
        text: "Fetching forecast…"
        color: Qt.darker(root.bar.foreground, 1.5)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.italic: true
      }

      // ---- Divider between current conditions and forecast.
      Rectangle {
        visible: root.forecastTimeline.length > 0
        width: parent.width
        height: Style.spacing.hairline
        color: root.bar.foreground
        opacity: 0.12
      }

      Loader {
        id: todayLoader
        width: parent.width
        height: item ? item.implicitHeight : 0
        active: false
        Component.onCompleted: {
          sourceComponent = todaySectionComponent
          active = true
        }
      }

      Rectangle {
        visible: !!root.todayForecast
        width: parent.width
        height: Style.spacing.hairline
        color: root.bar.foreground
        opacity: 0.12
      }

      // ---- Seven-day forecast list with precipitation, day/night symbols,
      //      and high/low temperatures aligned like a weather app forecast.
      Item {
        visible: root.forecastDays.length > 0
        width: parent.width
        height: forecastList.implicitHeight

        Column {
          id: forecastList
          width: parent.width
          spacing: Style.space(8)

          Repeater {
            model: root.forecastTimeline

            Row {
              required property var modelData
              required property int index
              width: forecastList.width
              height: Style.space(38)
              spacing: Style.space(6)

              Text {
                width: Style.space(100)
                text: root.forecastDayLabel(modelData.date)
                textFormat: Text.PlainText
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                width: Style.space(64)
                opacity: root.showDailyDetails(modelData.date) ? 1 : 0
                text: root.forecastPrecipitation(modelData) || "—"
                textFormat: Text.PlainText
                color: Qt.darker(root.bar.foreground, 1.3)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                horizontalAlignment: Text.AlignHCenter
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                textFormat: Text.PlainText
                width: Style.space(42)
                opacity: root.showDailyDetails(modelData.date) ? 1 : 0
                text: root.forecastIcon(modelData, false)
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.display
                horizontalAlignment: Text.AlignHCenter
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                textFormat: Text.PlainText
                width: Style.space(42)
                opacity: root.showDailyDetails(modelData.date) ? 1 : 0
                text: root.forecastIcon(modelData, true)
                color: Qt.darker(root.bar.foreground, 1.15)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.display
                horizontalAlignment: Text.AlignHCenter
                anchors.verticalCenter: parent.verticalCenter
              }

              Item {
                width: Math.max(0, forecastList.width - Style.space(430))
                height: 1
              }

              Text {
                width: Style.space(140)
                transform: Translate { x: -Style.space(50) }
                text: root.bareTempForDay(modelData, "max") + " / " + root.bareTempForDay(modelData, "min")
                textFormat: Text.PlainText
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.NoWrap
                horizontalAlignment: Text.AlignRight
                anchors.verticalCenter: parent.verticalCenter
              }
            }
          }
        }
      }

      // ---- Detailed forecast for today.
      Component {
        id: todaySectionComponent

        Column {
          visible: !!root.todayForecast
          width: parent.width
          spacing: Style.space(8)

        Text {
          textFormat: Text.PlainText
          text: "TODAY"
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1
        }

        Row {
          width: parent.width
          spacing: Style.space(12)

          Text {
            textFormat: Text.PlainText
            text: root.dayIcon(root.todayForecast)
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: root.todayForecast ? root.dayName(root.todayForecast.date) : ""
              textFormat: Text.PlainText
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
            }
            Text {
              text: root.todayForecast ? root.bareTempForDay(root.todayForecast, "max") + " / " + root.bareTempForDay(root.todayForecast, "min") : ""
              textFormat: Text.PlainText
              color: Qt.darker(root.bar.foreground, 1.3)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
            }
          }

          Item { width: Math.max(0, parent.width - 230); height: 1 }

          Text {
            width: Style.space(70)
            visible: root.forecastPrecipitation(root.todayForecast) !== ""
            text: root.forecastPrecipitation(root.todayForecast)
            textFormat: Text.PlainText
            color: Qt.darker(root.bar.foreground, 1.3)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.NoWrap
            horizontalAlignment: Text.AlignRight
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Item {
          visible: root.todayHourlyForecast.length > 0
          width: parent.width
          height: hourlyFlickable.height + Style.space(14)

          Flickable {
            id: hourlyFlickable
            width: parent.width
            height: hourlyRow.height
            contentWidth: Math.max(width, hourlyRow.implicitWidth)
            contentHeight: height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.HorizontalFlick
            interactive: contentWidth > width

            // A button-less MouseArea receives wheel events without taking
            // over the Flickable's normal click-and-drag interaction.
            MouseArea {
              anchors.fill: parent
              z: 1
              acceptedButtons: Qt.NoButton
              onWheel: function(wheel) { root.scrollHorizontally(hourlyFlickable, wheel) }
            }

            Row {
              id: hourlyRow
              width: implicitWidth
              spacing: Style.space(8)

              Repeater {
                model: root.todayHourlyForecast

                Column {
                  required property var modelData
                  width: Style.space(48)
                  spacing: Style.space(3)

                  Text {
                    width: parent.width
                    text: root.hourlyTime(modelData)
                    textFormat: Text.PlainText
                    color: Qt.darker(root.bar.foreground, 1.4)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    horizontalAlignment: Text.AlignHCenter
                  }
                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: root.dayIcon(modelData)
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.body
                    horizontalAlignment: Text.AlignHCenter
                  }
                  Text {
                    width: parent.width
                    text: root.hourlyTemperature(modelData)
                    textFormat: Text.PlainText
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    horizontalAlignment: Text.AlignHCenter
                  }
                }
              }

              // Trailing space lets the final hour scroll fully into view
              // instead of stopping with its text clipped at the edge.
              Item {
                width: Style.space(24)
                height: 1
              }
            }
          }

          Rectangle {
            visible: hourlyFlickable.contentWidth > hourlyFlickable.width
            y: hourlyFlickable.height + Style.space(10)
            width: parent.width
            height: Style.space(8)
            radius: height / 2
            color: Qt.darker(root.bar.foreground, 2.2)
            opacity: 0.25

            Rectangle {
              width: Math.max(Style.space(24), parent.width * hourlyFlickable.width / hourlyFlickable.contentWidth)
              height: parent.height
              radius: height / 2
              x: (parent.width - width) * (hourlyFlickable.contentX / Math.max(1, hourlyFlickable.contentWidth - hourlyFlickable.width))
              color: root.bar.foreground
              opacity: 0.75
            }

            MouseArea {
              anchors.fill: parent
              preventStealing: true
              onPressed: function(mouse) {
                var ratio = Math.max(0, Math.min(1, mouse.x / width))
                hourlyFlickable.contentX = ratio * Math.max(0, hourlyFlickable.contentWidth - hourlyFlickable.width)
              }
              onPositionChanged: function(mouse) {
                if (!pressed) return
                var ratio = Math.max(0, Math.min(1, mouse.x / width))
                hourlyFlickable.contentX = ratio * Math.max(0, hourlyFlickable.contentWidth - hourlyFlickable.width)
              }
            }
          }
        }

        }
      }

        Rectangle {
          visible: root.activities.length > 0
          width: parent.width
          height: Style.spacing.hairline
          color: root.bar.foreground
          opacity: 0.12
        }

        Column {
          visible: root.activities.length > 0
          width: parent.width
          spacing: Style.space(8)

          Item {
            width: parent.width
            height: Style.space(18)

            Text {
              textFormat: Text.PlainText
              id: activityTitle
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "ACTIVITY FORECASTS"
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
            }

            Text {
              textFormat: Text.PlainText
              id: activityToggle
              anchors.left: activityTitle.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(8)
              width: Style.space(34)
              text: root.activitiesExpanded ? "[-]" : "[+]"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignRight

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.activitiesExpanded = !root.activitiesExpanded
                  root.savePanelState()
                }
              }
            }

            MouseArea {
              anchors.left: activityTitle.left
              anchors.right: activityTitle.right
              anchors.verticalCenter: activityTitle.verticalCenter
              height: activityTitle.height + Style.space(8)
              onClicked: {
                root.activitiesExpanded = !root.activitiesExpanded
                root.savePanelState()
              }
            }
          }

          Item {
            visible: root.activitiesExpanded
            width: parent.width
            height: activityFlickable.height + Style.space(14)

            Flickable {
              id: activityFlickable
              width: parent.width
              height: activityRow.height
              contentWidth: Math.max(width, activityRow.width)
              contentHeight: height
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              flickableDirection: Flickable.HorizontalFlick
              interactive: contentWidth > width

              MouseArea {
                anchors.fill: parent
                z: 1
                acceptedButtons: Qt.NoButton
                onWheel: function(wheel) { root.scrollHorizontally(activityFlickable, wheel) }
              }

              Row {
                id: activityRow
                spacing: Style.space(8)

                Repeater {
                  model: root.activities

                  Rectangle {
                    required property var modelData
                    width: Style.space(140)
                    height: Style.space(64)
                    radius: Style.cornerRadius
                    color: Style.hoverFillFor(root.bar.foreground, modelData.status === "Good" ? Color.accent : root.bar.foreground)
                    opacity: 0.85

                    Column {
                      id: activityContent
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.leftMargin: Style.space(8)
                      anchors.rightMargin: Style.space(8)
                      spacing: Style.space(3)

                      Text {
                        textFormat: Text.PlainText
                        text: modelData.symbol + "  " + modelData.name
                        color: root.bar.foreground
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        font.bold: true
                      }
                      Text {
                        textFormat: Text.PlainText
                        text: modelData.status
                        color: root.bar.foreground
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.bodySmall
  }
}
                  }
                }
              }
            }

            Rectangle {
              visible: activityFlickable.contentWidth > activityFlickable.width
              y: activityFlickable.height + Style.space(6)
              width: parent.width
              height: Style.space(8)
              radius: height / 2
              color: Qt.darker(root.bar.foreground, 2.2)
              opacity: 0.25

              Rectangle {
                width: Math.max(Style.space(24), parent.width * activityFlickable.width / activityFlickable.contentWidth)
                height: parent.height
                radius: height / 2
                x: (parent.width - width) * (activityFlickable.contentX / Math.max(1, activityFlickable.contentWidth - activityFlickable.width))
                color: root.bar.foreground
                opacity: 0.75
              }

              MouseArea {
                anchors.fill: parent
                preventStealing: true
                onPressed: function(mouse) {
                  var ratio = Math.max(0, Math.min(1, mouse.x / width))
                  activityFlickable.contentX = ratio * Math.max(0, activityFlickable.contentWidth - activityFlickable.width)
                }
                onPositionChanged: function(mouse) {
                  if (!pressed) return
                  var ratio = Math.max(0, Math.min(1, mouse.x / width))
                  activityFlickable.contentX = ratio * Math.max(0, activityFlickable.contentWidth - activityFlickable.width)
                }
              }
            }
          }
        }

      Rectangle {
        visible: root.hasRadarCoordinates
        width: parent.width
        height: Style.spacing.hairline
        color: root.bar.foreground
        opacity: 0.12
      }

      Column {
        visible: root.hasRadarCoordinates
        width: parent.width
        spacing: Style.space(8)

        Item {
          width: parent.width
          height: Style.space(20)

          Text {
            textFormat: Text.PlainText
            id: mapsTitle
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "RADAR AND MAPS"
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            font.letterSpacing: 1
          }

          Text {
            textFormat: Text.PlainText
            id: mapsToggle
            anchors.left: mapsTitle.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(8)
            width: Style.space(34)
            text: root.mapsExpanded ? "[-]" : "[+]"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignRight

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.mapsExpanded = !root.mapsExpanded
                root.savePanelState()
              }
            }
          }

          MouseArea {
            anchors.left: mapsTitle.left
            anchors.right: mapsTitle.right
            anchors.verticalCenter: mapsTitle.verticalCenter
            height: mapsTitle.height + Style.space(8)
            onClicked: {
              root.mapsExpanded = !root.mapsExpanded
              root.savePanelState()
            }
          }
        }

        Column {
          visible: root.mapsExpanded
          width: parent.width
          spacing: Style.space(10)

          Text {
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Map tiles are not loaded inside the shell. Open the radar map in your browser instead."
            color: Qt.darker(root.bar.foreground, 1.2)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
          }

          Button {
            text: "Open radar map"
            bordered: true
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onClicked: root.openRadarInBrowser()
          }
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: "Current temperature of approximately " + (root.reportTempNum || "—") + root.tempUnit
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
        }
      }
    }
  }
  }
  }
}

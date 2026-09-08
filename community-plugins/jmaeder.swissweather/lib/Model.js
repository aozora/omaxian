// Parsing and normalisation of everything the plugin reads.
//
// Two rules run through this file.
//
// Nothing that arrives over the network is trusted. Every number is range
// checked against what the quantity can physically be, every array is length
// capped, every string is stripped of control characters and truncated. A
// response that is malformed, hostile, or simply a MeteoSwiss format change
// yields nulls and short arrays — never an exception that would take the
// panel down with it, and never an unbounded allocation inside the shared
// omarchy-shell process.
//
// Nothing fails loudly. Each parser returns a well-formed empty value on bad
// input so the panel keeps showing the last good reading instead of blanking.
// The panel decides what to tell the user; the model just refuses to lie.

// Length ceilings. Real payloads are far below these; they exist so a
// truncated, padded, or hostile response cannot grow the shell's heap.
var MAX_CSV_ROWS = 500
var MAX_SERIES_POINTS = 400
var MAX_FORECAST_DAYS = 10
var MAX_WARNINGS = 6
var MAX_TEXT_LENGTH = 400
// A warning is written as a short list of labelled points — impacts, advice,
// expected amounts — and reads as a wall of text if that structure is thrown
// away. These ceilings keep the structure while still bounding the payload.
var MAX_WARNING_LINES = 10
var MAX_WARNING_LINE_LENGTH = 300

// Warnings already notified, remembered so the same one does not pop up at
// every refresh. Bounded because it is written to disk and read back: a
// forgotten warning is a duplicate notification, which is a nuisance, while an
// unbounded list is a file that grows for as long as the plugin is installed.
var MAX_SEEN_WARNINGS = 40
var MAX_KEY_LENGTH = 64

// The danger level at or above which a warning is worth interrupting someone.
// Below it MeteoSwiss is describing conditions rather than raising an alarm:
// level 2 covers an ordinary rainy afternoon, and level 1 a standing cantonal
// notice that can sit in force for a whole summer.
var NOTIFY_LEVEL = 3
var MAX_NAME_LENGTH = 80
// Not a product limit — the panel lets you keep as many towns as you like.
// This only stops a corrupt or hand-edited state file from making the shell
// build an unbounded chip row and fire one request per entry.
var MAX_FAVOURITES = 24

// Plausibility bounds, one per physical quantity. A value outside its bound is
// treated as absent: better a blank field than a confidently wrong reading.
var BOUNDS = {
  temperature: { min: -60, max: 60 },
  precipitation: { min: 0, max: 500 },
  wind: { min: 0, max: 500 },
  direction: { min: 0, max: 360 },
  sunshine: { min: 0, max: 60 },
  humidity: { min: 0, max: 100 },
  pressure: { min: 500, max: 1100 },
  probability: { min: 0, max: 100 },
  latitude: { min: -90, max: 90 },
  longitude: { min: -180, max: 180 }
}

// ------------------------------------------------------------------ scalars

/** Finite number within `bounds`, or null. Rejects "", "-", NaN and Infinity. */
function number(value, bounds) {
  if (value === undefined || value === null) return null
  var text = String(value).replace(/^\s+|\s+$/g, "")
  if (text === "" || text === "-") return null
  var n = Number(text)
  if (!isFinite(n)) return null
  if (bounds && (n < bounds.min || n > bounds.max)) return null
  return n
}

/**
 * Text safe to hand to a QML Text item: control characters removed, length
 * capped. The caller must still render it with `textFormat: Text.PlainText`,
 * since remote text reaching an AutoText item would be parsed as markup.
 */
function text(value, maxLength) {
  var raw = String(value === undefined || value === null ? "" : value)
  var out = ""
  var limit = maxLength || MAX_TEXT_LENGTH
  for (var i = 0; i < raw.length && out.length < limit; i++) {
    var code = raw.charCodeAt(i)
    if (code < 32 || code === 127) {
      // Collapse newlines and tabs to a space; drop the rest outright.
      if (code === 9 || code === 10 || code === 13) out += " "
      continue
    }
    out += raw.charAt(i)
  }
  return out.replace(/\s+/g, " ").replace(/^ | $/g, "")
}

/** Array of numbers within bounds, length capped; unusable entries become null. */
function numberSeries(value, bounds) {
  if (!Array.isArray(value)) return []
  var out = []
  var limit = Math.min(value.length, MAX_SERIES_POINTS)
  for (var i = 0; i < limit; i++) out.push(number(value[i], bounds))
  return out
}

function epochMs(value) {
  var n = number(value, null)
  if (n === null) return null
  // Anything outside 2000-2100 is a unit mix-up (seconds passed as
  // milliseconds, or the reverse) rather than a timestamp we should trust.
  if (n < 946684800000 || n > 4102444800000) return null
  return n
}

// -------------------------------------------------------------- date & time

/** "202608200920" (UTC, as VQHA80 writes it) to a Date, or null. */
function parseCompactUtc(value) {
  var stamp = String(value || "").replace(/^\s+|\s+$/g, "")
  if (!/^[0-9]{12}$/.test(stamp)) return null
  var year = parseInt(stamp.substring(0, 4), 10)
  var month = parseInt(stamp.substring(4, 6), 10)
  var day = parseInt(stamp.substring(6, 8), 10)
  var hour = parseInt(stamp.substring(8, 10), 10)
  var minute = parseInt(stamp.substring(10, 12), 10)
  if (month < 1 || month > 12 || day < 1 || day > 31 || hour > 23 || minute > 59) return null

  var date = new Date(Date.UTC(year, month - 1, day, hour, minute))
  if (isNaN(date.getTime())) return null
  // Round-trip check catches impossible dates that Date.UTC silently rolls
  // over, such as the 31st of February.
  if (date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) return null
  return date
}

function pad2(value) {
  var n = Math.floor(Math.abs(Number(value) || 0))
  return (n < 10 ? "0" : "") + n
}

/** 24-hour local clock, the convention in all three of the plugin's languages. */
function formatClock(date) {
  if (!date || isNaN(date.getTime())) return ""
  return pad2(date.getHours()) + ":" + pad2(date.getMinutes())
}

/** DD.MM.YYYY — the Swiss date order, used regardless of panel language. */
function formatDate(date) {
  if (!date || isNaN(date.getTime())) return ""
  return pad2(date.getDate()) + "." + pad2(date.getMonth() + 1) + "." + date.getFullYear()
}

/** DD.MM, for the compact day headings in the week view. */
function formatDayMonth(date) {
  if (!date || isNaN(date.getTime())) return ""
  return pad2(date.getDate()) + "." + pad2(date.getMonth() + 1)
}

/** "YYYY-MM-DD" as it arrives in the daily forecast, to a local-midnight Date. */
function parseIsoDate(value) {
  var match = /^([0-9]{4})-([0-9]{2})-([0-9]{2})$/.exec(String(value || ""))
  if (!match) return null
  var date = new Date(parseInt(match[1], 10), parseInt(match[2], 10) - 1, parseInt(match[3], 10))
  return isNaN(date.getTime()) ? null : date
}

/** Local midnight of the day containing `date`. */
function startOfDay(date) {
  var d = new Date(date.getTime())
  d.setHours(0, 0, 0, 0)
  return d
}

// ---------------------------------------------------- measurements (VQHA80)

// The VQHA80 columns this plugin reads, with the bound each is checked against.
// Full legend: data.geo.admin.ch/ch.meteoschweiz.messwerte-aktuell/info/
var MEASUREMENT_PARAMETERS = {
  tre200s0: "temperature",   // air temperature 2 m, instantaneous, °C
  rre150z0: "precipitation", // precipitation, 10-minute total, mm
  sre000z0: "sunshine",      // sunshine duration, 10-minute total, min
  gre000z0: null,            // global radiation, 10-minute mean, W/m² (unbounded here)
  ure200s0: "humidity",      // relative humidity 2 m, instantaneous, %
  dkl010z0: "direction",     // wind direction, 10-minute mean, °
  fu3010z0: "wind",          // wind speed, 10-minute mean, km/h
  fu3010z1: "wind",          // gust peak, maximum, km/h
  pp0qffs0: "pressure"       // pressure reduced to sea level (QFF), hPa
}

/**
 * Parses VQHA80.csv — the latest 10-minute values for every SMN station — into
 * `{ STATION_ABBR: { time, temperature, precipitation, ... } }`.
 *
 * Columns are located by header name rather than by position, so MeteoSwiss
 * adding or reordering a parameter costs nothing.
 */
function parseMeasurements(raw) {
  var lines = String(raw || "").split("\n")
  if (lines.length < 2) return {}

  var header = lines[0].split(";")
  var columnOf = {}
  for (var h = 0; h < header.length; h++) {
    columnOf[String(header[h]).replace(/^\s+|\s+$/g, "")] = h
  }
  if (columnOf["Station/Location"] === undefined || columnOf["Date"] === undefined) return {}

  var stations = {}
  var rows = Math.min(lines.length, MAX_CSV_ROWS + 1)
  for (var i = 1; i < rows; i++) {
    var line = lines[i]
    if (line === "") continue
    var cells = line.split(";")

    var abbr = String(cells[columnOf["Station/Location"]] || "").replace(/^\s+|\s+$/g, "").toUpperCase()
    if (!/^[A-Z0-9]{2,5}$/.test(abbr)) continue
    var time = parseCompactUtc(cells[columnOf["Date"]])
    if (time === null) continue

    var record = { abbr: abbr, time: time }
    for (var key in MEASUREMENT_PARAMETERS) {
      var column = columnOf[key]
      var bound = MEASUREMENT_PARAMETERS[key]
      record[key] = column === undefined ? null : number(cells[column], bound ? BOUNDS[bound] : null)
    }
    stations[abbr] = record
  }
  return stations
}

// --------------------------------------------------------------- forecast

/**
 * Puts a 10-90 % band into a usable shape: ends in order, and wide enough to
 * contain the central value.
 *
 * The forecast service does occasionally publish a band that says nothing —
 * ten-minute precipitation slots turn up with min 0.3, expected 1.8 and max
 * 0.0. Rendering that verbatim gives "0.1-0.0 mm/h", which is not a range and
 * not a fact. Ordering the ends and stretching them over the expected value
 * keeps the band honest about how uncertain the hour is without inventing a
 * number the forecast did not give.
 *
 * Returns null when neither end is usable, so "no band published" stays
 * distinguishable from "a band of zero width".
 */
function orderedBand(low, high, value) {
  var a = number(low, null)
  var b = number(high, null)
  var centre = number(value, null)

  if (a === null && b === null) return null
  if (a === null) a = b
  if (b === null) b = a

  var lowEnd = Math.min(a, b)
  var highEnd = Math.max(a, b)
  if (centre !== null) {
    lowEnd = Math.min(lowEnd, centre)
    highEnd = Math.max(highEnd, centre)
  }
  return { low: lowEnd, high: highEnd }
}

/** One time series plus the grid it sits on, so callers never re-derive it. */
function series(values, startMs, stepMs) {
  return { values: values || [], startMs: startMs, stepMs: stepMs }
}

/** Timestamp of index `i` in a series, or null when the series has no grid. */
function seriesTime(s, index) {
  if (!s || s.startMs === null || s.startMs === undefined) return null
  return s.startMs + index * s.stepMs
}

/**
 * Values of `s` that fall inside [fromMs, toMs), as `{ time, value }` points.
 * Points whose value is null are dropped: a gap should break the line rather
 * than be drawn through as if it were zero.
 */
function sliceSeries(s, fromMs, toMs) {
  var points = []
  if (!s || !s.values || s.startMs === null || s.startMs === undefined) return points
  for (var i = 0; i < s.values.length; i++) {
    var time = s.startMs + i * s.stepMs
    if (time < fromMs) continue
    if (time >= toMs) break
    if (s.values[i] === null) continue
    points.push({ time: time, value: s.values[i] })
  }
  return points
}

/** Value of `s` at or immediately before `atMs`, or null. */
function valueAt(s, atMs) {
  if (!s || !s.values || s.startMs === null || s.startMs === undefined) return null
  var index = Math.floor((atMs - s.startMs) / s.stepMs)
  if (index < 0 || index >= s.values.length) return null
  return s.values[index]
}

var HOUR_MS = 3600000
var TEN_MINUTES_MS = 600000

/**
 * Normalises the forecast service's response.
 *
 * The hourly grids are implicit in the payload and worth stating once here:
 * `start` is the base of the hourly and three-hourly series; the ten-minute
 * precipitation series also begins at `start` and runs until
 * `startLowResolution`, from where the hourly precipitation series takes over.
 * Together the two cover the same six-day window as the temperature series.
 */
function parseForecast(raw) {
  var empty = { valid: false, current: null, days: [], graph: null, warnings: [] }

  var data
  try {
    data = JSON.parse(String(raw || ""))
  } catch (e) {
    return empty
  }
  if (!data || typeof data !== "object" || Array.isArray(data)) return empty

  var result = { valid: true, current: null, days: [], graph: null, warnings: [] }

  var current = data.currentWeather
  if (current && typeof current === "object") {
    result.current = {
      time: epochMs(current.time),
      icon: symbolCode(current.iconV2 !== undefined ? current.iconV2 : current.icon),
      temperature: number(current.temperature, BOUNDS.temperature)
    }
  }

  if (Array.isArray(data.forecast)) {
    var dayCount = Math.min(data.forecast.length, MAX_FORECAST_DAYS)
    for (var d = 0; d < dayCount; d++) {
      var day = data.forecast[d]
      if (!day || typeof day !== "object") continue
      var date = parseIsoDate(day.dayDate)
      if (date === null) continue
      result.days.push({
        date: date,
        icon: symbolCode(day.iconDayV2 !== undefined ? day.iconDayV2 : day.iconDay),
        temperatureMin: number(day.temperatureMin, BOUNDS.temperature),
        temperatureMax: number(day.temperatureMax, BOUNDS.temperature),
        precipitation: number(day.precipitation, BOUNDS.precipitation),
        precipitationMin: number(day.precipitationMin, BOUNDS.precipitation),
        precipitationMax: number(day.precipitationMax, BOUNDS.precipitation)
      })
    }
  }

  var graph = data.graph
  if (graph && typeof graph === "object") {
    var start = epochMs(graph.start)
    var lowResolution = epochMs(graph.startLowResolution)
    result.graph = {
      startMs: start,
      temperature: series(numberSeries(graph.temperatureMean1h, BOUNDS.temperature), start, HOUR_MS),
      temperatureMin: series(numberSeries(graph.temperatureMin1h, BOUNDS.temperature), start, HOUR_MS),
      temperatureMax: series(numberSeries(graph.temperatureMax1h, BOUNDS.temperature), start, HOUR_MS),
      wind: series(numberSeries(graph.windSpeed1h, BOUNDS.wind), start, HOUR_MS),
      windQ10: series(numberSeries(graph.windSpeed1hq10, BOUNDS.wind), start, HOUR_MS),
      windQ90: series(numberSeries(graph.windSpeed1hq90, BOUNDS.wind), start, HOUR_MS),
      gust: series(numberSeries(graph.gustSpeed1h, BOUNDS.wind), start, HOUR_MS),
      gustQ10: series(numberSeries(graph.gustSpeed1hq10, BOUNDS.wind), start, HOUR_MS),
      gustQ90: series(numberSeries(graph.gustSpeed1hq90, BOUNDS.wind), start, HOUR_MS),
      sunshine: series(numberSeries(graph.sunshine1h, BOUNDS.sunshine), start, HOUR_MS),
      precipitation10m: series(numberSeries(graph.precipitation10m, BOUNDS.precipitation), start, TEN_MINUTES_MS),
      precipitation10mMin: series(numberSeries(graph.precipitationMin10m, BOUNDS.precipitation), start, TEN_MINUTES_MS),
      precipitation10mMax: series(numberSeries(graph.precipitationMax10m, BOUNDS.precipitation), start, TEN_MINUTES_MS),
      precipitation1h: series(numberSeries(graph.precipitation1h, BOUNDS.precipitation), lowResolution, HOUR_MS),
      precipitation1hMin: series(numberSeries(graph.precipitationMin1h, BOUNDS.precipitation), lowResolution, HOUR_MS),
      precipitation1hMax: series(numberSeries(graph.precipitationMax1h, BOUNDS.precipitation), lowResolution, HOUR_MS),
      icon3h: series(symbolSeries(graph.weatherIcon3hV2 !== undefined ? graph.weatherIcon3hV2 : graph.weatherIcon3h), start, 3 * HOUR_MS),
      windDirection3h: series(numberSeries(graph.windDirection3h, BOUNDS.direction), start, 3 * HOUR_MS),
      precipitationProbability3h: series(numberSeries(graph.precipitationProbability3h, BOUNDS.probability), start, 3 * HOUR_MS),
      sunrise: numberSeries(graph.sunrise, null),
      sunset: numberSeries(graph.sunset, null)
    }
  }

  if (Array.isArray(data.warnings)) {
    var warningCount = Math.min(data.warnings.length, MAX_WARNINGS)
    for (var w = 0; w < warningCount; w++) {
      var warning = data.warnings[w]
      if (!warning || typeof warning !== "object") continue
      // `htmlText` is dropped outright: the panel renders plain text only, so
      // there is nothing here that could carry markup. `links` is not stored
      // either — only one enum value is read out of it, see hazardOfLinks.
      var body = warningLines(warning.text)
      if (body.length === 0) continue
      var hazard = warningHazard(warning)
      result.warnings.push({
        type: number(warning.warnType, { min: 0, max: 99 }),
        hazard: hazard,
        category: warningCategory(warning.warnType, hazard),
        level: number(warning.warnLevel, { min: 1, max: 5 }),
        from: epochMs(warning.validFrom),
        to: epochMs(warning.validTo),
        lines: body,
        // The flat form, kept for anything that wants one string.
        text: body.map(function(line) {
          return line.label === "" ? line.value : line.label + ": " + line.value
        }).join(" ")
      })
    }
  }

  return result
}

// Warning types, split by which authority issues them. MeteoSwiss warns about
// the weather; the Federal Office for the Environment warns about what the
// weather then does to the ground — avalanches, floods, forest fire, drought —
// and the two arrive mixed in the same array.
//
// The numbering is not published as part of Open Data, so this table is read
// off the live payloads and is necessarily incomplete. That is why an
// unrecognised type counts as a weather warning rather than as neither: a code
// MeteoSwiss adds later must keep showing up for someone who has weather
// warnings on, instead of silently disappearing.
var NATURAL_HAZARD_TYPES = [8, 9, 10, 11, 12] // avalanche, earthquake, forest fire, flood, drought

// Hazards that are not weather. MeteoSwiss warns about the weather; the
// avalanche, earthquake, fire, flood, drought and ground-movement warnings
// come from the other federal agencies and arrive in the same array.
var NATURAL_HAZARD_KEYS = ["avalanche", "earthquake", "forestFire", "flood", "drought", "massMovement"]

// What kind of hazard a warning is about, as a key the interface can name.
//
// The payload gives a `warnType` number, and that numbering is not published:
// only 1, 2 and 10 have been seen and confirmed against live warnings, so
// guessing the rest would risk labelling a flood warning "avalanche". What
// every warning does carry is its own "what to do" link on the federal
// natural-hazards site, whose path names the hazard — /waldbrand.html,
// /incendie-de-foret/, /forest-fire.html. That is read here as the primary
// source and the number is only the fallback.
//
// Nothing from the URL survives: the path is cut into segments, each is looked
// up in the table below, and the value stored is one of these keys or nothing.
var HAZARD_SLUGS = {
  // German
  gewitter: "thunderstorm", regen: "rain", schnee: "snow", schneefall: "snow",
  strassenglaette: "slipperyRoads", frost: "frost", hitze: "heat", hitzewelle: "heat",
  wind: "wind", lawinen: "avalanche", erdbeben: "earthquake", waldbrand: "forestFire",
  hochwasser: "flood", trockenheit: "drought", massenbewegungen: "massMovement",
  // French
  orages: "thunderstorm", pluie: "rain", pluies: "rain", neige: "snow",
  "chute-de-neige": "snow", "chaussee-glissante": "slipperyRoads", gel: "frost",
  canicule: "heat", vent: "wind", avalanches: "avalanche", seismes: "earthquake",
  "incendie-de-foret": "forestFire", crues: "flood", secheresse: "drought",
  "mouvements-de-terrain": "massMovement",
  // English
  thunderstorms: "thunderstorm", rain: "rain", snow: "snow", snowfall: "snow",
  "slippery-roads": "slipperyRoads", heat: "heat", heatwave: "heat",
  earthquakes: "earthquake", "forest-fire": "forestFire", flood: "flood", floods: "flood",
  drought: "drought", "mass-movements": "massMovement"
}

// Confirmed against live payloads, by reading the hazard link that came with
// each warning. Deliberately short: an unconfirmed number stays unnamed.
var HAZARD_BY_TYPE = { 1: "thunderstorm", 2: "rain", 10: "forestFire" }

/** The hazard key named by a warning's own links, or "". */
function hazardOfLinks(links) {
  if (!Array.isArray(links)) return ""
  for (var i = 0; i < links.length && i < 8; i++) {
    var link = links[i]
    var url = link && typeof link === "object" ? link.url : link
    if (typeof url !== "string" || url.length > 500) continue
    var parts = url.toLowerCase().split(/[/?#&=.]+/)
    for (var j = 0; j < parts.length; j++) {
      var key = HAZARD_SLUGS[parts[j]]
      if (key) return key
    }
  }
  return ""
}

/** The hazard key for a warning: from its links, else from its type number. */
function warningHazard(warning) {
  if (!warning || typeof warning !== "object") return ""
  var fromLinks = hazardOfLinks(warning.links)
  if (fromLinks !== "") return fromLinks
  var n = number(warning.warnType, { min: 0, max: 99 })
  if (n === null) return ""
  return HAZARD_BY_TYPE[Math.round(n)] || ""
}

/**
 * "hazard" or "weather", from the hazard key when one was identified and from
 * the type number otherwise.
 *
 * An unrecognised warning counts as weather rather than as neither: a code
 * MeteoSwiss adds later must keep showing up for someone who has weather
 * warnings on, instead of silently disappearing.
 */
function warningCategory(warnType, hazard) {
  if (hazard) return NATURAL_HAZARD_KEYS.indexOf(hazard) !== -1 ? "hazard" : "weather"
  var n = number(warnType, null)
  if (n !== null && NATURAL_HAZARD_TYPES.indexOf(Math.round(n)) !== -1) return "hazard"
  return "weather"
}

/**
 * A warning's text as the labelled points it was written as.
 *
 * MeteoSwiss writes the body as "- Possible impacts: …" one per line. Folding
 * that into a single paragraph — which is what happens if the newlines are
 * treated as ordinary control characters — turns four scannable points into a
 * block nobody reads. Each line comes back as {label, value}; a line with no
 * label of its own has label "".
 */
function warningLines(value) {
  var raw = String(value === undefined || value === null ? "" : value)
  var out = []
  var pieces = raw.split(/[\r\n]+/)
  for (var i = 0; i < pieces.length && out.length < MAX_WARNING_LINES; i++) {
    var line = text(pieces[i], MAX_WARNING_LINE_LENGTH)
    // The bullet MeteoSwiss writes in front of each point; the panel draws its
    // own, so a literal one here would double up.
    line = line.replace(/^[-•*\u2013\u2014]\s*/, "")
    if (line === "") continue
    // Split "Label: value" only when the label is short enough to be one —
    // otherwise a colon in the middle of a sentence would cut it in two.
    var match = /^([^:]{2,60}?)\s*:\s+(\S[\s\S]*)$/.exec(line)
    if (match) out.push({ label: match[1], value: match[2] })
    else out.push({ label: "", value: line })
  }
  return out
}

/** A MeteoSwiss symbol number (1-42 day, 101-142 night), or null. */
function symbolCode(value) {
  var n = number(value, null)
  if (n === null) return null
  n = Math.round(n)
  if ((n >= 1 && n <= 42) || (n >= 101 && n <= 142)) return n
  return null
}

function symbolSeries(value) {
  if (!Array.isArray(value)) return []
  var out = []
  var limit = Math.min(value.length, MAX_SERIES_POINTS)
  for (var i = 0; i < limit; i++) out.push(symbolCode(value[i]))
  return out
}

/**
 * Hourly precipitation over [fromMs, toMs), preferring the ten-minute series
 * where it reaches and falling back to the hourly one beyond it.
 *
 * The two series meet at `startLowResolution` and never overlap, so summing
 * ten-minute buckets into the hours they belong to and letting the hourly
 * series fill the rest reconstructs one continuous curve. Each hour keeps its
 * min/max band, which is what makes the bars readable as a forecast rather
 * than as a single guessed number.
 */
function hourlyPrecipitation(graph, fromMs, toMs) {
  var hours = []
  if (!graph) return hours

  for (var t = fromMs; t < toMs; t += HOUR_MS) {
    var bucket = { time: t, value: null, min: null, max: null }

    var tenMinute = accumulateTenMinute(graph, t)
    if (tenMinute !== null) {
      bucket.value = tenMinute.value
      bucket.min = tenMinute.min
      bucket.max = tenMinute.max
    } else {
      bucket.value = valueAt(graph.precipitation1h, t)
      var hourBand = orderedBand(valueAt(graph.precipitation1hMin, t),
                                 valueAt(graph.precipitation1hMax, t),
                                 bucket.value)
      bucket.min = hourBand === null ? null : hourBand.low
      bucket.max = hourBand === null ? null : hourBand.high
    }

    hours.push(bucket)
  }
  return hours
}

/**
 * Sums the six ten-minute readings inside the hour starting at `hourMs`.
 * Returns null when the hour is not fully covered by the ten-minute series,
 * so the caller falls back rather than reporting a partial hour as a total.
 */
function accumulateTenMinute(graph, hourMs) {
  var s = graph.precipitation10m
  if (!s || s.startMs === null || s.startMs === undefined || s.values.length === 0) return null

  var firstIndex = Math.round((hourMs - s.startMs) / TEN_MINUTES_MS)
  if (firstIndex < 0 || firstIndex + 6 > s.values.length) return null

  var total = 0, low = 0, high = 0
  for (var i = firstIndex; i < firstIndex + 6; i++) {
    if (s.values[i] === null) return null
    total += s.values[i]
    var minValue = graph.precipitation10mMin.values[i]
    var maxValue = graph.precipitation10mMax.values[i]
    // Order each slot before summing: an inverted slot would otherwise push
    // the hour's low above its high.
    var slot = orderedBand(minValue, maxValue, s.values[i])
    low += slot === null ? s.values[i] : slot.low
    high += slot === null ? s.values[i] : slot.high
  }
  var band = orderedBand(round1(low), round1(high), round1(total))
  return { value: round1(total), min: band.low, max: band.high }
}

function round1(value) {
  return Math.round(value * 10) / 10
}

// ------------------------------------------------------------------ geo-IP

/**
 * Coarse location from the geo-IP response. Only latitude, longitude and
 * country code are read; the response's IP address and everything else about
 * the caller is discarded here and never stored (see README "Privacy").
 *
 * A non-Swiss answer is reported as such rather than used, because every
 * forecast point this plugin can address is in Switzerland — placing the user
 * in the nearest Swiss town to, say, Lyon would be a confident lie.
 */
function parseGeoip(raw) {
  var data
  try {
    data = JSON.parse(String(raw || ""))
  } catch (e) {
    return null
  }
  if (!data || typeof data !== "object" || Array.isArray(data)) return null

  var lat = number(data.latitude, BOUNDS.latitude)
  var lon = number(data.longitude, BOUNDS.longitude)
  var country = text(data.country_code, 2).toUpperCase()
  if (lat === null || lon === null) return null

  return {
    latitude: lat,
    longitude: lon,
    country: country,
    // Liechtenstein counts. MeteoSwiss forecasts its towns and they are in the
    // shipped index — Vaduz included — so treating an LI address as "abroad"
    // would send someone to Bern while holding the forecast for their own
    // street.
    covered: COVERED_COUNTRIES.indexOf(country) !== -1
  }
}

// The countries the forecast service covers, and therefore the ones detection
// can place someone in. Anywhere else there is no honest answer: every point
// this plugin can address is here.
var COVERED_COUNTRIES = ["CH", "LI"]

// ----------------------------------------------------------- persisted state

/** A favourite, or null when the stored entry is not one we can act on. */
function parseFavourite(entry) {
  if (!entry || typeof entry !== "object") return null
  var pointId = String(entry.pointId || "")
  if (!/^[0-9]{6}$/.test(pointId)) return null
  var name = text(entry.name, MAX_NAME_LENGTH)
  if (name === "") return null
  var lat = number(entry.lat, BOUNDS.latitude)
  var lon = number(entry.lon, BOUNDS.longitude)
  if (lat === null || lon === null) return null
  return {
    pointId: pointId,
    plz: /^[0-9]{4}$/.test(String(entry.plz || "")) ? String(entry.plz) : "",
    name: name,
    lat: lat,
    lon: lon
  }
}

/**
 * Reads the plugin's state file. Everything is validated on the way in: the
 * file lives in the user's home and may have been hand-edited, and a bad value
 * must not reach a URL builder or an array index.
 */
function parseState(raw, languages) {
  var state = {
    language: "",
    units: "metric",
    favourites: [],
    activePointId: "",
    // The town detection picked, remembered separately from the active one so
    // that removing every favourite can fall back to it rather than to a
    // hardcoded city.
    detectedPointId: "",
    geoDetected: false,
    showWeatherWarnings: true,
    showHazardWarnings: true,
    // Off unless asked for. Warnings are safety information, which is why they
    // are shown by default — but showing something in a panel the user opened
    // and pushing a popup onto their screen are not the same permission.
    notifyWarnings: false,
    seenWarnings: []
  }

  var data
  try {
    data = JSON.parse(String(raw || ""))
  } catch (e) {
    return state
  }
  if (!data || typeof data !== "object" || Array.isArray(data)) return state

  var language = String(data.language || "").toLowerCase()
  if ((languages || []).indexOf(language) !== -1) state.language = language

  if (Array.isArray(data.favourites)) {
    for (var i = 0; i < data.favourites.length && state.favourites.length < MAX_FAVOURITES; i++) {
      var favourite = parseFavourite(data.favourites[i])
      if (favourite === null) continue
      if (indexOfPoint(state.favourites, favourite.pointId) !== -1) continue
      state.favourites.push(favourite)
    }
  }

  var active = String(data.activePointId || "")
  if (/^[0-9]{6}$/.test(active)) state.activePointId = active
  var detected = String(data.detectedPointId || "")
  if (/^[0-9]{6}$/.test(detected)) state.detectedPointId = detected

  state.units = normalizedUnits(data.units)
  state.geoDetected = data.geoDetected === true
  // Warnings default to on: they are safety information, so an absent or
  // unreadable setting must not be what turns them off.
  state.showWeatherWarnings = data.showWeatherWarnings !== false
  state.showHazardWarnings = data.showHazardWarnings !== false
  state.notifyWarnings = data.notifyWarnings === true

  if (Array.isArray(data.seenWarnings)) {
    for (var k = 0; k < data.seenWarnings.length && state.seenWarnings.length < MAX_SEEN_WARNINGS; k++) {
      // Strings only: text() would happily turn {} into "[object Object]",
      // which would then occupy a slot in a bounded list for ever.
      if (typeof data.seenWarnings[k] !== "string") continue
      var key = text(data.seenWarnings[k], MAX_KEY_LENGTH)
      if (key !== "" && state.seenWarnings.indexOf(key) === -1) state.seenWarnings.push(key)
    }
  }

  return state
}

function serializeState(state) {
  return {
    version: 1,
    language: String(state.language || ""),
    favourites: (state.favourites || []).slice(0, MAX_FAVOURITES).map(function(favourite) {
      return {
        pointId: favourite.pointId,
        plz: favourite.plz,
        name: favourite.name,
        lat: favourite.lat,
        lon: favourite.lon
      }
    }),
    activePointId: String(state.activePointId || ""),
    detectedPointId: String(state.detectedPointId || ""),
    units: normalizedUnits(state.units),
    geoDetected: state.geoDetected === true,
    showWeatherWarnings: state.showWeatherWarnings !== false,
    showHazardWarnings: state.showHazardWarnings !== false,
    notifyWarnings: state.notifyWarnings === true,
    // Newest last, oldest dropped: a warning that has expired cannot come back
    // with the same key, so the tail is the safe end to cut.
    seenWarnings: (state.seenWarnings || []).slice(-MAX_SEEN_WARNINGS)
  }
}

function indexOfPoint(favourites, pointId) {
  var id = String(pointId || "")
  for (var i = 0; i < (favourites || []).length; i++) {
    if (favourites[i].pointId === id) return i
  }
  return -1
}

// ------------------------------------------------------------ unit systems
//
// Conversion is arithmetic, done here. There is no unit-aware endpoint to ask
// and no reason to introduce one: MeteoSwiss publishes metric, and turning
// °C into °F is a multiplication. Keeping it local also means switching units
// costs no request and works offline.

var UNIT_SYSTEMS = ["metric", "imperial"]

function normalizedUnits(value) {
  return String(value || "") === "imperial" ? "imperial" : "metric"
}

/**
 * Converts one value from the metric units MeteoSwiss publishes.
 *
 * `quantity` names what the number measures, not what it is called on screen:
 * "speed" covers wind and gusts, "distance" the station distance, "elevation"
 * the altitude of a town. Nulls pass straight through, so an absent reading
 * stays absent rather than becoming 32 °F.
 */
function convert(value, quantity, units) {
  if (value === null || value === undefined) return null
  var n = Number(value)
  if (!isFinite(n)) return null
  if (normalizedUnits(units) === "metric") return n

  switch (quantity) {
    case "temperature": return n * 9 / 5 + 32       // °C  -> °F
    case "precipitation": return n / 25.4           // mm  -> in
    case "speed": return n * 0.621371               // km/h -> mph
    case "distance": return n * 0.621371            // km  -> mi
    case "elevation": return n * 3.28084            // m   -> ft
    default: return n                                // sunshine minutes, %, °
  }
}

/**
 * Decimal places for a quantity in a unit system. Inches need one more than
 * millimetres to say anything at all: a 2 mm shower is 0.08 in, which rounds
 * to 0.1 at one decimal and to nothing at zero.
 */
function decimalsFor(quantity, units) {
  var imperial = normalizedUnits(units) === "imperial"
  switch (quantity) {
    case "temperature": return 1
    case "precipitation": return imperial ? 2 : 1
    case "speed": return 0
    case "elevation": return 0
    default: return 0
  }
}

// --------------------------------------------------------------- formatting

/** Fixed-decimal number, or an em dash when the value is absent. */
function formatNumber(value, decimals, absent) {
  if (value === null || value === undefined) return absent === undefined ? "—" : absent
  var n = Number(value)
  if (!isFinite(n)) return absent === undefined ? "—" : absent
  return n.toFixed(decimals === undefined ? 1 : decimals)
}

/**
 * A 10-90 % band as "low – high", collapsed to a single value when the two
 * ends round to the same number. Showing "24.9 – 24.9" would suggest a
 * precision the forecast does not claim.
 */
function formatRange(low, high, decimals) {
  // Order defensively: a range is only a range if its ends are the right way
  // round, and the upstream bands are not always.
  var ordered = orderedBand(low, high, null)
  var lowText = ordered === null ? "" : formatNumber(ordered.low, decimals, "")
  var highText = ordered === null ? "" : formatNumber(ordered.high, decimals, "")
  if (lowText === "" && highText === "") return ""
  if (lowText === "" || highText === "") return lowText || highText
  if (lowText === highText) return lowText
  return lowText + "–" + highText
}

function formatDistance(km) {
  if (km === null || km === undefined || !isFinite(km)) return ""
  return km < 10 ? km.toFixed(1) : String(Math.round(km))
}

/**
 * A stable identity for one warning, used to tell a new one from a repeat.
 *
 * Made of what MeteoSwiss would change if the situation changed — the hazard,
 * the level and the period — and of nothing that varies for other reasons. The
 * text is deliberately not part of it: MeteoSwiss re-words a standing warning
 * as the forecast firms up, and being notified again because a sentence gained
 * a comma would be exactly the behaviour that makes people turn notifications
 * off.
 */
function warningKey(warning, pointId) {
  if (!warning || typeof warning !== "object") return ""
  var parts = [
    // The town comes first so that it survives the length cap: two towns are
    // regularly put under one regional warning, identical in hazard, level and
    // period, and without this they would share a key — the second town's
    // warning would be taken for one already announced and never arrive.
    String(pointId === null || pointId === undefined ? "?" : pointId),
    String(warning.hazard || warning.type || "?"),
    warning.level === null || warning.level === undefined ? "?" : String(warning.level),
    warning.from === null || warning.from === undefined ? "?" : String(warning.from),
    warning.to === null || warning.to === undefined ? "?" : String(warning.to)
  ]
  return parts.join("|").substring(0, MAX_KEY_LENGTH)
}

/** True for a warning severe enough to interrupt someone. */
function isNotifiable(warning) {
  return !!warning && warning.level !== null && warning.level !== undefined
    && warning.level >= NOTIFY_LEVEL
}

/**
 * Text made safe to hand to a rich-text renderer.
 *
 * Warning bodies are the one place the panel does not render remote text as
 * plain text: the labels MeteoSwiss writes ("Possible impacts:", "Expected
 * amounts:") are what makes a warning scannable, and they only stand out if
 * they can be emboldened. So the *plugin* writes the markup and everything
 * from the network goes through here first — with &, < and > turned into
 * entities, no sequence of remote characters can open a tag, and a payload
 * containing "<b>" or "<img src=x>" is displayed as those literal characters.
 * Nothing else needs escaping because the plugin emits no attributes, and
 * `text()` has already removed the control characters.
 */
// Padding for the summary notification, as character references.
//
// Omarchy's notification card renders the body as styled text, which collapses
// every run of whitespace — ordinary spaces and the Unicode ones alike — to a
// single space. A character reference survives that pass, so these are the only
// way to hold a column. Widths are measured, never assumed: the four give a
// step small enough (a hair space) that any gap lands within half a pixel.
var PAD_UNITS = [
  { entity: "&#8199;", text: " " }, // figure space, one digit wide
  { entity: "&nbsp;", text: " " },  // one space wide
  { entity: "&#8201;", text: " " }, // thin space
  { entity: "&#8202;", text: " " }  // hair space
]

var SUMMARY_ELLIPSIS = "…"
var SUMMARY_SEPARATOR = " · "

/** Character references filling `gap` pixels as closely as the units allow. */
function padding(gap, measure) {
  var units = PAD_UNITS.map(function(unit) {
    return { entity: unit.entity, width: measure(unit.text) }
  }).filter(function(unit) { return unit.width > 0 })
  if (units.length === 0) return ""

  var smallest = units[units.length - 1].width
  var out = ""
  var left = gap
  // Half a unit of overshoot beats a whole unit of gap: rounding to the nearest
  // is what keeps a column edge from drifting one way every line.
  while (left >= smallest / 2) {
    var unit = null
    for (var i = 0; i < units.length; i++) {
      if (units[i].width <= left + smallest / 2) { unit = units[i]; break }
    }
    if (unit === null) break
    out += unit.entity
    left -= unit.width
  }
  return out
}

/** The text padded to `target` pixels, or left alone when it is already wider. */
function padTo(value, target, measure, before) {
  var pad = padding(target - measure(value), measure)
  return before ? pad + escapeMarkup(value) : escapeMarkup(value) + pad
}

/** The longest head of `value` that fits `target` pixels once elided. */
function elide(value, target, measure) {
  if (measure(value) <= target) return value
  var room = target - measure(SUMMARY_ELLIPSIS)
  var cut = 0
  while (cut < value.length && measure(value.slice(0, cut + 1)) <= room) cut++
  // A single character plus the ellipsis says nothing; below that, keep the
  // head and let the card elide it itself rather than print a stub.
  if (cut < 2) return value
  return value.slice(0, cut) + SUMMARY_ELLIPSIS
}

/**
 * The summary notification's body: one row per town, values in columns.
 *
 * Every column is as wide as its widest member, so the temperatures of three
 * towns start at the same pixel and the eye reads down instead of hunting
 * along. The name column takes what is left of `width`; a name too long for it
 * is elided, because a wrapped line costs a town its place — the card shows
 * three lines and no more.
 *
 * `measure` is the width of a string in the card's own font, which only the
 * shell can answer; passing it in is what keeps this function testable.
 */
function summaryTable(rows, measure, width) {
  if (rows.length === 0) return []

  var columns = []
  for (var c = 0; c < rows[0].values.length; c++) {
    var widest = 0
    for (var r = 0; r < rows.length; r++) widest = Math.max(widest, measure(rows[r].values[c]))
    columns.push(widest)
  }

  var separator = measure(SUMMARY_SEPARATOR)
  var gap = measure(" ")
  var values = gap + separator * (columns.length - 1)
  for (var i = 0; i < columns.length; i++) values += columns[i]

  var longest = 0
  for (var n = 0; n < rows.length; n++) longest = Math.max(longest, measure(rows[n].name))
  // No stretching to the far edge: the name column is as wide as the names
  // need, and only narrower than that when the values would not otherwise fit.
  var nameWidth = Math.min(longest, width - values)

  var out = []
  for (var k = 0; k < rows.length; k++) {
    var line = padTo(elide(rows[k].name, nameWidth, measure), nameWidth, measure, false)
    for (var v = 0; v < rows[k].values.length; v++) {
      line += (v === 0 ? "&nbsp;" : escapeMarkup(SUMMARY_SEPARATOR))
      line += padTo(rows[k].values[v], columns[v], measure, true)
    }
    out.push(line)
  }
  return out
}

function escapeMarkup(value) {
  return String(value === undefined || value === null ? "" : value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
}

/**
 * Index 0-7 of the compass point for a bearing in degrees, or -1 when absent.
 *
 * Only the index is computed here. The abbreviations themselves are language
 * dependent — French west is O, German east is O — so naming them is I18n's
 * job, not this file's.
 */
function compassIndex(degrees) {
  var value = Number(degrees)
  if (degrees === null || degrees === undefined || !isFinite(value)) return -1
  return Math.round(((value % 360) + 360) % 360 / 45) % 8
}

if (typeof module !== "undefined") {
  module.exports = {
    BOUNDS: BOUNDS,
    MAX_FAVOURITES: MAX_FAVOURITES,
    UNIT_SYSTEMS: UNIT_SYSTEMS,
    normalizedUnits: normalizedUnits,
    convert: convert,
    decimalsFor: decimalsFor,
    warningCategory: warningCategory,
    warningHazard: warningHazard,
    warningKey: warningKey,
    isNotifiable: isNotifiable,
    NOTIFY_LEVEL: NOTIFY_LEVEL,
    MAX_SEEN_WARNINGS: MAX_SEEN_WARNINGS,
    warningLines: warningLines,
    escapeMarkup: escapeMarkup,
    summaryTable: summaryTable,
    SUMMARY_ELLIPSIS: SUMMARY_ELLIPSIS,
    NATURAL_HAZARD_KEYS: NATURAL_HAZARD_KEYS,
    HOUR_MS: HOUR_MS,
    TEN_MINUTES_MS: TEN_MINUTES_MS,
    number: number,
    text: text,
    numberSeries: numberSeries,
    epochMs: epochMs,
    parseCompactUtc: parseCompactUtc,
    formatClock: formatClock,
    formatDate: formatDate,
    formatDayMonth: formatDayMonth,
    parseIsoDate: parseIsoDate,
    startOfDay: startOfDay,
    parseMeasurements: parseMeasurements,
    parseForecast: parseForecast,
    symbolCode: symbolCode,
    series: series,
    orderedBand: orderedBand,
    seriesTime: seriesTime,
    sliceSeries: sliceSeries,
    valueAt: valueAt,
    hourlyPrecipitation: hourlyPrecipitation,
    parseGeoip: parseGeoip,
    parseState: parseState,
    serializeState: serializeState,
    parseFavourite: parseFavourite,
    indexOfPoint: indexOfPoint,
    formatNumber: formatNumber,
    formatRange: formatRange,
    formatDistance: formatDistance,
    compassIndex: compassIndex
  }
}

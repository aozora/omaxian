// The bundled Swiss location index, and lookups over it.
//
// Town search runs entirely against data/places.csv, which tools/build-data.sh
// generates from the MeteoSwiss Open Data point metadata. Keeping the index on
// disk is a security decision before it is a convenience one: a typed query
// never becomes a network request, so there is no query to inject into and no
// search term leaving the machine. It also means search works with the network
// down.
//
// data/stations.csv holds the SMN automatic weather stations, used to pick the
// station whose measurements to show for a chosen town.

// A town search never needs more than this many characters, and bounding it
// keeps a pasted megabyte from being scanned across 4000 rows on every
// keystroke.
var MAX_QUERY_LENGTH = 64
var MAX_RESULTS = 8

// Diacritics that occur in Swiss place names, folded for search. An explicit
// table rather than String.normalize("NFD"): the mapping is small, total for
// this data set, and does not depend on the QML engine's Unicode support.
var FOLD = {
  "à": "a", "á": "a", "â": "a", "ä": "a", "ã": "a", "å": "a",
  "ç": "c",
  "è": "e", "é": "e", "ê": "e", "ë": "e",
  "ì": "i", "í": "i", "î": "i", "ï": "i",
  "ñ": "n",
  "ò": "o", "ó": "o", "ô": "o", "ö": "o", "õ": "o", "ø": "o",
  "ù": "u", "ú": "u", "û": "u", "ü": "u",
  "ý": "y", "ÿ": "y",
  "ß": "ss", "œ": "oe", "æ": "ae",
  "'": " ", "’": " ", "-": " ", "/": " ", ".": " "
}

/** Lowercases and strips diacritics so "Genève" is found by typing "geneve". */
function fold(text) {
  var lower = String(text || "").toLowerCase()
  var out = ""
  for (var i = 0; i < lower.length; i++) {
    var ch = lower.charAt(i)
    out += (FOLD[ch] !== undefined) ? FOLD[ch] : ch
  }
  return out.replace(/\s+/g, " ").replace(/^ | $/g, "")
}

/**
 * Splits one line of the bundled semicolon-separated files.
 *
 * The generator strips separators out of every field, so a plain split is
 * correct here — but only for these files. Nothing else should be fed to it.
 */
function splitRow(line) {
  return String(line || "").split(";")
}

function finiteNumber(value) {
  var n = parseFloat(String(value))
  return isFinite(n) ? n : null
}

/**
 * Parses data/places.csv into search-ready records.
 *
 * Rows that fail validation are skipped rather than throwing: a truncated read
 * or a hand-edited file should cost the affected towns, not the whole panel.
 */
function parsePlaces(raw) {
  var lines = String(raw || "").split("\n")
  var places = []
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (line === "" || line.charAt(0) === "#") continue
    var cells = splitRow(line)
    if (cells.length < 5) continue

    var pointId = cells[0]
    if (!/^[0-9]{6}$/.test(pointId)) continue // also skips the header row
    var plz = cells[1]
    if (!/^[0-9]{4}$/.test(plz)) continue
    var name = cells[2]
    var lat = finiteNumber(cells[3])
    var lon = finiteNumber(cells[4])
    if (!name || lat === null || lon === null) continue

    places.push({
      pointId: pointId,
      plz: plz,
      name: name,
      lat: lat,
      lon: lon,
      altitude: finiteNumber(cells[5]),
      // Two letters or nothing. The register covers Swiss postal codes only,
      // so the Liechtenstein towns MeteoSwiss also forecasts have no canton,
      // and an index built before this column existed has none either — both
      // read back as "" and the header simply leaves it out.
      canton: /^[A-Z]{2}$/.test(cells[6] || "") ? cells[6] : "",
      key: fold(name)
    })
  }
  return places
}

/** Parses data/stations.csv into the SMN station list. */
function parseStations(raw) {
  var lines = String(raw || "").split("\n")
  var stations = []
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (line === "" || line.charAt(0) === "#") continue
    var cells = splitRow(line)
    if (cells.length < 4) continue

    var abbr = String(cells[0]).toUpperCase()
    if (!/^[A-Z0-9]{2,5}$/.test(abbr)) continue
    var name = cells[1]
    var lat = finiteNumber(cells[2])
    var lon = finiteNumber(cells[3])
    if (!name || lat === null || lon === null) continue

    stations.push({
      abbr: abbr,
      name: name,
      lat: lat,
      lon: lon,
      altitude: finiteNumber(cells[4])
    })
  }
  return stations
}

/**
 * Parses data/webcams.csv into the weather-cam list.
 *
 * Same shape as the station list, deliberately: both are "a named point with
 * coordinates and an altitude", and the nearest-of search is shared.
 */
function parseWebcams(raw) {
  return parseStations(raw)
}

/**
 * Great-circle distance in kilometres. Over Switzerland the spherical
 * approximation is off by well under a percent, which is far finer than the
 * "which station is nearest" question needs.
 */
function distanceKm(lat1, lon1, lat2, lon2) {
  var toRad = Math.PI / 180
  var earthRadiusKm = 6371
  var dLat = (lat2 - lat1) * toRad
  var dLon = (lon2 - lon1) * toRad
  var a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
    + Math.cos(lat1 * toRad) * Math.cos(lat2 * toRad)
    * Math.sin(dLon / 2) * Math.sin(dLon / 2)
  return 2 * earthRadiusKm * Math.asin(Math.min(1, Math.sqrt(a)))
}

/**
 * Ranks towns against a typed query.
 *
 * Ordering is: exact postal code, then name prefix, then name substring, and
 * alphabetically within each tier. A four-digit query is treated as a postal
 * code, which is how most people in Switzerland actually name a place.
 */
function search(places, query) {
  var text = String(query || "").substring(0, MAX_QUERY_LENGTH)
  var needle = fold(text)
  if (needle.length < 2) return []

  var isPostalCode = /^[0-9]{1,4}$/.test(needle)
  var matches = []
  for (var i = 0; i < places.length; i++) {
    var place = places[i]
    var rank = -1
    if (isPostalCode) {
      if (place.plz === needle) rank = 0
      else if (place.plz.lastIndexOf(needle, 0) === 0) rank = 1
    } else if (place.key.lastIndexOf(needle, 0) === 0) {
      rank = 2
    } else if (place.key.indexOf(needle) !== -1) {
      rank = 3
    }
    if (rank !== -1) matches.push({ rank: rank, place: place })
  }

  matches.sort(function(a, b) {
    if (a.rank !== b.rank) return a.rank - b.rank
    if (a.place.name !== b.place.name) return a.place.name < b.place.name ? -1 : 1
    return a.place.plz < b.place.plz ? -1 : 1
  })

  var results = []
  for (var j = 0; j < matches.length && results.length < MAX_RESULTS; j++) {
    results.push(matches[j].place)
  }
  return results
}

/**
 * Parses data/forecast-pages.csv into `{ plz: { de, fr, en } }`.
 *
 * MeteoSwiss addresses a local-forecast page by the town's name *in the page's
 * language* — Genève is /genf/ in German and /geneva/ in English — and no rule
 * derives that from the town's own name. The table is generated from the three
 * language sitemaps by tools/build-data.sh, so the plugin looks the slug up
 * instead of guessing it and the link is either right or absent.
 *
 * Empty fr/en columns mean the German slug applies, which is true for all but
 * 125 of the 3191 postal codes.
 */
function parseForecastPages(raw) {
  var lines = String(raw || "").split("\n")
  var pages = {}
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (line === "" || line.charAt(0) === "#") continue
    var cells = splitRow(line)
    if (cells.length < 2) continue

    var plz = cells[0]
    if (!/^[0-9]{4}$/.test(plz)) continue // also skips the header row
    var de = String(cells[1] || "")
    // Anything that is not a plain path segment is refused rather than
    // escaped: this value ends up in a URL handed to the browser.
    if (!/^[a-z0-9-]{1,80}$/.test(de)) continue

    var entry = { de: de, fr: de, en: de }
    var fr = String(cells[2] || "")
    var en = String(cells[3] || "")
    if (/^[a-z0-9-]{1,80}$/.test(fr)) entry.fr = fr
    if (/^[a-z0-9-]{1,80}$/.test(en)) entry.en = en
    pages[plz] = entry
  }
  return pages
}

/** Page slug for a postal code in a language, or "" when there is no page. */
function pageSlug(pages, plz, language) {
  var entry = pages ? pages[String(plz || "")] : null
  if (!entry) return ""
  var lang = (language === "fr" || language === "de" || language === "en") ? language : "en"
  return entry[lang] || ""
}

/** Place with the given six-digit forecast point id, or null. */
function byPointId(places, pointId) {
  var id = String(pointId || "")
  for (var i = 0; i < places.length; i++) {
    if (places[i].pointId === id) return places[i]
  }
  return null
}

/** Nearest place to a coordinate — how a detected latitude/longitude becomes a town. */
function nearestPlace(places, lat, lon) {
  return nearestOf(places, lat, lon)
}

// How far outside the country a detected address may sit and still be given a
// Swiss town rather than the default one.
//
// Switzerland's border towns are shared weather: Annemasse reads Geneva's sky,
// Konstanz reads Kreuzlingen's, Como reads Chiasso's. Someone there is better
// served by the town across the border than by Bern, which describes weather
// they cannot see. Thirty kilometres is close enough for that to hold and far
// short of reaching a city with a forecast of its own — Milan is 42 km from
// Chiasso and stays out, as it should.
var MAX_BORDER_DISTANCE_KM = 30

/**
 * Nearest place within `maxKm`, or null.
 *
 * The cut-off is the whole point: past it the nearest Swiss town stops being a
 * description of the sky overhead and becomes a wrong answer delivered with
 * confidence, which is worse than the honest default.
 */
function nearestPlaceWithin(places, lat, lon, maxKm) {
  var nearest = nearestOf(places, lat, lon)
  if (nearest === null) return null
  var limit = Number(maxKm)
  if (!isFinite(limit)) return nearest
  return nearest.distanceKm <= limit ? nearest : null
}

/** Nearest SMN station to a coordinate, with the distance that decided it. */
function nearestStation(stations, lat, lon) {
  return nearestOf(stations, lat, lon)
}

/**
 * The weather cam nearest a place, with its distance, or null.
 *
 * Nearest by distance alone, unlike the measuring station: a station is chosen
 * because its readings have to describe the town, so altitude matters as much
 * as distance. A camera is chosen because someone wants to look at the sky
 * over there, and the nearest one is the nearest one.
 */
function nearestWebcam(webcams, lat, lon) {
  return nearestOf(webcams, lat, lon)
}

// How far a station may sit from the town before its readings stop describing
// that town at all, expressed in the cost units below. Beyond this the panel
// would be attributing someone else's weather to the place on screen.
var MAX_STATION_COST = 60

// Metres of altitude difference judged equivalent to one kilometre of
// horizontal distance. In Switzerland the vertical axis dominates: Les Attelas
// and Sion are 15 km apart and routinely 15 °C apart, because one is 2730 m up
// and the other is in the Rhône valley. A station picked on horizontal
// distance alone will happily report an alpine summit as the weather in the
// town below it.
var METRES_PER_KM_EQUIVALENT = 50

/**
 * Combined distance/altitude cost of using `station` for a place.
 */
function stationCost(station, lat, lon, altitude) {
  var cost = distanceKm(lat, lon, station.lat, station.lon)
  var placeAltitude = finiteNumber(altitude)
  var stationAltitude = finiteNumber(station.altitude)
  if (placeAltitude !== null && stationAltitude !== null) {
    cost += Math.abs(stationAltitude - placeAltitude) / METRES_PER_KM_EQUIVALENT
  }
  return cost
}

/**
 * Picks the station whose readings to show for a place.
 *
 * Nearest is the obvious rule and the wrong one, for two reasons this function
 * exists to handle. Many SMN stations carry only some instruments — around
 * half publish no precipitation at all — and any station can fall silent for a
 * refresh or two. And nearest-by-map ignores altitude, which is the single
 * biggest influence on Swiss weather.
 *
 * So candidates are ranked first by how many of the requested parameters they
 * are actually reporting right now, and only then by the distance/altitude
 * cost above. A station a little further away that reports rain, sun and wind
 * tells the user more than a nearer one reporting nothing — and because the
 * panel always prints the station's name and distance, the substitution is
 * visible rather than silent.
 *
 * `readings` is the abbr-keyed map from Model.parseMeasurements, and may be
 * empty: before the first response lands this degrades to plain nearest-cost,
 * which is the right starting guess.
 */
function selectStation(stations, readings, lat, lon, altitude, parameters) {
  if (!stations || stations.length === 0) return null
  var targetLat = finiteNumber(lat)
  var targetLon = finiteNumber(lon)
  if (targetLat === null || targetLon === null) return null

  var wanted = parameters || []
  var best = null
  var bestCoverage = -1
  var bestCost = Infinity
  var fallback = null
  var fallbackCost = Infinity

  for (var i = 0; i < stations.length; i++) {
    var station = stations[i]
    var cost = stationCost(station, targetLat, targetLon, altitude)

    // Kept regardless of cost so a place with nothing nearby still names a
    // station rather than showing an anonymous blank.
    if (cost < fallbackCost) {
      fallbackCost = cost
      fallback = station
    }
    if (cost > MAX_STATION_COST) continue

    var reading = readings ? readings[station.abbr] : null
    var coverage = 0
    for (var p = 0; p < wanted.length; p++) {
      if (reading && reading[wanted[p]] !== null && reading[wanted[p]] !== undefined) coverage++
    }

    if (coverage > bestCoverage || (coverage === bestCoverage && cost < bestCost)) {
      bestCoverage = coverage
      bestCost = cost
      best = station
    }
  }

  var chosen = best || fallback
  if (chosen === null) return null

  var result = {}
  for (var key in chosen) result[key] = chosen[key]
  result.distanceKm = distanceKm(targetLat, targetLon, chosen.lat, chosen.lon)
  result.cost = best === chosen ? bestCost : fallbackCost
  result.coverage = best === chosen ? Math.max(0, bestCoverage) : 0
  return result
}

function nearestOf(items, lat, lon) {
  if (!items || items.length === 0) return null
  var targetLat = finiteNumber(lat)
  var targetLon = finiteNumber(lon)
  if (targetLat === null || targetLon === null) return null

  var best = null
  var bestDistance = Infinity
  for (var i = 0; i < items.length; i++) {
    var distance = distanceKm(targetLat, targetLon, items[i].lat, items[i].lon)
    if (distance < bestDistance) {
      bestDistance = distance
      best = items[i]
    }
  }
  if (best === null) return null

  // Copy rather than annotate: the index arrays are shared and long-lived, and
  // a distance measured from one town must not leak into the next lookup.
  var result = {}
  for (var key in best) result[key] = best[key]
  result.distanceKm = bestDistance
  return result
}

if (typeof module !== "undefined") {
  module.exports = {
    MAX_QUERY_LENGTH: MAX_QUERY_LENGTH,
    MAX_RESULTS: MAX_RESULTS,
    fold: fold,
    parsePlaces: parsePlaces,
    parseStations: parseStations,
    parseWebcams: parseWebcams,
    nearestWebcam: nearestWebcam,
    parseForecastPages: parseForecastPages,
    pageSlug: pageSlug,
    distanceKm: distanceKm,
    stationCost: stationCost,
    selectStation: selectStation,
    MAX_STATION_COST: MAX_STATION_COST,
    search: search,
    byPointId: byPointId,
    nearestPlace: nearestPlace,
    nearestPlaceWithin: nearestPlaceWithin,
    MAX_BORDER_DISTANCE_KM: MAX_BORDER_DISTANCE_KM,
    nearestStation: nearestStation
  }
}

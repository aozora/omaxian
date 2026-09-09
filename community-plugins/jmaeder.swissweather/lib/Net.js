// Network policy for the Swiss Weather plugin.
//
// Everything that reaches the network goes through this file, and nothing here
// ever takes a free-form string from the user. Requests are built as argv
// arrays (never a shell string), against a fixed host allowlist, from template
// URLs whose only variable parts are values this module has already validated
// as numeric ids or enum members.
//
// Design rules, in the order they matter:
//
//   1. No user text in a URL. Town search runs against the bundled index in
//      lib/Places.js, so a typed query never becomes a request. That deletes
//      the SSRF / query-injection class outright rather than filtering for it.
//   2. argv, not a shell. Every command is an array handed straight to
//      Quickshell's Process; there is no `sh -c`, so no quoting to get wrong.
//   3. Fail closed. assertAllowed() re-derives the host from the finished URL
//      and refuses anything off the allowlist, even though the caller built
//      that URL from a constant here. A future edit that introduces a
//      concatenation bug gets caught rather than shipped.
//   4. Bounded. Every request carries a connect timeout, a total timeout and a
//      byte ceiling, so a slow or hostile peer cannot stall the shell or grow
//      its heap. Responses land in memory, so the ceiling is what keeps them
//      small.
//   5. No redirects, no compression. A redirect off an allowlisted host is
//      never legitimate here and following one would silently void rule 3;
//      leaving compression off keeps --max-filesize a real bound on how many
//      bytes we end up holding rather than a bound on the compressed stream.

// Hosts this plugin is permitted to contact, and why.
var HOST_OPENDATA = "data.geo.admin.ch"          // MeteoSwiss Open Data (FSDI)
var HOST_FORECAST = "app-prod-ws.meteoswiss-app.ch" // MeteoSwiss forecast service
var HOST_GEOIP = "ipapi.co"                      // coarse first-run location only

var ALLOWED_HOSTS = [HOST_OPENDATA, HOST_FORECAST, HOST_GEOIP]

// Identifies the plugin to MeteoSwiss operations. A federal service is
// entitled to know who is calling it, and an identifiable agent is one they
// can reach out to rather than block.
var USER_AGENT = "omarchy-swissweather/1.0 (+https://github.com/jmaeder/omarchy-swissweather)"

var LANGUAGES = ["en", "fr", "de"]

// Byte ceilings, each a little above the real payload so a normal response is
// never truncated but a runaway one is cut off early.
var LIMIT_MEASUREMENTS = 262144   // VQHA80.csv is ~16 KB
var LIMIT_FORECAST = 524288       // plzDetail is ~15 KB
var LIMIT_GEOIP = 8192            // a few hundred bytes

/**
 * Host of an https URL, or "" if the string is not one we are prepared to
 * reason about. Deliberately strict: no userinfo (`user@host` would otherwise
 * let a crafted URL point somewhere the naive eye reads as allowlisted), no
 * scheme other than https, no empty host.
 */
function hostOf(url) {
  var text = String(url || "")
  var prefix = "https://"
  if (text.lastIndexOf(prefix, 0) !== 0) return ""

  var rest = text.substring(prefix.length)
  var end = rest.length
  var cut = rest.search(/[/?#]/)
  if (cut !== -1) end = cut
  var authority = rest.substring(0, end)

  // Reject userinfo and port syntax rather than parsing them: this plugin
  // never needs either, so anything carrying them is malformed by definition.
  if (authority === "" || authority.indexOf("@") !== -1 || authority.indexOf(":") !== -1) return ""
  if (!/^[A-Za-z0-9.-]+$/.test(authority)) return ""
  return authority.toLowerCase()
}

function isAllowed(url) {
  return ALLOWED_HOSTS.indexOf(hostOf(url)) !== -1
}

/**
 * Returns the url when it targets an allowlisted host, "" otherwise. Callers
 * treat "" as "do not run this request"; no exception is thrown so a policy
 * miss degrades into a skipped refresh rather than a broken panel.
 */
function assertAllowed(url) {
  return isAllowed(url) ? String(url) : ""
}

/**
 * A MeteoSwiss forecast point id: exactly six digits, the postal-code centre
 * ids shipped in data/places.csv. Anything else is refused, which is what
 * keeps the one caller-supplied value in any URL from being a value at all.
 */
function isPointId(value) {
  return /^[0-9]{6}$/.test(String(value || ""))
}

/** An SMN station abbreviation as published by MeteoSwiss: 2-5 alphanumerics. */
function isStationAbbr(value) {
  return /^[A-Z0-9]{2,5}$/.test(String(value || "").toUpperCase())
}

function normalizedLanguage(value) {
  var lang = String(value || "").toLowerCase().substring(0, 2)
  return LANGUAGES.indexOf(lang) !== -1 ? lang : "en"
}

/**
 * Base curl invocation shared by every request.
 *
 * `--fail` matters more than it looks: without it curl prints an error body to
 * stdout on a 4xx/5xx and exits 0, and the parser downstream would be handed
 * an error page to interpret as weather data.
 */
function curlCommand(url, maxBytes, timeoutSeconds, extraArgs) {
  var target = assertAllowed(url)
  if (target === "") return null

  var command = [
    "/usr/bin/curl",
    "-q",
    "--proto", "=https",
    "--proto-redir", "=https",
    "--tlsv1.2",
    "--max-redirs", "0",
    "--fail",
    "--silent",
    "--show-error",
    "--connect-timeout", "5",
    "--max-time", String(Math.max(1, Math.round(timeoutSeconds))),
    "--max-filesize", String(Math.max(1024, Math.round(maxBytes))),
    "--user-agent", USER_AGENT
  ]

  var extras = extraArgs || []
  for (var i = 0; i < extras.length; i++) command.push(String(extras[i]))

  // `--` stops curl reading the URL as an option even if a future edit lets a
  // leading dash through assertAllowed().
  command.push("--")
  command.push(target)
  return command
}

// ---------------------------------------------------------------- endpoints

/**
 * Latest 10-minute measurements for every SMN station, one CSV for the whole
 * country (~16 KB). Fetching the national file and picking a row locally means
 * the request carries no indication of which town the user cares about.
 */
function measurementsCommand() {
  return curlCommand(
    "https://" + HOST_OPENDATA + "/ch.meteoschweiz.messwerte-aktuell/VQHA80.csv",
    LIMIT_MEASUREMENTS, 12, [])
}

/**
 * Point forecast for one postal-code centre: current conditions, six days of
 * daily forecast, and hourly series with their 10 %/90 % quantile bands.
 *
 * The language only ever reaches the request as an Accept-Language header
 * drawn from LANGUAGES, so the header cannot be spliced.
 */
function forecastCommand(pointId, language) {
  if (!isPointId(pointId)) return null
  return curlCommand(
    "https://" + HOST_FORECAST + "/v1/plzDetail?plz=" + String(pointId),
    LIMIT_FORECAST, 12,
    ["--header", "Accept-Language: " + normalizedLanguage(language)])
}

// ------------------------------------------------------- outbound links
//
// Pages the panel can hand to the browser. Deliberately a *separate* set from
// ALLOWED_HOSTS: that list governs what this plugin fetches and parses, this
// one governs what it asks the desktop to open. Conflating the two would let a
// change to one silently widen the other.
//
// Every entry is a literal. There is no per-town deep link because MeteoSwiss
// addresses a town by its name in the *page's* language — Martigny is
// /martinach/ in German, St. Gallen is /saint-gall/ in French — and the
// bundled index carries only each town's own name. Guessing would ship links
// that 404 for exactly the bilingual cities people look up most.
var EXTERNAL_LINKS = {
  "site.en": "https://www.meteoswiss.admin.ch/",
  "site.fr": "https://www.meteosuisse.admin.ch/",
  "site.de": "https://www.meteoschweiz.admin.ch/",
  "opendata": "https://opendatadocs.meteoswiss.ch/"
}

/** MeteoSwiss in the panel's language. */
function siteUrl(language) {
  return EXTERNAL_LINKS["site." + normalizedLanguage(language)]
}

/** The Open Data documentation — where every number in the panel is specified. */
function openDataUrl() {
  return EXTERNAL_LINKS.opendata
}

// MeteoSwiss's local-forecast pages, one host and path per language. The town
// part of the URL is not derived here — it is looked up in the table
// data/forecast-pages.csv builds from the site's own sitemaps, because the
// slug is the town's name in the page's language and cannot be computed from
// the town's own name.
var FORECAST_PAGES = {
  en: { host: "www.meteoswiss.admin.ch", path: "local-forecasts" },
  fr: { host: "www.meteosuisse.admin.ch", path: "previsions-locales" },
  de: { host: "www.meteoschweiz.admin.ch", path: "lokalprognose" }
}

var SLUG_PATTERN = /^[a-z0-9-]{1,80}$/
var POSTAL_CODE_PATTERN = /^[0-9]{4}$/

// MeteoSwiss's map applications — the animated maps a town page links to at
// the bottom. The plugin does not draw these maps: MeteoSwiss serves the radar
// and nowcast frames as an undocumented vector encoding rather than as images,
// and decoding a format nobody publishes is a thing that breaks silently. It
// opens the real page instead, in the panel's language.
//
// Two tables, because the path prefix and the page name are localised
// independently: the German site says service-und-publikationen/applikationen
// and the page is niederschlag.html.
var APPLICATION_PATHS = {
  en: { host: "www.meteoswiss.admin.ch", path: "services-and-publications/applications" },
  fr: { host: "www.meteosuisse.admin.ch", path: "services-et-publications/applications" },
  de: { host: "www.meteoschweiz.admin.ch", path: "service-und-publikationen/applikationen" }
}

var MAP_PAGES = {
  precipitation: { en: "precipitation", fr: "precipitations", de: "niederschlag" },
  clouds: { en: "cloud-cover", fr: "nebulosite", de: "bewoelkung" },
  wind: { en: "wind", fr: "vent", de: "wind" },
  hazards: { en: "hazards", fr: "dangers", de: "gefahren" },
  networks: { en: "measuring-networks", fr: "reseaux-de-mesure", de: "messnetze" }
}

var WEBCAM_PARAMETER = "messnetz-webcams"

/**
 * URL of the MeteoSwiss forecast page for a postal code, in one language, or
 * "" when either part fails validation. Both parts come from a shipped data
 * file rather than from the user, but they are checked all the same: a file
 * in the user's home is editable, and this string is handed to the browser.
 */
function localForecastUrl(plz, slug, language) {
  if (!POSTAL_CODE_PATTERN.test(String(plz || ""))) return ""
  if (!SLUG_PATTERN.test(String(slug || ""))) return ""
  var page = FORECAST_PAGES[normalizedLanguage(language)]
  return "https://" + page.host + "/" + page.path + "/" + String(slug) + "/" + String(plz) + ".html"
}

/** URL of one MeteoSwiss map application, in one language, or "". */
function mapPageUrl(key, language) {
  var slugs = MAP_PAGES[String(key)]
  if (!slugs) return ""
  var lang = normalizedLanguage(language)
  var page = APPLICATION_PATHS[lang]
  return "https://" + page.host + "/" + page.path + "/" + slugs[lang] + ".html"
}

/**
 * URL of the page showing one weather cam, in one language, or "".
 *
 * The picture itself is not fetched and never will be: MeteoSwiss has the
 * cams filmed by a commercial provider and serves the images from that
 * provider's own hosts, behind a redirect. Displaying one would mean telling a
 * third party where the user lives, every quarter of an hour. The panel names
 * the nearest cam and opens MeteoSwiss's page for it instead.
 */
function webcamPageUrl(abbr, language) {
  if (!isStationAbbr(abbr)) return ""
  return mapPageUrl("networks", language)
    + "#param=" + WEBCAM_PARAMETER + "&station=" + String(abbr).toUpperCase()
}

/**
 * True for a URL that is exactly one of the fifteen map pages, optionally
 * carrying the weather-cam fragment for one station.
 *
 * Enumerating beats parsing here: the set is finite and known, so membership
 * can be decided by rebuilding every candidate rather than by picking a URL
 * apart and hoping the checks cover every way it could be malformed.
 */
function isMapPageUrl(url) {
  var target = String(url || "")
  var hash = target.indexOf("#")
  var base = hash === -1 ? target : target.substring(0, hash)

  var found = ""
  for (var key in MAP_PAGES) {
    for (var i = 0; i < LANGUAGES.length; i++) {
      if (mapPageUrl(key, LANGUAGES[i]) === base) { found = key; break }
    }
    if (found !== "") break
  }
  if (found === "") return false
  if (hash === -1) return true

  // A fragment is only ever meaningful on the measuring-networks page, and
  // only the weather-cam one: everywhere else it would be a string the plugin
  // never builds, which is reason enough to refuse it.
  if (found !== "networks") return false
  var match = /^#param=([a-z-]{1,40})&station=([A-Z0-9]{2,5})$/.exec(target.substring(hash))
  return match !== null && match[1] === WEBCAM_PARAMETER
}

/**
 * True for a URL of exactly the shape localForecastUrl produces.
 *
 * Structural, not a substring match: the host must be one of the three, the
 * path must be that host's own prefix, and the two remaining segments must be
 * a slug and a four-digit postal code with nothing after them. That is what
 * lets openCommand accept a constructed URL without becoming a general
 * "open anything".
 */
function isForecastPageUrl(url) {
  var host = hostOf(url)
  if (host === "") return false

  for (var lang in FORECAST_PAGES) {
    var page = FORECAST_PAGES[lang]
    if (page.host !== host) continue
    var prefix = "https://" + page.host + "/" + page.path + "/"
    var text = String(url)
    if (text.lastIndexOf(prefix, 0) !== 0) continue

    var rest = text.substring(prefix.length)
    var parts = rest.split("/")
    if (parts.length !== 2) return false
    if (!SLUG_PATTERN.test(parts[0])) return false
    if (parts[1].length !== 9 || parts[1].substring(4) !== ".html") return false
    return POSTAL_CODE_PATTERN.test(parts[1].substring(0, 4))
  }
  return false
}

/** True only for a URL that is verbatim one of the entries above. */
function isExternalLink(url) {
  var target = String(url || "")
  for (var key in EXTERNAL_LINKS) {
    if (EXTERNAL_LINKS[key] === target) return true
  }
  return false
}

/**
 * argv for handing one of those pages to the browser, or null.
 *
 * The membership test is the whole point: the caller passes a URL, and only a
 * URL this file already published comes back as a runnable command. A future
 * edit that lets a computed string reach here gets null, not a launched
 * browser.
 */
function openCommand(url) {
  var target = String(url || "")
  var allowed = isExternalLink(target) || isForecastPageUrl(target) || isMapPageUrl(target)
  return allowed ? ["xdg-open", target] : null
}

/**
 * Coarse location from the caller's IP, used once to pick a starting town.
 * See README "Privacy": this is the plugin's only non-MeteoSwiss request, it
 * runs at most once, its answer is cached, and the setting can be turned off
 * before it ever runs.
 */
function geoipCommand() {
  return curlCommand("https://" + HOST_GEOIP + "/json/", LIMIT_GEOIP, 6, [])
}

if (typeof module !== "undefined") {
  module.exports = {
    HOST_OPENDATA: HOST_OPENDATA,
    HOST_FORECAST: HOST_FORECAST,
    HOST_GEOIP: HOST_GEOIP,
    ALLOWED_HOSTS: ALLOWED_HOSTS,
    LANGUAGES: LANGUAGES,
    hostOf: hostOf,
    isAllowed: isAllowed,
    assertAllowed: assertAllowed,
    isPointId: isPointId,
    isStationAbbr: isStationAbbr,
    normalizedLanguage: normalizedLanguage,
    curlCommand: curlCommand,
    EXTERNAL_LINKS: EXTERNAL_LINKS,
    siteUrl: siteUrl,
    openDataUrl: openDataUrl,
    isExternalLink: isExternalLink,
    FORECAST_PAGES: FORECAST_PAGES,
    localForecastUrl: localForecastUrl,
    MAP_PAGES: MAP_PAGES,
    mapPageUrl: mapPageUrl,
    webcamPageUrl: webcamPageUrl,
    isMapPageUrl: isMapPageUrl,
    isForecastPageUrl: isForecastPageUrl,
    openCommand: openCommand,
    measurementsCommand: measurementsCommand,
    forecastCommand: forecastCommand,
    geoipCommand: geoipCommand
  }
}

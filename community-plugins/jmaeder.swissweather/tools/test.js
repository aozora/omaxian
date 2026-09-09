// Unit tests for the plugin's parsing and policy code.
//
//   node tools/test.js
//
// The QML in this plugin is a view over lib/*.js, and lib/*.js is where the
// security-relevant decisions live: what counts as a valid point id, which
// hosts may be contacted, what a hostile response is allowed to do. Those are
// exactly the things worth pinning down in a test rather than in a screenshot,
// so this file leans on the adversarial cases — the malformed row, the
// out-of-range value, the URL that only looks allowlisted.

const fs = require("fs")
const path = require("path")

const root = path.join(__dirname, "..")
const Net = require(path.join(root, "lib/Net.js"))
const Model = require(path.join(root, "lib/Model.js"))
const Places = require(path.join(root, "lib/Places.js"))
const Symbols = require(path.join(root, "lib/Symbols.js"))
const I18n = require(path.join(root, "lib/I18n.js"))

let passed = 0
const failures = []

function check(name, condition, detail) {
  if (condition) { passed++; return }
  failures.push(name + (detail === undefined ? "" : "  → " + detail))
}

function equal(name, actual, expected) {
  check(name, JSON.stringify(actual) === JSON.stringify(expected),
    "expected " + JSON.stringify(expected) + ", got " + JSON.stringify(actual))
}

// ---------------------------------------------------------------- Net policy

equal("host of a plain https url", Net.hostOf("https://data.geo.admin.ch/x.csv"), "data.geo.admin.ch")
equal("http is not https", Net.hostOf("http://data.geo.admin.ch/x"), "")
equal("userinfo is refused", Net.hostOf("https://data.geo.admin.ch@evil.example/x"), "")
equal("port syntax is refused", Net.hostOf("https://data.geo.admin.ch:8080/x"), "")
equal("scheme-relative is refused", Net.hostOf("//data.geo.admin.ch/x"), "")

check("allowlisted host passes", Net.isAllowed("https://data.geo.admin.ch/a"))
check("lookalike host is refused", !Net.isAllowed("https://data.geo.admin.ch.evil.example/a"))
check("suffix trick is refused", !Net.isAllowed("https://evildata.geo.admin.ch/a"))
check("unlisted host is refused", !Net.isAllowed("https://example.com/a"))
equal("assertAllowed blanks a bad url", Net.assertAllowed("https://example.com/a"), "")

check("six digits is a point id", Net.isPointId("800100"))
check("five digits is not", !Net.isPointId("80010"))
check("digits with a suffix is not", !Net.isPointId("800100a"))
check("injection attempt is not a point id", !Net.isPointId("800100&x=1"))
check("empty is not a point id", !Net.isPointId(""))

equal("unknown language falls back", Net.normalizedLanguage("es"), "en")
equal("language is truncated to two letters", Net.normalizedLanguage("FR_CH.UTF-8"), "fr")

const forecastCommand = Net.forecastCommand("800100", "fr")
check("forecast command is argv", Array.isArray(forecastCommand))
check("forecast command starts with curl", forecastCommand[0] === "/usr/bin/curl")
check("forecast command forbids redirects", forecastCommand.includes("--max-redirs") &&
  forecastCommand[forecastCommand.indexOf("--max-redirs") + 1] === "0")
check("forecast command pins https", forecastCommand.includes("--proto") &&
  forecastCommand[forecastCommand.indexOf("--proto") + 1] === "=https")
check("forecast command bounds size", forecastCommand.includes("--max-filesize"))
check("forecast command bounds time", forecastCommand.includes("--max-time"))
check("forecast command fails on http errors", forecastCommand.includes("--fail"))
check("forecast command ends with -- then the url",
  forecastCommand[forecastCommand.length - 2] === "--" &&
  forecastCommand[forecastCommand.length - 1] === "https://app-prod-ws.meteoswiss-app.ch/v1/plzDetail?plz=800100")
check("forecast command carries the language header",
  forecastCommand.includes("Accept-Language: fr"))
check("no shell anywhere in the command",
  !forecastCommand.some(arg => arg === "sh" || arg === "bash" || arg === "-c"))
equal("a bad point id yields no command", Net.forecastCommand("../../etc/passwd", "en"), null)
equal("an injected point id yields no command", Net.forecastCommand("800100 --output /tmp/x", "en"), null)

// ------------------------------------------------------- Net: outbound links

check("the site link is language-specific",
  Net.siteUrl("fr") === "https://www.meteosuisse.admin.ch/" &&
  Net.siteUrl("de") === "https://www.meteoschweiz.admin.ch/" &&
  Net.siteUrl("en") === "https://www.meteoswiss.admin.ch/")
equal("an unknown language falls back to the English site",
  Net.siteUrl("it"), "https://www.meteoswiss.admin.ch/")
equal("a published link opens", Net.openCommand(Net.openDataUrl()),
  ["xdg-open", "https://opendatadocs.meteoswiss.ch/"])
equal("an arbitrary url does not open", Net.openCommand("https://evil.example/"), null)
equal("a published link with anything appended does not open",
  Net.openCommand(Net.siteUrl("en") + "?x=1"), null)
equal("a file url does not open", Net.openCommand("file:///etc/passwd"), null)
equal("an argument-looking string does not open", Net.openCommand("--version"), null)
check("openable links never involve a shell", Object.keys(Net.EXTERNAL_LINKS).every(key => {
  const command = Net.openCommand(Net.EXTERNAL_LINKS[key])
  return command !== null && command[0] === "xdg-open" && command.length === 2
}))
// The fetch allowlist and the browser-link set are deliberately disjoint
// concerns; nothing openable should silently become fetchable.
check("no openable link is on the fetch allowlist",
  Object.keys(Net.EXTERNAL_LINKS).every(key => !Net.isAllowed(Net.EXTERNAL_LINKS[key])))

// -------------------------------------------- Net: MeteoSwiss page links
//
// The page slug is the town's name in the *page's* language — Genève is
// /genf/ in German and /geneva/ in English — so it is looked up in the table
// built from MeteoSwiss's own sitemaps, never derived. These pin both that the
// lookup produces the real URLs and that nothing else can be opened.

const forecastPages = Places.parseForecastPages(
  fs.readFileSync(path.join(root, "data/forecast-pages.csv"), "utf8"))

check("the page table is substantial", Object.keys(forecastPages).length > 3000,
  "got " + Object.keys(forecastPages).length)

function pageUrl(plz, lang) {
  return Net.localForecastUrl(plz, Places.pageSlug(forecastPages, plz, lang), lang)
}

equal("Geneva in German is genf",
  pageUrl("1204", "de"), "https://www.meteoschweiz.admin.ch/lokalprognose/genf/1204.html")
equal("Geneva in English is geneva",
  pageUrl("1204", "en"), "https://www.meteoswiss.admin.ch/local-forecasts/geneva/1204.html")
equal("Geneva in French is geneve",
  pageUrl("1204", "fr"), "https://www.meteosuisse.admin.ch/previsions-locales/geneve/1204.html")
equal("St. Gallen in French is saint-gall",
  pageUrl("9000", "fr"), "https://www.meteosuisse.admin.ch/previsions-locales/saint-gall/9000.html")
equal("Zurich keeps its German spelling on the German site",
  pageUrl("8001", "de"), "https://www.meteoschweiz.admin.ch/lokalprognose/zuerich/8001.html")
// Martigny is Martinach in German — the kind of exonym no slug rule derives,
// and the reason the table exists.
equal("Martigny in German is martinach",
  pageUrl("1920", "de"), "https://www.meteoschweiz.admin.ch/lokalprognose/martinach/1920.html")
equal("Martigny in French keeps its own name",
  pageUrl("1920", "fr"), "https://www.meteosuisse.admin.ch/previsions-locales/martigny/1920.html")
equal("a town with one name across languages resolves the same way",
  pageUrl("3818", "fr").split("/").slice(-2)[0], pageUrl("3818", "de").split("/").slice(-2)[0])
equal("an unknown postal code yields no link", pageUrl("9999", "fr"), "")
equal("a postal code with no page yields no link", pageUrl("1000", "fr"), "")

// Every slug in the shipped table must be a plain path segment: it goes
// straight into a URL handed to the browser.
check("every shipped slug is a safe path segment",
  Object.values(forecastPages).every(entry =>
    ["de", "fr", "en"].every(l => /^[a-z0-9-]{1,80}$/.test(entry[l]))))

// Every shipped postal code must produce an openable URL in all three
// languages — a table entry that cannot be opened is a dead link waiting.
check("every shipped postal code opens in all three languages",
  Object.keys(forecastPages).every(plz =>
    I18n.LANGUAGES.every(l => Net.openCommand(pageUrl(plz, l)) !== null)))

check("a constructed page URL is openable",
  Net.openCommand(pageUrl("1204", "de")) !== null)
equal("a path traversal is not openable",
  Net.openCommand("https://www.meteoschweiz.admin.ch/lokalprognose/../../etc/1204.html"), null)
equal("an extra path segment is not openable",
  Net.openCommand("https://www.meteoschweiz.admin.ch/lokalprognose/genf/1204.html/x"), null)
equal("a lookalike host is not openable",
  Net.openCommand("https://www.meteoschweiz.admin.ch.evil.example/lokalprognose/genf/1204.html"), null)
equal("the wrong path prefix is not openable",
  Net.openCommand("https://www.meteoschweiz.admin.ch/admin/genf/1204.html"), null)
equal("a non-numeric postal code is not openable",
  Net.openCommand("https://www.meteoschweiz.admin.ch/lokalprognose/genf/abcd.html"), null)
equal("an uppercase slug is refused", Net.localForecastUrl("1204", "Genf", "de"), "")
equal("a slug with a slash is refused", Net.localForecastUrl("1204", "a/b", "de"), "")
equal("a five-digit postal code is refused", Net.localForecastUrl("12040", "genf", "de"), "")
// The pages are opened in a browser, never fetched and parsed by the plugin.
check("page hosts are not on the fetch allowlist",
  Object.keys(Net.FORECAST_PAGES).every(l =>
    !Net.isAllowed("https://" + Net.FORECAST_PAGES[l].host + "/")))

// ------------------------------------------- Net: map and weather-cam links

equal("a map page is built per language",
  Net.mapPageUrl("precipitation", "fr"),
  "https://www.meteosuisse.admin.ch/services-et-publications/applications/precipitations.html")
equal("the page name is localised too, not just the path",
  Net.mapPageUrl("clouds", "de"),
  "https://www.meteoschweiz.admin.ch/service-und-publikationen/applikationen/bewoelkung.html")
equal("an unknown map has no url", Net.mapPageUrl("nuclear", "en"), "")
check("every map page is openable in every language",
  Object.keys(Net.MAP_PAGES).every(key =>
    Net.LANGUAGES.every(l => Net.openCommand(Net.mapPageUrl(key, l)) !== null)))

equal("a weather cam links to its own station on the networks page",
  Net.webcamPageUrl("KSL", "fr"),
  "https://www.meteosuisse.admin.ch/services-et-publications/applications/reseaux-de-mesure.html"
    + "#param=messnetz-webcams&station=KSL")
equal("an abbreviation that is not one yields no url", Net.webcamPageUrl("../etc", "fr"), "")
equal("a lowercase abbreviation is normalised", Net.webcamPageUrl("ksl", "en").slice(-3), "KSL")
check("a weather cam link is openable", Net.openCommand(Net.webcamPageUrl("KSL", "de")) !== null)

// The fragment is where a crafted string would try to get in, since it is the
// one part built from data rather than enumerated.
equal("another parameter in the fragment is not openable",
  Net.openCommand(Net.mapPageUrl("networks", "fr") + "#param=anything&station=KSL"), null)
equal("a fragment with an extra field is not openable",
  Net.openCommand(Net.mapPageUrl("networks", "fr")
    + "#param=messnetz-webcams&station=KSL&x=1"), null)
equal("the weather-cam fragment on any other map page is not openable",
  Net.openCommand(Net.mapPageUrl("wind", "fr") + "#param=messnetz-webcams&station=KSL"), null)
equal("a map page on a lookalike host is not openable",
  Net.openCommand("https://www.meteosuisse.admin.ch.evil.example"
    + "/services-et-publications/applications/precipitations.html"), null)
equal("a map page with an appended segment is not openable",
  Net.openCommand(Net.mapPageUrl("precipitation", "fr") + "/x"), null)

// ------------------------------------------------------------ Model: scalars

equal("dash means absent", Model.number("-", null), null)
equal("empty means absent", Model.number("", null), null)
equal("out-of-range temperature is dropped", Model.number("999", Model.BOUNDS.temperature), null)
equal("in-range temperature is kept", Model.number("25.4", Model.BOUNDS.temperature), 25.4)
equal("infinity is dropped", Model.number("Infinity", null), null)
equal("NaN text is dropped", Model.number("abc", null), null)

// Written as escapes rather than as literal bytes: a raw NUL in the source
// makes git treat this file as binary, and the test is about what the parser
// does with the characters, not about how they got into the file.
equal("control characters are stripped", Model.text("a\u0000b\u001bc"), "abc")
equal("a NUL alone is removed", Model.text("\u0000"), "")
equal("a bare escape sequence is removed", Model.text("\u001b[31mred\u001b[0m"), "[31mred[0m")
equal("newlines collapse to spaces", Model.text("a\nb"), "a b")
check("text is length capped", Model.text("x".repeat(10000)).length <= 400)
equal("markup is not interpreted, only carried", Model.text("<b>hi</b>"), "<b>hi</b>")

check("a long array is truncated", Model.numberSeries(new Array(5000).fill(1), null).length <= 400)
equal("nulls survive as gaps", Model.numberSeries([1, null, "x", 3], null), [1, null, null, 3])

// --------------------------------------------------------- Model: timestamps

const stamp = Model.parseCompactUtc("202608200920")
check("a compact UTC stamp parses", stamp !== null)
equal("stamp year", stamp.getUTCFullYear(), 2026)
equal("stamp minute", stamp.getUTCMinutes(), 20)
equal("an impossible date is refused", Model.parseCompactUtc("202602300000"), null)
equal("a short stamp is refused", Model.parseCompactUtc("2026082009"), null)
equal("a non-numeric stamp is refused", Model.parseCompactUtc("20260820092a"), null)
equal("month 13 is refused", Model.parseCompactUtc("202613200920"), null)

// ------------------------------------------------------ Model: measurements

const vqha80 = [
  "Station/Location;Date;tre200s0;rre150z0;sre000z0;gre000z0;ure200s0;tde200s0;dkl010z0;fu3010z0;fu3010z1;prestas0;pp0qffs0",
  "TAE;202608200920;25.30;0.00;0.00;480.00;46.30;13.00;294.00;5.40;12.20;949.40;1009.10",
  "COM;202608200920;20.10;0.20;10.00;146.00;94.70;19.20;189.00;4.00;8.30;946.70;1011.70",
  "BAD;notadate;1.0;-;-;-;-;-;-;-;-;-;-",
  "GAP;202608200920;-;-;-;-;-;-;-;-;-;-;-",
  "toolongabbr;202608200920;1.0;-;-;-;-;-;-;-;-;-;-",
  ""
].join("\n")

const measured = Model.parseMeasurements(vqha80)
equal("only well-formed rows parse", Object.keys(measured).sort(), ["COM", "GAP", "TAE"])
equal("a row with an unparseable date is skipped", measured.BAD, undefined)
equal("a row with an oversized abbreviation is skipped", measured.toolongabbr, undefined)
equal("temperature is read by column name", measured.TAE.tre200s0, 25.3)
equal("a zero reading stays zero, not absent", measured.TAE.rre150z0, 0)
equal("a dash becomes absent", measured.GAP.tre200s0, null)
equal("an all-dash row still carries its timestamp", measured.GAP.time instanceof Date, true)
equal("sunshine is read", measured.COM.sre000z0, 10)
check("the timestamp is a date", measured.TAE.time instanceof Date)
equal("header-only input yields nothing", Model.parseMeasurements("a;b\n"), {})
equal("garbage yields nothing", Model.parseMeasurements("not a csv"), {})
equal("empty input yields nothing", Model.parseMeasurements(""), {})

// Column order is not assumed anywhere.
const reordered = [
  "Date;Station/Location;fu3010z0;tre200s0",
  "202608200920;ABC;7.5;11.5"
].join("\n")
equal("columns are located by name", Model.parseMeasurements(reordered).ABC.tre200s0, 11.5)

// ---------------------------------------------------------- Model: forecast

equal("invalid json is not valid", Model.parseForecast("{oops").valid, false)
equal("an array payload is not valid", Model.parseForecast("[]").valid, false)
equal("empty input is not valid", Model.parseForecast("").valid, false)

const forecastPayload = JSON.stringify({
  currentWeather: { time: 1787218800000, icon: 3, iconV2: 27, temperature: 25.4 },
  forecast: [
    { dayDate: "2026-08-20", iconDay: 13, iconDayV2: 38, temperatureMax: 26, temperatureMin: 20,
      precipitation: 1.5, precipitationMin: 0.3, precipitationMax: 5.9 },
    { dayDate: "not-a-date", temperatureMax: 5 }
  ],
  graph: {
    start: 1787176800000,
    startLowResolution: 1787238000000,
    temperatureMean1h: [10, 11, 12],
    temperatureMin1h: [9, 10, 11],
    temperatureMax1h: [11, 12, 13],
    windSpeed1h: [5, 6, 7],
    windSpeed1hq10: [4, 5, 6],
    windSpeed1hq90: [8, 9, 10],
    sunshine1h: [0, 30, 60],
    precipitation10m: [0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.2],
    precipitationMin10m: [0, 0, 0, 0, 0, 0, 0],
    precipitationMax10m: [0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.4],
    precipitation1h: [2.0],
    precipitationMin1h: [1.0],
    precipitationMax1h: [4.0],
    weatherIcon3hV2: [102, 999, 3],
    windDirection3h: [90, 180, 270],
    precipitationProbability3h: [0, 50, 100],
    sunrise: [1787200113827],
    sunset: [1787250540773]
  },
  warnings: [
    { warnType: 10, warnLevel: 5, text: "Heat warning", htmlText: "<b>Heat</b>", links: [{ url: "https://x" }],
      validFrom: 1787230800000, validTo: 1787317200000 },
    { warnType: 1, warnLevel: 99, text: "" }
  ]
})

const forecast = Model.parseForecast(forecastPayload)
check("payload is valid", forecast.valid)
equal("iconV2 wins over icon", forecast.current.icon, 27)
equal("current temperature", forecast.current.temperature, 25.4)
equal("only well-formed days survive", forecast.days.length, 1)
equal("daily iconV2 wins", forecast.days[0].icon, 38)
equal("precipitation band survives", [forecast.days[0].precipitationMin, forecast.days[0].precipitationMax], [0.3, 5.9])
equal("an out-of-range symbol becomes null", forecast.graph.icon3h.values, [102, null, 3])
equal("hourly grid step", forecast.graph.temperature.stepMs, Model.HOUR_MS)
equal("ten-minute grid step", forecast.graph.precipitation10m.stepMs, Model.TEN_MINUTES_MS)
equal("hourly precipitation starts at the low-resolution boundary",
  forecast.graph.precipitation1h.startMs, 1787238000000)

equal("empty warning text is dropped", forecast.warnings.length, 1)
equal("warning text is carried", forecast.warnings[0].text, "Heat warning")
equal("out-of-range warning level is nulled",
  Model.parseForecast(JSON.stringify({ warnings: [{ warnLevel: 99, text: "x" }] })).warnings[0].level, null)
check("html and links are dropped from warnings",
  forecast.warnings[0].htmlText === undefined && forecast.warnings[0].links === undefined)

// The two precipitation series must join into one continuous hourly curve.
const graph = forecast.graph
const firstHour = Model.hourlyPrecipitation(graph, 1787176800000, 1787176800000 + Model.HOUR_MS)
equal("a full hour of ten-minute values is summed", firstHour[0].value, 0.6)
equal("the band is summed with it", [firstHour[0].min, firstHour[0].max], [0, 1.8])

const lowResHour = Model.hourlyPrecipitation(graph, 1787238000000, 1787238000000 + Model.HOUR_MS)
equal("beyond the ten-minute series the hourly one is used", lowResHour[0].value, 2.0)
equal("with its own band", [lowResHour[0].min, lowResHour[0].max], [1.0, 4.0])

const partialHour = Model.hourlyPrecipitation(graph, 1787176800000 + Model.HOUR_MS, 1787176800000 + 2 * Model.HOUR_MS)
equal("a partially covered hour is not reported as a total", partialHour[0].value, null)

equal("valueAt reads the right bucket", Model.valueAt(graph.temperature, 1787176800000 + Model.HOUR_MS), 11)
equal("valueAt before the series is null", Model.valueAt(graph.temperature, 0), null)
equal("valueAt past the series is null", Model.valueAt(graph.temperature, 4e12), null)

const sliced = Model.sliceSeries(graph.temperature, 1787176800000, 1787176800000 + 2 * Model.HOUR_MS)
equal("slice respects the half-open window", sliced.map(p => p.value), [10, 11])

// ------------------------------------------------- Model: uncertainty bands
//
// The forecast service does publish inconsistent bands — observed live: a
// ten-minute precipitation slot with min 0.3, expected 1.8 and max 0.0. Left
// alone that renders as "0.1-0.0 mm/h", which is not a range.

equal("an inverted band is put back in order",
  Model.orderedBand(0.3, 0.0, null), { low: 0, high: 0.3 })
equal("a band is widened to contain its own expected value",
  Model.orderedBand(0.3, 0.0, 1.8), { low: 0, high: 1.8 })
equal("an ordered band is left alone",
  Model.orderedBand(1.0, 5.9, 2.0), { low: 1.0, high: 5.9 })
equal("a single end becomes a zero-width band",
  Model.orderedBand(null, 5.9, null), { low: 5.9, high: 5.9 })
equal("no ends means no band", Model.orderedBand(null, null, 3), null)
equal("a formatted range is never inverted", Model.formatRange(0.1, 0.0, 1), "0.0–0.1")

// The same defence has to hold through the hourly aggregation, which is where
// the inconsistency was actually seen.
const invertedGraph = Model.parseForecast(JSON.stringify({
  currentWeather: { time: 1787176800000, icon: 1, temperature: 10 },
  graph: {
    start: 1787176800000,
    startLowResolution: 1787176800000 + 6 * Model.TEN_MINUTES_MS,
    precipitation10m: [0.3, 0.3, 0.3, 0.3, 0.3, 0.3],
    precipitationMin10m: [0.3, 0.3, 0.3, 0.3, 0.3, 0.3],
    precipitationMax10m: [0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
    precipitation1h: [2.0],
    precipitationMin1h: [4.0],
    precipitationMax1h: [1.0]
  }
})).graph

const invertedHour = Model.hourlyPrecipitation(invertedGraph, 1787176800000, 1787176800000 + Model.HOUR_MS)[0]
check("an aggregated hour keeps its band the right way round",
  invertedHour.min <= invertedHour.max,
  invertedHour.min + " > " + invertedHour.max)
check("the aggregated band contains the aggregated total",
  invertedHour.min <= invertedHour.value && invertedHour.value <= invertedHour.max,
  JSON.stringify(invertedHour))

// ------------------------------------------------------------ Model: geo-IP

equal("bad json yields no location", Model.parseGeoip("{"), null)
equal("a location without coordinates is refused", Model.parseGeoip('{"country_code":"CH"}'), null)
const swiss = Model.parseGeoip('{"latitude":46.94,"longitude":7.44,"country_code":"CH","ip":"1.2.3.4"}')
equal("swiss location is recognised", swiss.covered, true)
check("the ip address is not retained", swiss.ip === undefined)
equal("a foreign location is flagged",
  Model.parseGeoip('{"latitude":48.85,"longitude":2.35,"country_code":"FR"}').covered, false)
// MeteoSwiss forecasts Liechtenstein and its towns are in the shipped index,
// so an LI address must not be sent to Bern.
equal("liechtenstein is covered too",
  Model.parseGeoip('{"latitude":47.14,"longitude":9.52,"country_code":"LI"}').covered, true)
equal("a missing country is not covered",
  Model.parseGeoip('{"latitude":47.0,"longitude":8.0}').covered, false)

// ------------------------------------------------------------- Model: state

const state = Model.parseState(JSON.stringify({
  version: 1,
  language: "fr",
  favourites: [
    { pointId: "800100", plz: "8001", name: "Zürich", lat: 47.37, lon: 8.54 },
    { pointId: "800100", plz: "8001", name: "Zürich duplicate", lat: 47.37, lon: 8.54 },
    { pointId: "bad", name: "Nope", lat: 1, lon: 1 },
    { pointId: "100300", plz: "1003", name: "Lausanne", lat: 46.52, lon: 6.63 },
    { pointId: "300400", plz: "3004", name: "Bern", lat: 46.97, lon: 7.45 },
    { pointId: "900000", plz: "9000", name: "St. Gallen", lat: 47.42, lon: 9.37 }
  ],
  activePointId: "800100",
  geoDetected: true
}), I18n.LANGUAGES)

equal("language is restored", state.language, "fr")
equal("duplicates and invalid entries are dropped, the rest kept in order",
  state.favourites.map(f => f.pointId), ["800100", "100300", "300400", "900000"])
equal("active point is restored", state.activePointId, "800100")
equal("detection flag is restored", state.geoDetected, true)
equal("an unknown language is not accepted",
  Model.parseState('{"language":"es"}', I18n.LANGUAGES).language, "")
equal("corrupt state yields defaults",
  Model.parseState("]]not json[[", I18n.LANGUAGES).favourites, [])
equal("a non-object state yields defaults",
  Model.parseState('"hello"', I18n.LANGUAGES).activePointId, "")

// There is no product limit on favourites, only a guard against a corrupt or
// hand-edited file making the shell build an unbounded chip row.
check("the favourites cap is a safety bound, not three", Model.MAX_FAVOURITES > 3)
equal("an oversized favourites list is truncated to the safety bound",
  Model.parseState(JSON.stringify({
    favourites: Array.from({length: 500}, (_, i) => ({
      pointId: String(100000 + i), plz: "1000", name: "Town " + i, lat: 46.5, lon: 7.5
    }))
  }), I18n.LANGUAGES).favourites.length, Model.MAX_FAVOURITES)

// ------------------------------------------------------------- Model: units

equal("metric passes values through", Model.convert(25.4, "temperature", "metric"), 25.4)
equal("celsius to fahrenheit", Model.convert(100, "temperature", "imperial"), 212)
equal("freezing point", Model.convert(0, "temperature", "imperial"), 32)
check("millimetres to inches", Math.abs(Model.convert(25.4, "precipitation", "imperial") - 1) < 1e-9)
check("km/h to mph", Math.abs(Model.convert(100, "speed", "imperial") - 62.1371) < 1e-4)
check("km to miles", Math.abs(Model.convert(100, "distance", "imperial") - 62.1371) < 1e-4)
check("metres to feet", Math.abs(Model.convert(1000, "elevation", "imperial") - 3280.84) < 1e-2)
equal("sunshine minutes are not converted", Model.convert(30, "sunshine", "imperial"), 30)
equal("an unknown quantity is not converted", Model.convert(30, "humidity", "imperial"), 30)
equal("absent stays absent under conversion", Model.convert(null, "temperature", "imperial"), null)
equal("a non-number does not become one", Model.convert("abc", "temperature", "imperial"), null)
equal("an unknown unit system means metric", Model.normalizedUnits("nonsense"), "metric")
equal("units default to metric", Model.normalizedUnits(undefined), "metric")

// Inches need a decimal more than millimetres: a 2 mm shower is 0.08 in, which
// disappears entirely at one decimal place.
equal("millimetres use one decimal", Model.decimalsFor("precipitation", "metric"), 1)
equal("inches use two", Model.decimalsFor("precipitation", "imperial"), 2)
check("a small metric shower survives the round trip to inches",
  Model.formatNumber(Model.convert(2, "precipitation", "imperial"),
                     Model.decimalsFor("precipitation", "imperial")) === "0.08")

// -------------------------------------------------------- Model: warnings

equal("forest fire is a natural hazard", Model.warningCategory(10), "hazard")
equal("flood is a natural hazard", Model.warningCategory(11), "hazard")
equal("avalanche is a natural hazard", Model.warningCategory(8), "hazard")
equal("thunderstorm is a weather warning", Model.warningCategory(2), "weather")
equal("heat is a weather warning", Model.warningCategory(7), "weather")
// An unrecognised code must keep appearing rather than vanish into a category
// nobody has enabled.
equal("an unknown type counts as a weather warning", Model.warningCategory(77), "weather")
equal("a missing type counts as a weather warning", Model.warningCategory(null), "weather")
equal("the parsed warning carries its category", forecast.warnings[0].category, "hazard")

// The hazard a warning is about is read from the "what to do" link it carries,
// because the type numbering is not published. The link is language dependent,
// and the slug is not always the last path segment.
equal("a german hazard link names the hazard",
  Model.warningHazard({ warnType: 77, links: [{ url: "https://www.naturgefahren.ch/home/umgang-mit-naturgefahren/waldbrand.html?utm_source=app#vor-waldbrand" }] }),
  "forestFire")
equal("a french hazard link names the hazard",
  Model.warningHazard({ warnType: 77, links: [{ url: "https://www.dangers-naturels.ch/degres-danger/incendie-de-foret/comportement.html" }] }),
  "forestFire")
equal("an english hazard link names the hazard",
  Model.warningHazard({ warnType: 77, links: [{ url: "https://www.natural-hazards.ch/home/dealing-with-natural-hazards/rain.html?x=1#during-rain" }] }),
  "rain")
equal("a warning with no usable link falls back to its confirmed type number",
  Model.warningHazard({ warnType: 2, links: [] }), "rain")
equal("an unconfirmed type number stays unnamed",
  Model.warningHazard({ warnType: 77, links: [{ url: "https://example.com/whatever.html" }] }), "")
equal("a hazard key overrides an unrecognised type number",
  Model.warningCategory(77, "flood"), "hazard")
equal("a weather hazard key stays weather even for a hazard-range number",
  Model.warningCategory(10, "rain"), "weather")
// An absurdly long URL is not worth scanning, and is exactly what a hostile
// payload would use to make the scan expensive.
equal("an oversized url is ignored",
  Model.warningHazard({ warnType: 77, links: [{ url: "https://x/" + "a".repeat(600) + "/regen.html" }] }), "")
equal("a link that is not an object is ignored",
  Model.warningHazard({ warnType: 77, links: [null, 42, {}] }), "")

// The body is written as labelled points, one per line, and stays that way.
const warningBody = Model.warningLines(
  "- Mögliche Auswirkungen: Steigender Wasserpegel.\n- Erwartete Mengen: 20-40 mm\n\nSchneefallgrenze: 3500 m")
equal("each point becomes a line", warningBody.length, 3)
equal("the label is separated from its text", warningBody[0],
  { label: "Mögliche Auswirkungen", value: "Steigender Wasserpegel." })
equal("the bullet MeteoSwiss writes is not doubled", warningBody[1].label, "Erwartete Mengen")
equal("a line without a bullet is still a line", warningBody[2].label, "Schneefallgrenze")
equal("the french spaced colon splits too",
  Model.warningLines("- Conséquences possibles : Augmentation du niveau.")[0].label,
  "Conséquences possibles")
equal("a sentence with a late colon is not cut in two",
  Model.warningLines("Informationen zu den Massnahmen in den Kantonen finden Sie hier: auf der BAFU Webseite.")[0].label,
  "")
equal("an empty body yields no lines", Model.warningLines("   \n  \n").length, 0)
check("the number of lines is capped", Model.warningLines(new Array(50).join("a: b\n")).length <= 10)
check("a line is length-capped",
  Model.warningLines("x: " + "y".repeat(2000))[0].value.length <= 300)
equal("the flat text is still available", forecast.warnings[0].text, "Heat warning")
equal("the parsed warning carries its validity",
  [forecast.warnings[0].from, forecast.warnings[0].to], [1787230800000, 1787317200000])

// The identity of a warning decides whether a notification is a repeat.
const notifiable = { hazard: "flood", level: 4, from: 1787230800000, to: 1787317200000 }
equal("a warning has a stable key", Model.warningKey(notifiable, 613700),
  "613700|flood|4|1787230800000|1787317200000")
equal("re-wording a warning does not change its key",
  Model.warningKey(Object.assign({}, notifiable, { lines: [{ label: "", value: "new text" }] }), 613700),
  Model.warningKey(notifiable, 613700))
check("raising the level changes the key",
  Model.warningKey(Object.assign({}, notifiable, { level: 5 }), 613700) !== Model.warningKey(notifiable, 613700))
check("extending the period changes the key",
  Model.warningKey(Object.assign({}, notifiable, { to: 1787400000000 }), 613700) !== Model.warningKey(notifiable, 613700))
// One regional warning covers many towns identically; each town still has to
// be told about it once.
check("the same warning in two towns is two keys",
  Model.warningKey(notifiable, 613700) !== Model.warningKey(notifiable, 190000))
equal("an unnamed hazard still keys on its type number",
  Model.warningKey({ type: 77, level: 3, from: 1, to: 2 }, 1), "1|77|3|1|2")
equal("a missing warning has no key", Model.warningKey(null, 613700), "")
equal("a warning with no town is still keyed",
  Model.warningKey({ type: 7, level: 3, from: 1, to: 2 }, null), "?|7|3|1|2")
check("a key cannot grow unbounded",
  Model.warningKey({ hazard: "x".repeat(500), level: 3, from: 1, to: 2 }, 613700).length <= 64)
check("the town survives the length cap",
  Model.warningKey({ hazard: "x".repeat(500), level: 3, from: 1, to: 2 }, 613700).indexOf("613700|") === 0)

equal("level 3 is worth interrupting someone", Model.isNotifiable({ level: 3 }), true)
equal("level 5 is worth interrupting someone", Model.isNotifiable({ level: 5 }), true)
equal("level 2 is not", Model.isNotifiable({ level: 2 }), false)
equal("an unknown level is not", Model.isNotifiable({ level: null }), false)

// Notifications are off until asked for, and the seen list is bounded because
// it is written to disk and read back on every start.
equal("notifications are off by default",
  Model.parseState("{}", I18n.LANGUAGES).notifyWarnings, false)
equal("a non-boolean does not switch notifications on",
  Model.parseState('{"notifyWarnings":"yes"}', I18n.LANGUAGES).notifyWarnings, false)
equal("notifications survive a round trip",
  Model.parseState(JSON.stringify(Model.serializeState({ notifyWarnings: true, seenWarnings: ["a"] })),
                   I18n.LANGUAGES).notifyWarnings, true)
equal("the seen list is deduplicated",
  Model.parseState('{"seenWarnings":["a","a","b"]}', I18n.LANGUAGES).seenWarnings, ["a", "b"])
check("the seen list is capped", (() => {
  const many = Array.from({ length: 500 }, (_, i) => "k" + i)
  return Model.parseState(JSON.stringify({ seenWarnings: many }), I18n.LANGUAGES)
    .seenWarnings.length === Model.MAX_SEEN_WARNINGS
})())
check("the newest keys are the ones kept on write", (() => {
  const many = Array.from({ length: 500 }, (_, i) => "k" + i)
  const kept = Model.serializeState({ seenWarnings: many }).seenWarnings
  return kept.length === Model.MAX_SEEN_WARNINGS && kept[kept.length - 1] === "k499"
})())
equal("a seen entry that is not a string is dropped",
  Model.parseState('{"seenWarnings":[null,{},"ok"]}', I18n.LANGUAGES).seenWarnings, ["ok"])

// Warning bodies are the one place rich text is used, so the escape that makes
// that safe is worth pinning down.
equal("markup in remote text is escaped",
  Model.escapeMarkup("<b>x</b> & <img src=a onerror=b>"),
  "&lt;b&gt;x&lt;/b&gt; &amp; &lt;img src=a onerror=b&gt;")
equal("an entity cannot be smuggled in", Model.escapeMarkup("&lt;b&gt;"), "&amp;lt;b&amp;gt;")

const roundTripped = Model.parseState(JSON.stringify(Model.serializeState(state)), I18n.LANGUAGES)
equal("state survives a round trip", roundTripped.favourites.map(f => f.name),
  state.favourites.map(f => f.name))

// ---------------------------------------------------------- Model: format

equal("absent renders as a dash", Model.formatNumber(null, 1), "—")
equal("a band collapses when both ends agree", Model.formatRange(2.04, 2.04, 1), "2.0")
equal("a band renders as a range", Model.formatRange(1.0, 5.9, 1), "1.0–5.9")
equal("a half-known band renders the known end", Model.formatRange(null, 5.9, 1), "5.9")
equal("north wraps correctly", Model.compassIndex(359), 0)
equal("south west is index 5", Model.compassIndex(225), 5)
equal("absent direction has no compass index", Model.compassIndex(null), -1)
equal("a non-numeric bearing has no compass index", Model.compassIndex("abc"), -1)

// --------------------------------------------------------------- Places

equal("diacritics fold", Places.fold("Genève"), "geneve")
equal("case folds", Places.fold("ZÜRICH"), "zurich")
equal("hyphens become spaces", Places.fold("La Chaux-de-Fonds"), "la chaux de fonds")

const placesCsv = fs.readFileSync(path.join(root, "data/places.csv"), "utf8")
const places = Places.parsePlaces(placesCsv)
check("the shipped index is substantial", places.length > 3000, "got " + places.length)
check("every point id is six digits", places.every(p => /^[0-9]{6}$/.test(p.pointId)))
check("every coordinate is inside Switzerland",
  places.every(p => p.lat > 45.5 && p.lat < 48 && p.lon > 5.5 && p.lon < 11))

equal("comment and header lines are skipped",
  Places.parsePlaces("# a comment\npoint_id;plz;name;lat;lon;alt\n800100;8001;Zürich;47.37;8.54;408\n").length, 1)
equal("a short row is skipped", Places.parsePlaces("800100;8001;Zürich\n").length, 0)
equal("a bad point id is skipped", Places.parsePlaces("80010;8001;Zürich;47.37;8.54;408\n").length, 0)

const webcams = Places.parseWebcams(fs.readFileSync(path.join(root, "data/webcams.csv"), "utf8"))
check("the shipped weather-cam index is present", webcams.length >= 30, "got " + webcams.length)
check("every cam is inside Switzerland",
  webcams.every(w => w.lat > 45.5 && w.lat < 48 && w.lon > 5.5 && w.lon < 11))
check("every cam abbreviation is one Net will accept",
  webcams.every(w => Net.webcamPageUrl(w.abbr, "en") !== ""))
// The starting town when detection is off, fails, or lands abroad. Pinned to
// what it means rather than to the string "301100": if the index ever moves
// that point, this fails instead of quietly starting people somewhere else.
const FEDERAL_PALACE = { lat: 46.946581, lon: 7.444117 }
const fallback = Places.nearestPlace(places, FEDERAL_PALACE.lat, FEDERAL_PALACE.lon)
equal("the fallback town is the postal code of the Federal Palace", fallback.pointId, "301100")
check("and it is within a few hundred metres of it", fallback.distanceKm < 0.5,
  Math.round(fallback.distanceKm * 1000) + " m")
equal("Vaduz is in the index, so a Liechtenstein address has its own town",
  Places.nearestPlace(places, 47.1410, 9.5209).name, "Vaduz")

// An address abroad but on the doorstep gets the town across the border, which
// shares its weather; one far enough away gets nothing and falls back.
const nearBorder = (name, lat, lon) => {
  const place = Places.nearestPlaceWithin(places, lat, lon, Places.MAX_BORDER_DISTANCE_KM)
  return place === null ? null : place.name
}
equal("Annemasse gets a Geneva town", nearBorder("Annemasse", 46.1920, 6.2340), "Puplinge")
equal("Konstanz gets Kreuzlingen", nearBorder("Konstanz", 47.6600, 9.1750), "Kreuzlingen")
equal("Como gets Chiasso", nearBorder("Como", 45.8081, 9.0852), "Chiasso")
equal("Saint-Louis gets Basel", nearBorder("Saint-Louis", 47.5900, 7.5600), "Basel")
// Milan is 42 km from the nearest Swiss town — a city with a forecast of its
// own, and the first case the limit has to exclude.
equal("Milan is too far", nearBorder("Milan", 45.4642, 9.1900), null)
equal("Lyon is too far", nearBorder("Lyon", 45.7640, 4.8357), null)
equal("Munich is too far", nearBorder("Munich", 48.1351, 11.5820), null)
equal("no places means no border town",
  Places.nearestPlaceWithin([], 46.19, 6.23, Places.MAX_BORDER_DISTANCE_KM), null)
check("an unbounded limit always answers",
  Places.nearestPlaceWithin(places, 48.8566, 2.3522, Infinity) !== null)

equal("the nearest cam to Engelberg is Kaiserstuhl",
  Places.nearestWebcam(webcams, 46.8199, 8.4083).abbr, "KSL")
equal("the nearest cam carries its distance",
  Math.round(Places.nearestWebcam(webcams, 46.1004, 7.0745).distanceKm), 2)
equal("no cams means no nearest cam", Places.nearestWebcam([], 46.8, 8.4), null)
equal("a place with no coordinates has no nearest cam",
  Places.nearestWebcam(webcams, null, null), null)

// The canton disambiguates towns of the same name, so a wrong one is worse
// than none: the column is only believed when it looks like a canton code.
equal("the canton is read", Places.parsePlaces("800100;8001;Zürich;47.37;8.54;408;ZH\n")[0].canton, "ZH")
equal("an index without the column still parses",
  Places.parsePlaces("800100;8001;Zürich;47.37;8.54;408\n")[0].canton, "")
equal("a malformed canton is dropped",
  Places.parsePlaces("800100;8001;Zürich;47.37;8.54;408;zurich\n")[0].canton, "")
check("almost every shipped town has a canton",
  places.filter(p => p.canton === "").length < 40,
  places.filter(p => p.canton === "").length + " without one")
check("every canton is a two-letter code",
  places.every(p => p.canton === "" || /^[A-Z]{2}$/.test(p.canton)))
check("Engelberg is in Obwalden, not in the canton with the smaller share",
  places.some(p => p.name === "Engelberg" && p.plz === "6390" && p.canton === "OW"))
check("only real cantons appear", (() => {
  const cantons = new Set(places.map(p => p.canton).filter(c => c !== ""))
  const official = new Set(["ZH", "BE", "LU", "UR", "SZ", "OW", "NW", "GL", "ZG", "FR",
                            "SO", "BS", "BL", "SH", "AR", "AI", "SG", "GR", "AG", "TG",
                            "TI", "VD", "VS", "NE", "GE", "JU"])
  return [...cantons].every(c => official.has(c)) && cantons.size === official.size
})())

equal("an accent-free query finds the accented town",
  Places.search(places, "geneve").some(p => p.name === "Genève"), true)
equal("a postal code query works", Places.search(places, "8001")[0].plz, "8001")
equal("a one-letter query returns nothing", Places.search(places, "z").length, 0)
check("results are capped", Places.search(places, "a").length <= Places.MAX_RESULTS)
check("an enormous query is handled", Places.search(places, "x".repeat(100000)).length === 0)
check("prefix matches outrank substring matches", (() => {
  const results = Places.search(places, "bern")
  return results.length > 0 && Places.fold(results[0].name).startsWith("bern")
})())

const stations = Places.parseStations(fs.readFileSync(path.join(root, "data/stations.csv"), "utf8"))
check("stations parse", stations.length > 100, "got " + stations.length)
const nearBern = Places.nearestStation(stations, 46.9477, 7.4459)
check("a station near Bern is found", nearBern !== null && nearBern.distanceKm < 15,
  nearBern ? nearBern.name + " " + nearBern.distanceKm : "none")
check("the returned station carries a distance", typeof nearBern.distanceKm === "number")
check("the index itself is not annotated", stations.every(s => s.distanceKm === undefined))

// Station selection is the panel's most consequential judgement call, so it is
// pinned against the real Rhône-valley geometry that motivated it.
const alpine = [
  { abbr: "MAR", name: "Les Marécottes", lat: 46.1416, lon: 7.0086, altitude: 1140 },
  { abbr: "SIO", name: "Sion",           lat: 46.2186, lon: 7.3305, altitude: 482 },
  { abbr: "ATT", name: "Les Attelas",    lat: 46.0994, lon: 7.2694, altitude: 2733 }
]
const martigny = { lat: 46.1020, lon: 7.0734, altitude: 471 }
const allWanted = ["tre200s0", "rre150z0", "fu3010z0", "sre000z0"]

// With nothing reported anywhere, cost alone decides — and altitude is part of
// cost, so the 2733 m summit must not win over a valley station.
const noReadings = Places.selectStation(alpine, {}, martigny.lat, martigny.lon, martigny.altitude, allWanted)
check("a summit station does not win for a valley town", noReadings.abbr !== "ATT", noReadings.abbr)

// The nearest station reporting nothing must lose to a further one reporting.
const readings = {
  MAR: { tre200s0: null, rre150z0: null, fu3010z0: null, sre000z0: null },
  SIO: { tre200s0: 24.5, rre150z0: 0, fu3010z0: 4.7, sre000z0: 0 },
  ATT: { tre200s0: 9.3, rre150z0: null, fu3010z0: 27, sre000z0: 9 }
}
const chosen = Places.selectStation(alpine, readings, martigny.lat, martigny.lon, martigny.altitude, allWanted)
equal("a reporting station beats a nearer silent one", chosen.abbr, "SIO")
equal("coverage is reported", chosen.coverage, 4)
check("the distance actually travelled is reported", chosen.distanceKm > 20 && chosen.distanceKm < 30,
  String(chosen.distanceKm))

// A silent station is still named when it is the only one reporting nothing —
// the panel needs something to attribute the blank readings to.
const allSilent = Places.selectStation(alpine, { MAR: {}, SIO: {}, ATT: {} },
  martigny.lat, martigny.lon, martigny.altitude, allWanted)
check("a station is always named", allSilent !== null)
equal("zero coverage is reported as zero", allSilent.coverage, 0)

// Altitude is what separates these two, not distance.
check("altitude enters the cost", (() => {
  const valley = Places.stationCost(alpine[1], martigny.lat, martigny.lon, martigny.altitude)
  const summit = Places.stationCost(alpine[2], martigny.lat, martigny.lon, martigny.altitude)
  return summit > valley
})())
equal("no stations means no selection",
  Places.selectStation([], {}, martigny.lat, martigny.lon, martigny.altitude, allWanted), null)
equal("a bad coordinate means no selection",
  Places.selectStation(alpine, {}, null, null, 400, allWanted), null)

// Against the shipped index, every town must resolve to some station.
check("every shipped town resolves to a station", places.every(p =>
  Places.selectStation(stations, {}, p.lat, p.lon, p.altitude, allWanted) !== null))

// Distances must be symmetric and roughly right: Bern to Zürich is ~95 km.
const bernToZurich = Places.distanceKm(46.9477, 7.4459, 47.3769, 8.5417)
check("Bern to Zürich is about 95 km", bernToZurich > 90 && bernToZurich < 100, String(bernToZurich))

// --------------------------------------------------------------- Symbols

equal("day symbols parse", Symbols.parse(1), { base: 1, night: false })
equal("night symbols parse", Symbols.parse(127), { base: 27, night: true })
equal("out-of-range symbols do not", Symbols.parse(43), null)
equal("symbol 0 does not", Symbols.parse(0), null)
equal("nonsense does not", Symbols.parse("abc"), null)

check("every day symbol has a glyph", (() => {
  for (let code = 1; code <= 42; code++) {
    if (!Symbols.glyph(code) || Symbols.glyph(code) === Symbols.GLYPH_UNKNOWN) return false
  }
  return true
})())
check("every night symbol has a glyph", (() => {
  for (let code = 101; code <= 142; code++) {
    if (!Symbols.glyph(code) || Symbols.glyph(code) === Symbols.GLYPH_UNKNOWN) return false
  }
  return true
})())
equal("an unknown symbol gets the fallback glyph", Symbols.glyph(500), Symbols.GLYPH_UNKNOWN)
equal("the fallback is not the circle-cross glyph that renders as the Xbox logo",
  Symbols.GLYPH_UNKNOWN.codePointAt(0) === 0xe29d, false)
equal("the fallback is the cloudy-alert glyph", Symbols.GLYPH_UNKNOWN.codePointAt(0), 0xf0f2f)

check("every symbol is described in every language", (() => {
  for (const lang of I18n.LANGUAGES) {
    for (let code = 1; code <= 42; code++) {
      if (!Symbols.describe(code, lang)) return false
      if (!Symbols.describe(code + 100, lang)) return false
    }
  }
  return true
})())
equal("clear night reads as clear, not sunny", Symbols.describe(101, "en"), "Clear")
equal("the day counterpart still reads as sunny", Symbols.describe(1, "en"), "Sunny")

// ----------------------------------------------------------------- I18n

check("every language defines every key", (() => {
  const reference = Object.keys(I18n.STRINGS.en)
  return I18n.LANGUAGES.every(lang =>
    reference.every(key => I18n.STRINGS[lang][key] !== undefined))
})())
check("no language has a stray key", (() => {
  const reference = Object.keys(I18n.STRINGS.en).sort().join(",")
  return I18n.LANGUAGES.every(lang => Object.keys(I18n.STRINGS[lang]).sort().join(",") === reference)
})())
check("every language names seven weekdays",
  I18n.LANGUAGES.every(lang => I18n.STRINGS[lang].weekdays.length === 7))
equal("a locale seeds the language", I18n.defaultLanguage("de_CH.UTF-8"), "de")
equal("an unsupported locale falls back to English", I18n.defaultLanguage("it_CH.UTF-8"), "en")
equal("a missing key renders as itself", I18n.t("en", "no-such-key"), "no-such-key")

check("every language names every hazard", I18n.LANGUAGES.every(lang => {
  const reference = Object.keys(I18n.STRINGS.en.hazards).sort().join(",")
  return Object.keys(I18n.STRINGS[lang].hazards).sort().join(",") === reference
}))
check("every language spells out the five danger levels",
  I18n.LANGUAGES.every(lang => I18n.STRINGS[lang].dangerLevels.length === 5))
check("every hazard the model can identify has a name",
  Model.NATURAL_HAZARD_KEYS.concat(["thunderstorm", "rain", "snow", "slipperyRoads",
                                    "frost", "heat", "wind"])
    .every(key => I18n.LANGUAGES.every(lang => I18n.STRINGS[lang].hazards[key] !== undefined)))
equal("a hazard is named in the panel language", I18n.hazardName("de", "forestFire"), "Waldbrand")
// Not "forestFire", and not a guess: a warning whose type the plugin has not
// confirmed still has a level and a text worth reading.
equal("an unnamed hazard falls back to the plain word", I18n.hazardName("fr", "nope"), "Alerte")
equal("a danger level is spelled out", I18n.dangerLevelName("fr", 4), "Fort danger")
equal("an out-of-range danger level has no name", I18n.dangerLevelName("en", 9), "")
equal("a missing danger level has no name", I18n.dangerLevelName("en", null), "")

// West is W in English and German but O in French; east is E in English and
// French but O in German. Getting this wrong reverses the wind on screen.
equal("english west", I18n.compass("en", 270), "W")
equal("french west is O", I18n.compass("fr", 270), "O")
equal("german west is W", I18n.compass("de", 270), "W")
equal("english east", I18n.compass("en", 90), "E")
equal("french east is E", I18n.compass("fr", 90), "E")
equal("german east is O", I18n.compass("de", 90), "O")
equal("french north-west is NO", I18n.compass("fr", 315), "NO")
equal("german north-east is NO", I18n.compass("de", 45), "NO")
equal("north wraps in every language",
  I18n.LANGUAGES.map(l => I18n.compass(l, 359)), ["N", "N", "N"])
equal("an absent bearing has no compass point", I18n.compass("fr", null), "")
check("every language names eight compass points",
  I18n.LANGUAGES.every(lang => I18n.STRINGS[lang].compass.length === 8))
check("no language leaves a compass point untranslated",
  I18n.LANGUAGES.every(lang => I18n.STRINGS[lang].compass.every(p => typeof p === "string" && p.length > 0)))
equal("the attribution is present in every language",
  I18n.LANGUAGES.map(l => I18n.t(l, "source").length > 0), [true, true, true])

// ------------------------------------------------ summary notification table

// A fake proportional font: wide W, narrow i, and the four padding units at
// their real proportions. Nothing here depends on Liberation Sans — what is
// being tested is that the layout closes the gap whatever the metric says.
const FAKE_WIDTH = { W: 16, i: 4, l: 4, ".": 4, " ": 5, " ": 10, " ": 5, " ": 3.5, " ": 1.5 }
const fakeMeasure = text => Array.from(String(text))
  .reduce((sum, ch) => sum + (FAKE_WIDTH[ch] === undefined ? 10 : FAKE_WIDTH[ch]), 0)

// Resolve what the card would render, so a laid-out row can be measured back.
const rendered = line => line
  .replace(/&#8199;/g, " ").replace(/&nbsp;/g, " ")
  .replace(/&#8201;/g, " ").replace(/&#8202;/g, " ")
  .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&")

const summaryRows = [
  { name: "Martigny (VS)", values: ["23.9 °C", "0.0 mm", "18 km/h", "7 min"] },
  { name: "Engelberg (OW)", values: ["9.5 °C", "0.0 mm", "8 km/h", "10 min"] },
  { name: "Davos Dorf (GR)", values: ["17.4 °C", "12.4 mm", "128 km/h", "0 min"] }
]

const laidOut = Model.summaryTable(summaryRows, fakeMeasure, 2000)
const laidOutWidths = laidOut.map(line => fakeMeasure(rendered(line)))
check("every row ends on the same pixel",
  Math.max(...laidOutWidths) - Math.min(...laidOutWidths) <= FAKE_WIDTH[" "] / 2 + 0.01,
  laidOutWidths.join(" "))

// Equal totals alone would not prove alignment. The separator never occurs
// inside a name, so the rendered row splits back into its cells: every cell
// must be the same width in every row, which is what a column is.
const cells = laidOut.map(line => rendered(line).split(" · ").map(fakeMeasure))
for (let c = 0; c < cells[0].length; c++) {
  const column = cells.map(row => row[c])
  check("column " + c + " is one width for every row",
    Math.max(...column) - Math.min(...column) <= 1, column.join(" "))
}

check("a row that already fits is not elided", laidOut.every(line => line.indexOf("…") === -1))

// Narrow enough that the longest name cannot stand: it is cut, not wrapped.
const narrowWidth = Math.max(...laidOutWidths) - 40
const narrow = Model.summaryTable(summaryRows, fakeMeasure, narrowWidth)
check("a name too wide for the column is elided",
  narrow.some(line => line.indexOf(Model.SUMMARY_ELLIPSIS) !== -1), narrow.join(" | "))
check("an elided row still fits the width",
  narrow.every(line => fakeMeasure(rendered(line)) <= narrowWidth + 1),
  narrow.map(line => fakeMeasure(rendered(line))).join(" "))
check("elision keeps the head of the name", rendered(narrow[0]).indexOf("Mart") === 0, narrow[0])

const hostile = Model.summaryTable(
  [{ name: "<b>&x</b>", values: ["1 °C"] }, { name: "Bern (BE)", values: ["2 °C"] }],
  fakeMeasure, 2000)
check("a name cannot open a tag", hostile[0].indexOf("&lt;b&gt;&amp;x") !== -1, hostile[0])

equal("no rows, no table", Model.summaryTable([], fakeMeasure, 400), [])

// ------------------------------------------------- notification argv shape

// omarchy-notification-send reads every word after --exec as the click
// command's argv, so --exec has to come last and its command has to be
// separate words. Get either wrong and the notification is not sent at all:
// the plugin's only symptom is silence, because execDetached discards the
// error. Cheap to pin down here, impossible to notice in a screenshot.
const panelQml = fs.readFileSync(path.join(root, "Panel.qml"), "utf8")
const notifyCalls = panelQml
  .split("Quickshell.execDetached([")
  .slice(1)
  .map(chunk => chunk.slice(0, chunk.indexOf("])")))
  .filter(chunk => chunk.indexOf("omarchy-notification-send") !== -1)

check("every notification call was found", notifyCalls.length === 2, notifyCalls.length + " found")

for (const call of notifyCalls) {
  const argv = call
    .replace(/\/\/[^\n]*/g, "")
    .split(",")
    .map(a => a.trim())
    .filter(a => a.length > 0)
  const exec = argv.indexOf('"--exec"')
  check("the click command is present", exec !== -1)
  const words = argv.slice(exec + 1)
  check("the click command is the last thing in the argv",
    words.length > 0 && words.every(w => /^"[^"\s]+"$/.test(w)),
    words.join(" "))
}

// ------------------------------------------------------------------ report

console.log(`${passed} passed, ${failures.length} failed`)
if (failures.length > 0) {
  for (const failure of failures) console.log("  FAIL  " + failure)
  process.exit(1)
}

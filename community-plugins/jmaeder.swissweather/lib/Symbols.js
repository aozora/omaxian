// MeteoSwiss weather symbols.
//
// MeteoSwiss numbers its weather symbols 1-42 for daytime and 101-142 for the
// corresponding night situation. Those numbers arrive in `icon` / `iconV2` from
// the forecast service and in the `jww003i0` / `jp2000d0` Open Data parameters.
//
// The MeteoSwiss symbol *graphics* are proprietary and may not be reused, but
// the Open Data documentation states that "the number and description of the
// weather symbols may be utilised and matched with graphics that are permitted
// for use". So this file maps each number onto a Nerd Font weather glyph and
// carries its own trilingual wording of the situation the number denotes.
//
// Every codepoint below is verified present in the Nerd Font that Omarchy
// ships; the shared subset is the same one the built-in omarchy.weather widget
// draws from, so a theme that renders one renders the other.

// Shown when there is no symbol to show: a cloud carrying an exclamation
// mark, which reads as "weather, but not available". Not U+E29D — that
// codepoint is a filled circle with a cross through it and renders as the
// Xbox logo, which is not what an absent forecast should look like.
var GLYPH_UNKNOWN = "󰼯" // nf-md-weather-cloudy-alert

// day glyph, night glyph. A single entry means the symbol looks the same
// either way (rain is rain; only the sun/moon-bearing symbols differ).
var GLYPHS = {
  1:  ["", ""], // sunny            / clear
  2:  ["", ""], // day cloudy       / night cloudy
  3:  ["", ""], // sunny overcast   / night partly cloudy
  4:  [""],           // cloudy
  5:  [""],           // cloud
  6:  ["", ""], // day showers      / night showers
  7:  ["", ""], // day sleet        / night sleet
  8:  ["", ""], // day snow         / night snow
  9:  [""],           // showers
  10: [""],           // sleet
  11: [""],           // snow
  12: ["", ""], // day thunder      / night thunder
  13: ["", ""],
  14: [""],
  15: [""],
  16: [""],
  17: [""],           // rain
  18: [""],
  19: [""],
  20: [""],
  21: [""],
  22: [""],
  23: [""],           // thunderstorm
  24: [""],
  25: [""],
  26: ["", ""],
  27: ["", ""], // fog / night fog — stratus reads as a fog layer
  28: ["", ""],
  29: ["", ""],
  30: ["", ""],
  31: ["", ""],
  32: ["", ""],
  33: [""],
  34: [""],
  35: [""],
  36: ["", ""],
  37: ["", ""], // day snow+thunder / night snow+thunder
  38: [""],
  39: ["", ""],
  40: [""],
  41: [""],
  42: ["", ""]
}

// Situation described by each daytime symbol number.
var DAY_TEXT = {
  1:  { en: "Sunny", fr: "Ensoleillé", de: "Sonnig" },
  2:  { en: "Mostly sunny, some clouds", fr: "Assez ensoleillé, quelques nuages", de: "Meist sonnig, einige Wolken" },
  3:  { en: "Partly sunny, passing clouds", fr: "Partiellement ensoleillé, passages nuageux", de: "Teils sonnig, durchziehende Wolken" },
  4:  { en: "Overcast", fr: "Couvert", de: "Bedeckt" },
  5:  { en: "Very cloudy", fr: "Très nuageux", de: "Stark bewölkt" },
  6:  { en: "Sunny intervals, isolated showers", fr: "Éclaircies, averses isolées", de: "Sonnige Abschnitte, einzelne Schauer" },
  7:  { en: "Sunny intervals, isolated sleet", fr: "Éclaircies, giboulées isolées", de: "Sonnige Abschnitte, einzelne Schneeregenschauer" },
  8:  { en: "Sunny intervals, snow showers", fr: "Éclaircies, averses de neige", de: "Sonnige Abschnitte, Schneeschauer" },
  9:  { en: "Overcast, some rain showers", fr: "Couvert, quelques averses", de: "Bedeckt, einige Regenschauer" },
  10: { en: "Overcast, some sleet", fr: "Couvert, quelques giboulées", de: "Bedeckt, etwas Schneeregen" },
  11: { en: "Overcast, some snow showers", fr: "Couvert, quelques averses de neige", de: "Bedeckt, einige Schneeschauer" },
  12: { en: "Sunny intervals, chance of thunderstorms", fr: "Éclaircies, risque d’orages", de: "Sonnige Abschnitte, Gewitterneigung" },
  13: { en: "Sunny intervals, possible thunderstorms", fr: "Éclaircies, orages possibles", de: "Sonnige Abschnitte, mögliche Gewitter" },
  14: { en: "Very cloudy, light rain", fr: "Très nuageux, pluie faible", de: "Stark bewölkt, leichter Regen" },
  15: { en: "Very cloudy, light sleet", fr: "Très nuageux, neige mêlée de pluie faible", de: "Stark bewölkt, leichter Schneeregen" },
  16: { en: "Very cloudy, light snow showers", fr: "Très nuageux, faibles averses de neige", de: "Stark bewölkt, leichte Schneeschauer" },
  17: { en: "Very cloudy, intermittent rain", fr: "Très nuageux, pluie intermittente", de: "Stark bewölkt, zeitweise Regen" },
  18: { en: "Very cloudy, intermittent sleet", fr: "Très nuageux, neige mêlée de pluie intermittente", de: "Stark bewölkt, zeitweise Schneeregen" },
  19: { en: "Very cloudy, intermittent snow", fr: "Très nuageux, neige intermittente", de: "Stark bewölkt, zeitweise Schneefall" },
  20: { en: "Overcast with rain", fr: "Couvert avec pluie", de: "Bedeckt mit Regen" },
  21: { en: "Overcast with frequent sleet", fr: "Couvert, neige mêlée de pluie fréquente", de: "Bedeckt mit häufigem Schneeregen" },
  22: { en: "Overcast with heavy snow", fr: "Couvert avec fortes chutes de neige", de: "Bedeckt mit starkem Schneefall" },
  23: { en: "Overcast, slight chance of storms", fr: "Couvert, faible risque d’orages", de: "Bedeckt, geringe Gewitterneigung" },
  24: { en: "Overcast with thunderstorms", fr: "Couvert avec orages", de: "Bedeckt mit Gewittern" },
  25: { en: "Very cloudy, very stormy", fr: "Très nuageux, fortement orageux", de: "Stark bewölkt, kräftige Gewitter" },
  26: { en: "High cloud", fr: "Nuages élevés", de: "Hohe Bewölkung" },
  27: { en: "Stratus", fr: "Stratus", de: "Hochnebel" },
  28: { en: "Fog", fr: "Brouillard", de: "Nebel" },
  29: { en: "Sunny intervals, scattered showers", fr: "Éclaircies, averses éparses", de: "Sonnige Abschnitte, verbreitet Schauer" },
  30: { en: "Sunny intervals, scattered snow showers", fr: "Éclaircies, averses de neige éparses", de: "Sonnige Abschnitte, verbreitet Schneeschauer" },
  31: { en: "Sunny intervals, scattered sleet", fr: "Éclaircies, giboulées éparses", de: "Sonnige Abschnitte, verbreitet Schneeregen" },
  32: { en: "Sunny intervals, some showers", fr: "Éclaircies, quelques averses", de: "Sonnige Abschnitte, einige Schauer" },
  33: { en: "Brief sunny intervals, frequent rain", fr: "Brèves éclaircies, pluie fréquente", de: "Kurze sonnige Abschnitte, häufig Regen" },
  34: { en: "Brief sunny intervals, frequent snowfall", fr: "Brèves éclaircies, chutes de neige fréquentes", de: "Kurze sonnige Abschnitte, häufig Schneefall" },
  35: { en: "Overcast and dry", fr: "Couvert et sec", de: "Bedeckt und trocken" },
  36: { en: "Partly sunny, slightly stormy", fr: "Partiellement ensoleillé, légèrement orageux", de: "Teils sonnig, leicht gewittrig" },
  37: { en: "Partly sunny, stormy snow showers", fr: "Partiellement ensoleillé, averses de neige orageuses", de: "Teils sonnig, gewittrige Schneeschauer" },
  38: { en: "Overcast, thundery showers", fr: "Couvert, averses orageuses", de: "Bedeckt, gewittrige Schauer" },
  39: { en: "Overcast, thundery snow showers", fr: "Couvert, averses de neige orageuses", de: "Bedeckt, gewittrige Schneeschauer" },
  40: { en: "Very cloudy, slightly stormy", fr: "Très nuageux, légèrement orageux", de: "Stark bewölkt, leicht gewittrig" },
  41: { en: "Overcast, slightly stormy", fr: "Couvert, légèrement orageux", de: "Bedeckt, leicht gewittrig" },
  42: { en: "Very cloudy, thundery snow showers", fr: "Très nuageux, averses de neige orageuses", de: "Stark bewölkt, gewittrige Schneeschauer" }
}

// Night wording, listed only for the symbols whose daytime text names the sun.
// Everything else describes cloud and precipitation, which reads the same after
// dark, so those codes fall through to DAY_TEXT rather than being duplicated.
var NIGHT_TEXT = {
  1:  { en: "Clear", fr: "Ciel dégagé", de: "Klar" },
  2:  { en: "Slightly overcast", fr: "Légèrement nuageux", de: "Leicht bewölkt" },
  3:  { en: "Passing clouds", fr: "Passages nuageux", de: "Durchziehende Wolken" },
  6:  { en: "Clear spells, isolated showers", fr: "Éclaircies nocturnes, averses isolées", de: "Aufhellungen, einzelne Schauer" },
  7:  { en: "Clear spells, isolated sleet", fr: "Éclaircies nocturnes, giboulées isolées", de: "Aufhellungen, einzelne Schneeregenschauer" },
  8:  { en: "Clear spells, snow showers", fr: "Éclaircies nocturnes, averses de neige", de: "Aufhellungen, Schneeschauer" },
  12: { en: "Clear spells, chance of thunderstorms", fr: "Éclaircies nocturnes, risque d’orages", de: "Aufhellungen, Gewitterneigung" },
  13: { en: "Clear spells, possible thunderstorms", fr: "Éclaircies nocturnes, orages possibles", de: "Aufhellungen, mögliche Gewitter" },
  26: { en: "High cloud", fr: "Nuages élevés", de: "Hohe Bewölkung" },
  29: { en: "Clear spells, scattered showers", fr: "Éclaircies nocturnes, averses éparses", de: "Aufhellungen, verbreitet Schauer" },
  30: { en: "Clear spells, scattered snow showers", fr: "Éclaircies nocturnes, averses de neige éparses", de: "Aufhellungen, verbreitet Schneeschauer" },
  31: { en: "Clear spells, scattered sleet", fr: "Éclaircies nocturnes, giboulées éparses", de: "Aufhellungen, verbreitet Schneeregen" },
  32: { en: "Clear spells, some showers", fr: "Éclaircies nocturnes, quelques averses", de: "Aufhellungen, einige Schauer" },
  33: { en: "Brief clear spells, frequent rain", fr: "Brèves éclaircies, pluie fréquente", de: "Kurze Aufhellungen, häufig Regen" },
  34: { en: "Brief clear spells, frequent snowfall", fr: "Brèves éclaircies, chutes de neige fréquentes", de: "Kurze Aufhellungen, häufig Schneefall" },
  36: { en: "Slightly stormy", fr: "Légèrement orageux", de: "Leicht gewittrig" },
  37: { en: "Stormy snow showers", fr: "Averses de neige orageuses", de: "Gewittrige Schneeschauer" }
}

/**
 * Splits a MeteoSwiss symbol number into its base symbol and whether it is the
 * night variant. Returns null for anything outside the published ranges, so a
 * malformed or out-of-range value from the network can never index the tables.
 */
function parse(code) {
  var n = parseInt(String(code), 10)
  if (!isFinite(n)) return null
  if (n >= 1 && n <= 42) return { base: n, night: false }
  if (n >= 101 && n <= 142) return { base: n - 100, night: true }
  return null
}

function isNight(code) {
  var parsed = parse(code)
  return parsed !== null && parsed.night
}

/** Nerd Font glyph for a symbol number, or the "no data" glyph. */
function glyph(code) {
  var parsed = parse(code)
  if (parsed === null) return GLYPH_UNKNOWN
  var entry = GLYPHS[parsed.base]
  if (!entry) return GLYPH_UNKNOWN
  return (parsed.night && entry.length > 1) ? entry[1] : entry[0]
}

/** Human-readable situation for a symbol number in the given language. */
function describe(code, language) {
  var parsed = parse(code)
  if (parsed === null) return ""
  var lang = (language === "fr" || language === "de") ? language : "en"
  var entry = (parsed.night && NIGHT_TEXT[parsed.base]) || DAY_TEXT[parsed.base]
  return entry ? (entry[lang] || entry.en) : ""
}

if (typeof module !== "undefined") {
  module.exports = {
    GLYPH_UNKNOWN: GLYPH_UNKNOWN,
    parse: parse,
    isNight: isNight,
    glyph: glyph,
    describe: describe
  }
}

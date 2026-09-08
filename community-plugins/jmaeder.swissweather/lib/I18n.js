// Interface strings in the three languages the plugin offers.
//
// The panel language is a plugin setting, deliberately independent of the
// system locale: a machine running in en_US.UTF-8 in Lausanne should still be
// able to read its weather in French. `defaultLanguage()` seeds the setting
// from the locale on first run, and the user can change it from the panel.
//
// Dates and times use the Swiss conventions (DD.MM, 24-hour clock, comma-free
// numbers) in all three languages, because that is what the country uses
// regardless of which of its languages you are reading.

// The two warning categories are named as MeteoSwiss names them on its own
// hazard page — Intempéries / Dangers naturels, Unwetter / Naturgefahren, Bad
// weather / Natural hazards — so that a reader who has both open is looking at
// one vocabulary rather than two.
//
// The hazard names and the five danger levels are MeteoSwiss's own wording,
// taken from its "explanation of the danger levels" page in each of the three
// languages, so that a warning reads here exactly as it reads on the site.
var LANGUAGES = ["en", "fr", "de"]

var STRINGS = {
  en: {
    languageName: "English",
    favourites: "Favourites",
    searchPlaceholder: "Search a Swiss town",
    searchHint: "Type at least two letters",
    noResults: "No town matches",
    addFavourite: "Add to favourites",
    removeFavourite: "Remove from favourites",
    measured: "Measured",
    forecastLabel: "Forecast",
    station: "Station",
    away: "away",
    temperature: "Temperature",
    precipitation: "Precipitation",
    wind: "Wind",
    gust: "Gusts",
    sunshine: "Sunshine",
    humidity: "Humidity",
    pressure: "Pressure",
    tabToday: "Today",
    tabWeek: "Week",
    back: "Back",
    language: "Language",
    loading: "Loading…",
    noData: "No data",
    unreachable: "MeteoSwiss unreachable — showing last known values",
    neverLoaded: "MeteoSwiss unreachable",
    source: "Source: MeteoSwiss",
    uncertainty: "Band: 10–90 % forecast range",
    sunrise: "Sunrise",
    sunset: "Sunset",
    warnings: "Warnings",
    unitTemperature: "°C",
    unitPrecipitation: "mm",
    unitWind: "km/h",
    unitSunshine: "min",
    unitHumidity: "%",
    unitPressure: "hPa",
    unitDistance: "km",
    perHour: "/h",
    openData: "Open data",
    stationSilent: "station reporting no values",
    compass: ["N", "NE", "E", "SE", "S", "SW", "W", "NW"],
    hourSuffix: "h",
    tenMinuteInterval: "(10 min)",
    units: "Units",
    unitsMetric: "Metric",
    unitsImperial: "Imperial",
    unitTemperatureImperial: "°F",
    unitPrecipitationImperial: "in",
    unitWindImperial: "mph",
    unitDistanceImperial: "mi",
    unitAltitude: "m",
    unitAltitudeImperial: "ft",
    weatherWarnings: "Bad weather",
    naturalHazards: "Natural hazards",
    noWarnings: "No warnings in force",
    maps: "Maps",
    mapPrecipitation: "Precipitation",
    mapClouds: "Cloud cover",
    mapWind: "Wind",
    mapHazards: "Hazards",
    nearestWebcam: "Nearest weather cam",
    notifications: "Notify",
    help: "Keyboard",
    helpSearch: "Search for a town",
    helpFavourite: "Go to that favourite",
    helpChartTabs: "In the charts: today, the week",
    helpPanels: "Neighbouring Omarchy panel",
    helpBack: "Back, then close",
    helpKeys: "This list",
    summaryTitle: "Swiss Weather",
    warning: "Warning",
    dangerLevel: "Level",
    dangerLevels: ["No or low danger", "Moderate danger", "Considerable danger",
                   "High danger", "Very high danger"],
    warningFrom: "from",
    warningUntil: "until",
    hazards: {
      thunderstorm: "Thunderstorms", rain: "Rain", snow: "Snow",
      slipperyRoads: "Slippery roads", frost: "Frost", heat: "Heat", wind: "Wind",
      avalanche: "Avalanches", earthquake: "Earthquakes", forestFire: "Forest fire",
      flood: "Flood", drought: "Drought", massMovement: "Mass movements"
    },
    fullForecast: "Full forecast",
    weekdays: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"],
    locating: "Detecting your region…"
  },
  fr: {
    languageName: "Français",
    favourites: "Favoris",
    searchPlaceholder: "Rechercher une commune suisse",
    searchHint: "Saisissez au moins deux lettres",
    noResults: "Aucune commune trouvée",
    addFavourite: "Ajouter aux favoris",
    removeFavourite: "Retirer des favoris",
    measured: "Mesuré",
    forecastLabel: "Prévision",
    station: "Station",
    away: "de distance",
    temperature: "Température",
    precipitation: "Précipitations",
    wind: "Vent",
    gust: "Rafales",
    sunshine: "Ensoleillement",
    humidity: "Humidité",
    pressure: "Pression",
    tabToday: "Journée",
    tabWeek: "Semaine",
    back: "Retour",
    language: "Langue",
    loading: "Chargement…",
    noData: "Pas de données",
    unreachable: "MétéoSuisse injoignable — dernières valeurs connues",
    neverLoaded: "MétéoSuisse injoignable",
    source: "Source : MétéoSuisse",
    uncertainty: "Bande : plage de prévision 10–90 %",
    sunrise: "Lever",
    sunset: "Coucher",
    warnings: "Alertes",
    unitTemperature: "°C",
    unitPrecipitation: "mm",
    unitWind: "km/h",
    unitSunshine: "min",
    unitHumidity: "%",
    unitPressure: "hPa",
    unitDistance: "km",
    perHour: "/h",
    openData: "Données ouvertes",
    stationSilent: "station sans valeurs",
    compass: ["N", "NE", "E", "SE", "S", "SO", "O", "NO"],
    hourSuffix: "h",
    tenMinuteInterval: "(10 min)",
    units: "Unités",
    unitsMetric: "Métrique",
    unitsImperial: "Impérial",
    unitTemperatureImperial: "°F",
    unitPrecipitationImperial: "in",
    unitWindImperial: "mph",
    unitDistanceImperial: "mi",
    unitAltitude: "m",
    unitAltitudeImperial: "ft",
    weatherWarnings: "Intempéries",
    naturalHazards: "Dangers naturels",
    noWarnings: "Aucune alerte en cours",
    maps: "Cartes",
    mapPrecipitation: "Précipitations",
    mapClouds: "Nébulosité",
    mapWind: "Vent",
    mapHazards: "Dangers",
    nearestWebcam: "Caméra la plus proche",
    notifications: "Notifier",
    help: "Clavier",
    helpSearch: "Chercher une commune",
    helpFavourite: "Aller à ce favori",
    helpChartTabs: "Dans les graphiques : aujourd’hui, la semaine",
    helpPanels: "Panneau Omarchy voisin",
    helpBack: "Retour, puis fermer",
    helpKeys: "Cette liste",
    summaryTitle: "Météo Suisse",
    warning: "Alerte",
    dangerLevel: "Degré",
    dangerLevels: ["Aucun danger ou danger faible", "Danger limité", "Danger marqué",
                   "Fort danger", "Très fort danger"],
    warningFrom: "dès",
    warningUntil: "jusqu'au",
    hazards: {
      thunderstorm: "Orages", rain: "Pluie", snow: "Neige",
      slipperyRoads: "Chaussée glissante", frost: "Gel", heat: "Canicule", wind: "Vent",
      avalanche: "Avalanches", earthquake: "Séismes", forestFire: "Incendie de forêt",
      flood: "Crues", drought: "Sécheresse", massMovement: "Mouvements de terrain"
    },
    fullForecast: "Prévisions complètes",
    weekdays: ["Dim", "Lun", "Mar", "Mer", "Jeu", "Ven", "Sam"],
    locating: "Détection de votre région…"
  },
  de: {
    languageName: "Deutsch",
    favourites: "Favoriten",
    searchPlaceholder: "Schweizer Ort suchen",
    searchHint: "Mindestens zwei Buchstaben eingeben",
    noResults: "Kein Ort gefunden",
    addFavourite: "Zu Favoriten hinzufügen",
    removeFavourite: "Aus Favoriten entfernen",
    measured: "Gemessen",
    forecastLabel: "Prognose",
    station: "Station",
    away: "entfernt",
    temperature: "Temperatur",
    precipitation: "Niederschlag",
    wind: "Wind",
    gust: "Böen",
    sunshine: "Sonnenschein",
    humidity: "Luftfeuchtigkeit",
    pressure: "Luftdruck",
    tabToday: "Tag",
    tabWeek: "Woche",
    back: "Zurück",
    language: "Sprache",
    loading: "Lädt…",
    noData: "Keine Daten",
    unreachable: "MeteoSchweiz nicht erreichbar — letzte bekannte Werte",
    neverLoaded: "MeteoSchweiz nicht erreichbar",
    source: "Quelle: MeteoSchweiz",
    uncertainty: "Band: Prognosebereich 10–90 %",
    sunrise: "Aufgang",
    sunset: "Untergang",
    warnings: "Warnungen",
    unitTemperature: "°C",
    unitPrecipitation: "mm",
    unitWind: "km/h",
    unitSunshine: "Min",
    unitHumidity: "%",
    unitPressure: "hPa",
    unitDistance: "km",
    perHour: "/h",
    openData: "Open Data",
    stationSilent: "Station meldet keine Werte",
    compass: ["N", "NO", "O", "SO", "S", "SW", "W", "NW"],
    hourSuffix: "Uhr",
    tenMinuteInterval: "(10 Min)",
    units: "Einheiten",
    unitsMetric: "Metrisch",
    unitsImperial: "Imperial",
    unitTemperatureImperial: "°F",
    unitPrecipitationImperial: "in",
    unitWindImperial: "mph",
    unitDistanceImperial: "mi",
    unitAltitude: "m",
    unitAltitudeImperial: "ft",
    weatherWarnings: "Unwetter",
    naturalHazards: "Naturgefahren",
    noWarnings: "Keine Warnungen in Kraft",
    maps: "Karten",
    mapPrecipitation: "Niederschlag",
    mapClouds: "Bewölkung",
    mapWind: "Wind",
    mapHazards: "Gefahren",
    nearestWebcam: "Nächste Wetterkamera",
    notifications: "Melden",
    help: "Tastatur",
    helpSearch: "Ort suchen",
    helpFavourite: "Zu diesem Favoriten",
    helpChartTabs: "In den Diagrammen: heute, die Woche",
    helpPanels: "Benachbartes Omarchy-Panel",
    helpBack: "Zurück, dann schliessen",
    helpKeys: "Diese Liste",
    summaryTitle: "Schweizer Wetter",
    warning: "Warnung",
    dangerLevel: "Stufe",
    dangerLevels: ["Keine oder geringe Gefahr", "Mässige Gefahr", "Erhebliche Gefahr",
                   "Grosse Gefahr", "Sehr grosse Gefahr"],
    warningFrom: "ab",
    warningUntil: "bis",
    hazards: {
      thunderstorm: "Gewitter", rain: "Regen", snow: "Schnee",
      slipperyRoads: "Strassenglätte", frost: "Frost", heat: "Hitze", wind: "Wind",
      avalanche: "Lawinen", earthquake: "Erdbeben", forestFire: "Waldbrand",
      flood: "Hochwasser", drought: "Trockenheit", massMovement: "Massenbewegungen"
    },
    fullForecast: "Vollständige Prognose",
    weekdays: ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"],
    locating: "Region wird ermittelt…"
  }
}

function normalize(language) {
  var lang = String(language || "").toLowerCase().substring(0, 2)
  return LANGUAGES.indexOf(lang) !== -1 ? lang : "en"
}

/** Seeds the language setting on first run; the user's choice wins after that. */
function defaultLanguage(localeName) {
  return normalize(String(localeName || "").replace(/[_.-].*$/, ""))
}

/**
 * Looks a string up, falling back to English and then to the key itself. A
 * missing key renders as its own name rather than as an empty box, which makes
 * a translation gap obvious in a screenshot instead of invisible.
 */
function t(language, key) {
  var table = STRINGS[normalize(language)] || STRINGS.en
  var value = table[key]
  if (value === undefined) value = STRINGS.en[key]
  return value === undefined ? String(key) : value
}

/**
 * Compass point for a bearing in degrees, in the panel language.
 *
 * The abbreviations are not shared across languages: west is W in English and
 * German but O (ouest) in French, while east is E in English and French but O
 * (Ost) in German. Reusing one table would label a French panel's easterly
 * wind as westerly.
 */
function compass(language, degrees) {
  var value = Number(degrees)
  if (degrees === null || degrees === undefined || !isFinite(value)) return ""
  var points = t(language, "compass")
  return points[Math.round(((value % 360) + 360) % 360 / 45) % 8]
}

/**
 * The name of a hazard, in the panel language.
 *
 * Falls back to the plain word "warning" rather than to the key: a warning
 * whose type the plugin has not confirmed still has a level and a text worth
 * reading, and inventing a name for it would be worse than not naming it.
 */
function hazardName(language, key) {
  var names = t(language, "hazards")
  var name = names && key ? names[key] : ""
  return name || t(language, "warning")
}

/** The meaning of a danger level 1-5, in the panel language, or "". */
function dangerLevelName(language, level) {
  var n = Number(level)
  if (!isFinite(n) || n < 1 || n > 5) return ""
  return t(language, "dangerLevels")[Math.round(n) - 1] || ""
}

/** Short weekday name for a JS Date, in the panel language. */
function weekday(language, date) {
  var names = t(language, "weekdays")
  if (!date || isNaN(date.getTime())) return ""
  return names[date.getDay()] || ""
}

function languageOptions() {
  var options = []
  for (var i = 0; i < LANGUAGES.length; i++) {
    options.push({ value: LANGUAGES[i], label: STRINGS[LANGUAGES[i]].languageName })
  }
  return options
}

if (typeof module !== "undefined") {
  module.exports = {
    LANGUAGES: LANGUAGES,
    STRINGS: STRINGS,
    normalize: normalize,
    defaultLanguage: defaultLanguage,
    t: t,
    weekday: weekday,
    hazardName: hazardName,
    dangerLevelName: dangerLevelName,
    compass: compass,
    languageOptions: languageOptions
  }
}

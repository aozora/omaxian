# Where the data comes from

[← README](../README.md)

Everything on screen is MeteoSwiss data.

| What | Source |
|---|---|
| Current measurements | `data.geo.admin.ch` — [`VQHA80.csv`](https://data.geo.admin.ch/ch.meteoschweiz.messwerte-aktuell/VQHA80.csv), the latest 10-minute values for all ~160 SMN stations |
| Forecast, bands, symbols, warnings | The MeteoSwiss forecast service used by the official MeteoSwiss app |
| Weather-cam list | [`ch.meteoschweiz.messnetz-webcams`](https://data.geo.admin.ch/ch.meteoschweiz.messnetz-webcams/) on `data.geo.admin.ch`, shipped in `data/webcams.csv` |
| Town and station indexes | [MeteoSwiss Open Data](https://opendatadocs.meteoswiss.ch/) point and station metadata, shipped in `data/` |
| Page links | the fr/de/en sitemaps of meteoswiss.admin.ch, shipped in `data/forecast-pages.csv` |
| Hazard names, danger levels | the wording on MeteoSwiss's [explanation of the danger levels](https://www.meteoswiss.admin.ch/weather/hazards/explanation-of-the-danger-levels.html), in each of the three languages |
| Canton of each town | swisstopo's official register of localities, on the same `data.geo.admin.ch` host, shipped in `data/places.csv` |

The canton is the one field that is not MeteoSwiss's: it is in neither the
point metadata nor the town's own page on meteoswiss.admin.ch, and it is
administrative geography rather than weather, so it comes from the federal
register that defines it — swisstopo's *Amtliches Ortschaftenverzeichnis*, on
the `data.geo.admin.ch` host the weather data already comes from. It is baked
into the shipped index at build time, so the plugin gains no host and makes no
request for it.

MeteoSwiss Open Data may be used freely provided the source is cited, which
the panel does in its footer. The MeteoSwiss weather *graphics* are proprietary
and are **not** used here: the plugin takes only the documented symbol numbers
and draws its own Nerd Font glyphs.

Two notes on the forecast service. It is the backend of the official
MeteoSwiss app rather than a documented Open Data endpoint, so it can change
without notice; `lib/Net.js` isolates it behind one function so it can be
repointed. MeteoSwiss has said individual API queries over Open Data are
planned, and when they arrive this plugin should move to them. The Open Data
alternative today is a set of ~32 MB files per parameter, which is not
something a bar widget should be downloading every quarter of an hour.

## Maps and weather cams

Both are links out to MeteoSwiss, deliberately.

**The maps.** MeteoSwiss's site no longer serves its radar and nowcast
animations as pictures: a frame is a JSON file of chain-coded contours on a
1 km LV95 grid, in an encoding that is documented nowhere. Some products —
cloud cover, satellite — are still PNG or JPEG and could be drawn here, but
precipitation, the one worth watching, is not among them. Decoding a private
format would give a map that breaks silently the day MeteoSwiss changes it,
and drawing every other layer except the rain would be an odd plugin. The
radar in Open Data (`ch.meteoschweiz.ogd-radar-precip`) is HDF5, which is not
something to decode in a bar widget either. So the panel opens the real page,
in your language, where the animation controls are.

**The weather cams.** The station list is MeteoSwiss Open Data on
`data.geo.admin.ch` and is shipped in `data/webcams.csv`, so finding the
nearest cam is done offline like everything else here. The pictures are not:
MeteoSwiss has the cams filmed by a commercial provider and serves the images
from that provider's hosts, behind a redirect. Fetching one every quarter of
an hour would tell a third party where you live, which is not a trade this
plugin makes for a picture of a mountain. The panel names the nearest cam, its
distance, and opens MeteoSwiss's page for it.

## Refreshing the shipped indexes

`data/places.csv` (4071 postal-code centres, with their canton),
`data/stations.csv` (158 SMN stations), `data/webcams.csv` (35 weather cams)
and `data/forecast-pages.csv` (3191 page slugs) are generated from federal
open data. To refresh them:

```bash
tools/build-data.sh
```

Each index records the date and the SHA-256 of the upstream file it came from.

A note on the canton column. A postal code can straddle a cantonal border —
169 of them do — and the register lists one row per municipality with the
share of the code's addresses it holds. Engelberg 6390 is 93 % Obwalden, 5 %
Nidwalden and 2 % Uri; taking rows in file order would file it under Uri, so
the share decides. The thirteen Liechtenstein towns MeteoSwiss also forecasts
are in no canton and get none.

`forecast-pages.csv` deserves a note. MeteoSwiss addresses a town's forecast
page by that town's name **in the page's own language** — Genève is `/genf/` in
German and `/geneva/` in English, Martigny is `/martinach/` in German — and no
rule derives that from the town's own name. Guessing gets about 80 % of links
right, or 99 % once German umlauts are transliterated the German way; neither
is good enough for a link. So the slugs are read from the site's three language
sitemaps, three requests in total, and the plugin looks them up instead of
computing them. A town with no page — three postal codes address PO boxes —
simply shows no link.

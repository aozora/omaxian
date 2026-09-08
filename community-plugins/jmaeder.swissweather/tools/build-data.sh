#!/usr/bin/env bash
# Regenerate data/places.csv and data/stations.csv from MeteoSwiss Open Data.
#
# The plugin ships these two indexes so that searching for a Swiss town never
# leaves the machine: no geocoding request, no user-typed string in any URL.
# That removes the whole SSRF / query-injection class from the search path and
# keeps the search working offline. The trade-off is staleness, so this script
# exists to make regeneration reproducible and auditable — run it, review the
# diff, commit.
#
# Source: MeteoSwiss (https://opendatadocs.meteoswiss.ch/), used under the
# MeteoSwiss Open Data terms of use.
#
# Usage: tools/build-data.sh
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="$repo_root/data"
work_dir="$(mktemp -d)"
trap 'rm -rf -- "$work_dir"' EXIT

points_url="https://data.geo.admin.ch/ch.meteoschweiz.ogd-local-forecasting/ogd-local-forecasting_meta_point.csv"
stations_url="https://data.geo.admin.ch/ch.meteoschweiz.ogd-smn/ogd-smn_meta_stations.csv"

# The canton of each postal code, from the official register of localities.
#
# This is the one field in the index that MeteoSwiss does not publish: the
# canton is in neither the point metadata nor the town's own page on
# meteoswiss.admin.ch. It is also not weather data — it is administrative
# geography — so it is taken from the federal register that defines it,
# swisstopo's "Amtliches Ortschaftenverzeichnis", on the same
# data.geo.admin.ch host the weather data already comes from. Baked in here,
# at build time: the plugin gains no new host and makes no new request.
localities_url="https://data.geo.admin.ch/ch.swisstopo-vd.ortschaftenverzeichnis_plz/ortschaftenverzeichnis_plz/ortschaftenverzeichnis_plz_2056.csv.zip"

# The 35 MeteoSwiss weather cams, so the panel can name the nearest one and
# link to its page. Only the station list is taken: the pictures themselves are
# served by a commercial third party, which the plugin deliberately never
# contacts — see the README.
webcams_url="https://data.geo.admin.ch/ch.meteoschweiz.messnetz-webcams/ch.meteoschweiz.messnetz-webcams_en.csv"

# The three language sitemaps. They are the authoritative list of MeteoSwiss's
# local-forecast pages, which is what makes data/forecast-pages.csv exact
# rather than guessed: the page slug is the town's name *in the page's
# language* — Genève is /genf/ in German and /geneva/ in English — and no rule
# derives that from the town's own name. Three requests here replace twelve
# thousand probes, and mean the plugin never has to guess a URL.
sitemap_fr_url="https://www.meteosuisse.admin.ch/sitemap.xml"
sitemap_de_url="https://www.meteoschweiz.admin.ch/sitemap.xml"
sitemap_en_url="https://www.meteoswiss.admin.ch/sitemap.xml"

fetch() {
  # No -L: a redirect off the host named in the URL is never legitimate here,
  # and following one silently would defeat the point of pinning the host.
  curl --proto '=https' --tlsv1.2 --fail --silent --show-error \
    --max-time 120 --max-filesize 20000000 \
    --output "$2" -- "$1"
}

echo "Fetching point metadata…"
fetch "$points_url" "$work_dir/points.csv"
echo "Fetching station metadata…"
fetch "$stations_url" "$work_dir/stations.csv"
echo "Fetching weather-cam metadata…"
fetch "$webcams_url" "$work_dir/webcams.csv"
echo "Fetching the register of localities (cantons)…"
fetch "$localities_url" "$work_dir/localities.zip"
unzip -q -o -j "$work_dir/localities.zip" -d "$work_dir/localities"
echo "Fetching page sitemaps (fr, de, en)…"
fetch "$sitemap_fr_url" "$work_dir/sitemap_fr.xml"
fetch "$sitemap_de_url" "$work_dir/sitemap_de.xml"
fetch "$sitemap_en_url" "$work_dir/sitemap_en.xml"

mkdir -p "$out_dir"

python3 - "$work_dir" "$out_dir" <<'PY'
import csv, glob, hashlib, re, sys, unicodedata
from datetime import datetime, timezone

work, out = sys.argv[1], sys.argv[2]


def digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def clean(value):
    # The index is read back by a hand-rolled CSV splitter in QML, so a stray
    # ';' or newline in a field would silently shift every later column.
    # Strip the separators instead of quoting them.
    text = unicodedata.normalize("NFC", (value or "").strip())
    return "".join(" " if ch in ";\r\n\t" else ch for ch in text).strip()


stamp = datetime.now(timezone.utc).strftime("%Y-%m-%d")

# ---- places: postal-code centres -------------------------------------------
#
# Only point_type_id == 2 is kept. Those are the only points whose id the
# forecast service resolves; station (1) and mountain-POI (3) ids are rejected
# by it, so shipping them would just produce dead search results.
with open(f"{work}/points.csv", encoding="latin-1", newline="") as fh:
    points = list(csv.DictReader(fh, delimiter=";"))

# Canton per postal code, from the register of localities. A postal code can
# straddle a cantonal border — 169 of them do — so the name is used to pick
# the right side, and the code's own canton is the fallback only when it is
# unambiguous. Seven Onsernone-valley codes are absent from the register
# (their localities were merged away) and simply get no canton: the header
# then shows the town without one, which is better than showing a guess.
localities = glob.glob(f"{work}/localities/*.csv")
if len(localities) != 1:
    raise SystemExit(f"expected one locality CSV, found {localities}")

# The register splits a locality that straddles a border into one row per
# municipality, each with the share of the locality's addresses it holds:
# Engelberg 6390 is 93 % Obwalden, 5 % Nidwalden, 2 % Uri. Taking rows in file
# order would have called Engelberg a Uri town. The share is the tie-breaker.
canton_share = {}
canton_share_by_name = {}


def keep(table, key, canton, share):
    best = table.get(key)
    if best is None or share > best[1]:
        table[key] = (canton, share)


with open(localities[0], encoding="utf-8-sig", newline="") as fh:
    for row in csv.DictReader(fh, delimiter=";"):
        plz = clean(row.get("PLZ4"))
        canton = clean(row.get("Kantonskürzel")).upper()
        name = clean(row.get("Ortschaftsname"))
        if not (plz.isdigit() and len(plz) == 4 and len(canton) == 2 and canton.isalpha()):
            continue
        try:
            share = float(clean(row.get("Adressenanteil")).rstrip("%").strip())
        except ValueError:
            share = 0.0
        keep(canton_share, plz, canton, share)
        if name:
            keep(canton_share_by_name, (plz, name.casefold()), canton, share)


def canton_for(plz, name):
    exact = canton_share_by_name.get((plz, name.casefold()))
    if exact:
        return exact[0]
    best = canton_share.get(plz)
    return best[0] if best else ""


places = []
missing_canton = 0
for row in points:
    if row.get("point_type_id") != "2":
        continue
    point_id = clean(row.get("point_id"))
    plz = clean(row.get("postal_code"))
    name = clean(row.get("point_name"))
    lat = clean(row.get("point_coordinates_wgs84_lat"))
    lon = clean(row.get("point_coordinates_wgs84_lon"))
    alt = clean(row.get("point_height_masl"))
    if not (point_id.isdigit() and len(point_id) == 6 and plz.isdigit() and name):
        continue
    try:
        lat_f, lon_f, alt_f = float(lat), float(lon), float(alt or 0)
    except ValueError:
        continue
    # Switzerland's bounding box, generously padded. A point outside it means
    # the upstream row is corrupt; dropping it keeps the nearest-station search
    # from being dragged off by a bogus coordinate.
    if not (45.5 <= lat_f <= 48.0 and 5.5 <= lon_f <= 11.0):
        continue
    canton = canton_for(plz, name)
    if not canton:
        missing_canton += 1
    places.append((point_id, plz, name, f"{lat_f:.4f}", f"{lon_f:.4f}", str(round(alt_f)), canton))

places.sort(key=lambda r: (r[2].casefold(), r[1]))

with open(f"{out}/places.csv", "w", encoding="utf-8", newline="\n") as fh:
    fh.write(f"# Swiss postal-code centres. Source: MeteoSwiss. Generated {stamp}.\n")
    fh.write(f"# from ogd-local-forecasting_meta_point.csv sha256={digest(f'{work}/points.csv')}\n")
    fh.write("# canton from swisstopo ortschaftenverzeichnis_plz "
             f"sha256={digest(f'{work}/localities.zip')}\n")
    fh.write("point_id;plz;name;lat;lon;alt;canton\n")
    for row in places:
        fh.write(";".join(row) + "\n")

# ---- stations: SMN automatic weather stations -------------------------------
with open(f"{work}/stations.csv", encoding="latin-1", newline="") as fh:
    stations = list(csv.DictReader(fh, delimiter=";"))

kept = []
for row in stations:
    abbr = clean(row.get("station_abbr")).upper()
    name = clean(row.get("station_name"))
    lat = clean(row.get("station_coordinates_wgs84_lat"))
    lon = clean(row.get("station_coordinates_wgs84_lon"))
    alt = clean(row.get("station_height_masl"))
    if not (abbr.isalnum() and 2 <= len(abbr) <= 5 and name):
        continue
    try:
        lat_f, lon_f, alt_f = float(lat), float(lon), float(alt or 0)
    except ValueError:
        continue
    if not (45.5 <= lat_f <= 48.0 and 5.5 <= lon_f <= 11.0):
        continue
    kept.append((abbr, name, f"{lat_f:.4f}", f"{lon_f:.4f}", str(round(alt_f))))

kept.sort()

with open(f"{out}/stations.csv", "w", encoding="utf-8", newline="\n") as fh:
    fh.write(f"# SMN automatic weather stations. Source: MeteoSwiss. Generated {stamp}.\n")
    fh.write(f"# from ogd-smn_meta_stations.csv sha256={digest(f'{work}/stations.csv')}\n")
    fh.write("abbr;name;lat;lon;alt\n")
    for row in kept:
        fh.write(";".join(row) + "\n")

# ---- weather cams -----------------------------------------------------------
#
# Latin-1 and quoted, unlike the OGD files above, so it is read with the csv
# module and written out in the plain form the QML splitter expects.
with open(f"{work}/webcams.csv", encoding="latin-1", newline="") as fh:
    cams = list(csv.DictReader(fh, delimiter=";"))

webcams = []
for row in cams:
    abbr = clean(row.get("Abbr.")).upper()
    name = clean(row.get("Station"))
    lat = clean(row.get("Latitude"))
    lon = clean(row.get("Longitude"))
    alt = clean(row.get("Height Weather Cam m a. sea level"))
    if not (abbr.isalnum() and 2 <= len(abbr) <= 5 and name):
        continue
    try:
        lat_f, lon_f, alt_f = float(lat), float(lon), float(alt or 0)
    except ValueError:
        continue
    if not (45.5 <= lat_f <= 48.0 and 5.5 <= lon_f <= 11.0):
        continue
    webcams.append((abbr, name, f"{lat_f:.4f}", f"{lon_f:.4f}", str(round(alt_f))))

webcams.sort()

with open(f"{out}/webcams.csv", "w", encoding="utf-8", newline="\n") as fh:
    fh.write(f"# MeteoSwiss weather cams. Source: MeteoSwiss. Generated {stamp}.\n")
    fh.write(f"# from ch.meteoschweiz.messnetz-webcams_en.csv sha256={digest(f'{work}/webcams.csv')}\n")
    fh.write("abbr;name;lat;lon;alt\n")
    for row in webcams:
        fh.write(";".join(row) + "\n")

# ---- forecast pages: postal code -> page slug per language ------------------
#
# Stored as `plz;de;fr;en` with the French and English columns left empty when
# they match the German one — which is the case for all but a small minority,
# so the file stays a fraction of the size of writing every slug three times.
PAGE_PATTERNS = {
    "de": re.compile(r"<loc>https://[^<]*/lokalprognose/([^/<]+)/(\d{4})\.html</loc>"),
    "fr": re.compile(r"<loc>https://[^<]*/previsions-locales/([^/<]+)/(\d{4})\.html</loc>"),
    "en": re.compile(r"<loc>https://[^<]*/local-forecasts/([^/<]+)/(\d{4})\.html</loc>"),
}

pages = {}
for lang, pattern in PAGE_PATTERNS.items():
    with open(f"{work}/sitemap_{lang}.xml", encoding="utf-8") as fh:
        for match in pattern.finditer(fh.read()):
            slug, plz = match.group(1), match.group(2)
            # The slug goes straight into a URL, so anything that is not a
            # plain lowercase path segment is dropped rather than escaped.
            if not re.fullmatch(r"[a-z0-9-]+", slug):
                continue
            pages.setdefault(plz, {})[lang] = slug

wanted = {row[1] for row in places}
rows = []
for plz in sorted(p for p in pages if p in wanted):
    entry = pages[plz]
    if len(entry) != 3:
        continue  # a page missing in any language would give a dead link
    base = entry["de"]
    rows.append((plz, base,
                 "" if entry["fr"] == base else entry["fr"],
                 "" if entry["en"] == base else entry["en"]))

with open(f"{out}/forecast-pages.csv", "w", encoding="utf-8", newline="\n") as fh:
    fh.write(f"# MeteoSwiss local-forecast page slugs. Source: MeteoSwiss. Generated {stamp}.\n")
    fh.write("# from the fr/de/en sitemaps. Empty fr/en columns mean the German slug applies.\n")
    fh.write("plz;de;fr;en\n")
    for row in rows:
        fh.write(";".join(row) + "\n")

localised = sum(1 for r in rows if r[2] or r[3])
missing_pages = len(wanted) - len(rows)

print(f"places.csv:   {len(places)} postal-code centres "
      f"({missing_canton} without a canton)")
print(f"stations.csv: {len(kept)} stations")
print(f"webcams.csv:  {len(webcams)} weather cams")
print(f"forecast-pages.csv: {len(rows)} postal codes "
      f"({localised} with a language-specific slug, {missing_pages} without a page)")
PY

echo "Done. Review the diff before committing."

#!/usr/bin/env bash
# Rebuilds the bundled map packs (Trip/Resources/MapPacks/*.json) from Natural Earth.
# Requirements: curl, node (npx), python3. Natural Earth data is public domain.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
CACHE="$HERE/.cache"
OUT="$ROOT/Trip/Resources/MapPacks"
NE="https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson"
MAPSHAPER="npx -y mapshaper@0.8.10"

mkdir -p "$CACHE" "$OUT"

fetch() { # url file
  if [[ ! -s "$CACHE/$2" ]]; then
    echo "↓ $2"
    curl -sSL --fail -o "$CACHE/$2" "$1"
  fi
}

fetch "$NE/ne_50m_admin_0_countries.geojson" countries50.geojson
fetch "$NE/ne_10m_admin_1_states_provinces.geojson" admin1_10m.geojson

echo "• Simplifying Turkey provinces"
$MAPSHAPER "$CACHE/admin1_10m.geojson" \
  -filter "adm0_a3 === 'TUR'" \
  -filter-fields iso_3166_2,latitude,longitude \
  -simplify 45% keep-shapes \
  -clean \
  -o "$CACHE/turkey.simplified.geojson" precision=0.0005 force

echo "• Simplifying world countries"
$MAPSHAPER "$CACHE/countries50.geojson" \
  -filter "CONTINENT !== 'Antarctica'" \
  -filter-fields ADM0_A3,ISO_A3_EH,NAME,NAME_TR,CONTINENT,REGION_UN,SUBREGION,TYPE,LABEL_X,LABEL_Y \
  -simplify 25% keep-shapes \
  -clean \
  -o "$CACHE/world.simplified.geojson" precision=0.005 force

echo "• Packing"
python3 -I "$HERE/pack.py" \
  --turkey "$CACHE/turkey.simplified.geojson" \
  --provinces "$HERE/tr_provinces.csv" \
  --world "$CACHE/world.simplified.geojson" \
  --out "$OUT"

ls -lh "$OUT"

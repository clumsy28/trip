#!/usr/bin/env python3
"""Converts simplified Natural Earth GeoJSON into Trip's compact map-pack format.

Output schema (one JSON file per pack):
{
  "id": "turkey", "name": "Türkiye", "version": 1,
  "projection": "mercator" | "equalEarth",
  "parentRegionID": "TUR" | null,          # world region this pack subdivides
  "groupTitle": "Bölge" | "Kıta",
  "unitName": "il" | "ülke",               # noun used in "81 ilden 23 il gezildi"
  "groups": [...],                         # display order of groups
  "regions": [{
     "id": "TR-34", "name": "İstanbul", "group": "Marmara",
     "countsTowardTotal": true, "areaKm2": 5461.2,
     "label": [lon, lat], "bbox": [minLon, minLat, maxLon, maxLat],
     "polygons": [[ring, hole, ...], ...]   # ring = flat [lon, lat, lon, lat, ...]
  }]
}
Standard library only.
"""
import argparse
import csv
import json
import math
import os
import sys

EARTH_RADIUS_KM = 6371.0088

TR_REGIONS = [
    "Marmara", "Ege", "Akdeniz", "İç Anadolu",
    "Karadeniz", "Doğu Anadolu", "Güneydoğu Anadolu",
]

CONTINENTS_TR = {
    "Europe": "Avrupa",
    "Asia": "Asya",
    "Africa": "Afrika",
    "North America": "Kuzey Amerika",
    "South America": "Güney Amerika",
    "Oceania": "Okyanusya",
    "Seven seas (open ocean)": "Okyanus Adaları",
    "Americas": None,  # resolved via SUBREGION
}
CONTINENT_ORDER = ["Avrupa", "Asya", "Afrika", "Kuzey Amerika", "Güney Amerika", "Okyanusya", "Okyanus Adaları"]

# 193 UN member states + 2 observer states (Vatican, Palestine): the denominator of "world %".
UN_MEMBERS = """
AFG ALB DZA AND AGO ATG ARG ARM AUS AUT AZE BHS BHR BGD BRB BLR BEL BLZ BEN BTN BOL BIH BWA BRA
BRN BGR BFA BDI CPV KHM CMR CAN CAF TCD CHL CHN COL COM COG COD CRI CIV HRV CUB CYP CZE DNK DJI
DMA DOM ECU EGY SLV GNQ ERI EST SWZ ETH FJI FIN FRA GAB GMB GEO DEU GHA GRC GRD GTM GIN GNB GUY
HTI HND HUN ISL IND IDN IRN IRQ IRL ISR ITA JAM JPN JOR KAZ KEN KIR PRK KOR KWT KGZ LAO LVA LBN
LSO LBR LBY LIE LTU LUX MDG MWI MYS MDV MLI MLT MHL MRT MUS MEX FSM MDA MCO MNG MNE MAR MOZ MMR
NAM NRU NPL NLD NZL NIC NER NGA MKD NOR OMN PAK PLW PAN PNG PRY PER PHL POL PRT QAT ROU RUS RWA
KNA LCA VCT WSM SMR STP SAU SEN SRB SYC SLE SGP SVK SVN SLB SOM ZAF SSD ESP LKA SDN SUR SWE CHE
SYR TJK TZA THA TLS TGO TON TTO TUN TUR TKM TUV UGA UKR ARE GBR USA URY UZB VUT VEN VNM YEM ZMB ZWE
""".split()
UN_OBSERVERS = ["VAT", "PSE"]


def fail(msg):
    print(f"✗ {msg}", file=sys.stderr)
    sys.exit(1)


def ring_area_km2(ring):
    """Spherical excess approximation of a lon/lat ring's area (absolute)."""
    if len(ring) < 3:
        return 0.0
    total = 0.0
    for i in range(len(ring)):
        lon1, lat1 = ring[i]
        lon2, lat2 = ring[(i + 1) % len(ring)]
        total += math.radians(lon2 - lon1) * (2 + math.sin(math.radians(lat1)) + math.sin(math.radians(lat2)))
    return abs(total * EARTH_RADIUS_KM ** 2 / 2.0)


def polygons_of(geometry):
    t = geometry["type"]
    if t == "Polygon":
        return [geometry["coordinates"]]
    if t == "MultiPolygon":
        return geometry["coordinates"]
    fail(f"unsupported geometry {t}")


def round_ring(ring, ndigits):
    flat = []
    prev = None
    for lon, lat in ring:
        p = (round(lon, ndigits), round(lat, ndigits))
        if p != prev:
            flat.extend(p)
            prev = p
    # drop explicit closing point; the renderer closes rings itself
    if len(flat) >= 4 and flat[0] == flat[-2] and flat[1] == flat[-1]:
        flat = flat[:-2]
    return flat


def build_region(rid, name, group, counts, geometry, label, ndigits):
    polys = polygons_of(geometry)
    area = 0.0
    min_lon = min_lat = math.inf
    max_lon = max_lat = -math.inf
    out_polys = []
    for poly in polys:
        rings = []
        for i, ring in enumerate(poly):
            a = ring_area_km2(ring)
            area += a if i == 0 else -a
            for lon, lat in ring:
                min_lon, max_lon = min(min_lon, lon), max(max_lon, lon)
                min_lat, max_lat = min(min_lat, lat), max(max_lat, lat)
            flat = round_ring(ring, ndigits)
            if len(flat) >= 6:
                rings.append(flat)
        if rings:
            out_polys.append(rings)
    if not out_polys:
        fail(f"{rid} has no polygons left after simplification")
    if label is None or not (min_lon <= label[0] <= max_lon and min_lat <= label[1] <= max_lat):
        label = [(min_lon + max_lon) / 2, (min_lat + max_lat) / 2]
    return {
        "id": rid,
        "name": name,
        "group": group,
        "countsTowardTotal": counts,
        "areaKm2": round(area, 1),
        "label": [round(label[0], 3), round(label[1], 3)],
        "bbox": [round(min_lon, 4), round(min_lat, 4), round(max_lon, 4), round(max_lat, 4)],
        "polygons": out_polys,
    }


def pack_turkey(path, provinces_csv):
    with open(provinces_csv, encoding="utf-8") as f:
        provinces = {row["plate"]: row for row in csv.DictReader(f)}
    if len(provinces) != 81:
        fail(f"tr_provinces.csv must have 81 rows, has {len(provinces)}")
    data = json.load(open(path, encoding="utf-8"))
    regions = []
    seen = set()
    for feat in data["features"]:
        props = feat["properties"]
        code = props["iso_3166_2"]  # TR-34; the number is the license-plate code
        plate = code.split("-")[1]
        if plate not in provinces:
            fail(f"unknown province {code}")
        row = provinces[plate]
        if row["region"] not in TR_REGIONS:
            fail(f"unknown region {row['region']} for {code}")
        seen.add(plate)
        label = [props.get("longitude"), props.get("latitude")]
        label = label if None not in label else None
        regions.append(build_region(code, row["name"], row["region"], True, feat["geometry"], label, 4))
    if len(seen) != 81:
        fail(f"expected 81 provinces, got {len(seen)}")
    regions.sort(key=lambda r: r["id"])
    return {
        "id": "turkey",
        "name": "Türkiye",
        "version": 1,
        "projection": "mercator",
        "parentRegionID": "TUR",
        "groupTitle": "Bölge",
        "unitName": "il",
        "groups": TR_REGIONS,
        "regions": regions,
    }


def pack_world(path):
    data = json.load(open(path, encoding="utf-8"))
    regions = []
    ids = set()
    counted = set()
    allowed = set(UN_MEMBERS) | set(UN_OBSERVERS)
    if len(UN_MEMBERS) != 193 or len(set(UN_MEMBERS)) != 193:
        fail(f"UN member list must have 193 unique codes, has {len(set(UN_MEMBERS))}")
    for feat in data["features"]:
        p = feat["properties"]
        iso3 = p.get("ISO_A3_EH")
        rid = iso3 if iso3 and iso3 != "-99" and iso3 not in ids else p["ADM0_A3"]
        if rid in ids:
            fail(f"duplicate world id {rid} ({p['NAME']})")
        ids.add(rid)
        raw_continent = p["CONTINENT"]
        if raw_continent.startswith("Seven seas") and p.get("REGION_UN") in CONTINENTS_TR:
            raw_continent = p["REGION_UN"]  # e.g. Maldives → Asia, Mauritius → Africa
        if raw_continent == "Americas":
            raw_continent = "South America" if p.get("SUBREGION") == "South America" else "North America"
        continent = CONTINENTS_TR.get(raw_continent)
        if continent is None:
            fail(f"unknown continent {p['CONTINENT']}")
        counts = rid in allowed and rid not in counted
        if counts:
            counted.add(rid)
        name = p.get("NAME_TR") or p["NAME"]
        label = [p.get("LABEL_X"), p.get("LABEL_Y")]
        label = label if None not in label else None
        regions.append(build_region(rid, name, continent, counts, feat["geometry"], label, 3))
    missing = sorted(allowed - counted)
    if missing:
        print(f"! UN states missing from map data (not counted): {' '.join(missing)}")
    if "TUR" not in ids:
        fail("Turkey missing from world data")
    regions.sort(key=lambda r: r["name"])
    return {
        "id": "world",
        "name": "Dünya",
        "version": 1,
        "projection": "equalEarth",
        "parentRegionID": None,
        "groupTitle": "Kıta",
        "unitName": "ülke",
        "groups": CONTINENT_ORDER,
        "regions": regions,
    }


def write(pack, out_dir):
    path = os.path.join(out_dir, f"{pack['id']}.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(pack, f, ensure_ascii=False, separators=(",", ":"))
    size = os.path.getsize(path)
    counted = sum(1 for r in pack["regions"] if r["countsTowardTotal"])
    print(f"✓ {pack['id']}: {len(pack['regions'])} regions ({counted} counted), {size / 1024:.0f} KB")
    if size > 1_500_000:
        fail(f"{path} is too large ({size} bytes)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--turkey", required=True)
    ap.add_argument("--provinces", required=True)
    ap.add_argument("--world", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    write(pack_turkey(args.turkey, args.provinces), args.out)
    write(pack_world(args.world), args.out)


if __name__ == "__main__":
    main()

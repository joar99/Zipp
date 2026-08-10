#!/usr/bin/env python3
"""Derives the platform -> lines mapping that GTFS refuses to state directly.

A stop knows nothing about the lines calling at it. The only path is
`stop_times -> trips -> routes`, and `stop_times` is 416 MB uncompressed across
the NYC feeds — far too much to ship or to parse on a phone. So the join happens
here, at build time, and the app ships the few hundred KB of answers instead.

Run from the repository root:

    python3 Tools/generate_lines.py

Writes Packages/ZippFoundation/Sources/ZippFoundation/Resources/Lines.json
"""

import csv, io, json, os, sys, urllib.request, zipfile, collections

FEEDS = {
    "subway":            "https://rrgtfsfeeds.s3.amazonaws.com/gtfs_subway.zip",
    "bus-bronx":         "https://rrgtfsfeeds.s3.amazonaws.com/gtfs_bx.zip",
    "bus-brooklyn":      "https://rrgtfsfeeds.s3.amazonaws.com/gtfs_b.zip",
    "bus-manhattan":     "https://rrgtfsfeeds.s3.amazonaws.com/gtfs_m.zip",
    "bus-queens":        "https://rrgtfsfeeds.s3.amazonaws.com/gtfs_q.zip",
    "bus-staten-island": "https://rrgtfsfeeds.s3.amazonaws.com/gtfs_si.zip",
    "bus-company":       "https://rrgtfsfeeds.s3.amazonaws.com/gtfs_busco.zip",
    "nyc-ferry":         "https://nycferry.connexionz.net/rtt/public/utility/gtfs.aspx",
    "path":              "https://data.trilliumtransit.com/gtfs/path-nj-us/path-nj-us.zip",
}

# Route colours are published without a leading '#', and some feeds omit them.
FALLBACK_COLOUR = {3: "4D5357", 711: "4D5357", 4: "007D8C", 2: "C60C30"}


def rows(archive, name):
    with archive.open(name) as handle:
        yield from csv.DictReader(io.TextIOWrapper(handle, encoding="utf-8-sig", errors="replace"))


def clean(value):
    return (value or "").strip()


def main():
    lines_by_key = {}
    platform_lines = collections.defaultdict(set)

    for feed_id, url in FEEDS.items():
        print(f"  {feed_id}: downloading…", flush=True)
        payload = urllib.request.urlopen(url, timeout=600).read()
        archive = zipfile.ZipFile(io.BytesIO(payload))

        route_of_trip = {}
        for route in rows(archive, "routes.txt"):
            route_id = clean(route.get("route_id"))
            if not route_id:
                continue
            key = f"{feed_id}:{route_id}"
            try:
                route_type = int(clean(route.get("route_type")) or -1)
            except ValueError:
                route_type = -1
            name = clean(route.get("route_short_name")) or clean(route.get("route_long_name"))
            colour = clean(route.get("route_color")) or FALLBACK_COLOUR.get(route_type, "4D5357")
            lines_by_key[key] = {
                "n": name,
                "c": colour.upper(),
                "t": route_type,
                "l": clean(route.get("route_long_name")),
            }

        for trip in rows(archive, "trips.txt"):
            route_id = clean(trip.get("route_id"))
            if route_id:
                route_of_trip[clean(trip.get("trip_id"))] = f"{feed_id}:{route_id}"

        seen = 0
        for stop_time in rows(archive, "stop_times.txt"):
            key = route_of_trip.get(clean(stop_time.get("trip_id")))
            if key:
                platform_lines[f"{feed_id}:{clean(stop_time.get('stop_id'))}"].add(key)
            seen += 1
        print(f"    {seen:,} stop_times -> {len(platform_lines):,} platforms so far", flush=True)

    # Drop routes nothing calls at, so the catalogue only carries what is reachable.
    used = set()
    for keys in platform_lines.values():
        used |= keys

    payload = {
        "lines": {key: value for key, value in lines_by_key.items() if key in used},
        # Sorted so the file is stable between runs and diffs stay readable.
        "platforms": {k: sorted(v) for k, v in sorted(platform_lines.items())},
    }

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = os.path.join(root, "Packages/ZippFoundation/Sources/ZippFoundation/Resources/Lines.json")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w") as handle:
        json.dump(payload, handle, separators=(",", ":"), sort_keys=True)

    size = os.path.getsize(out)
    print(f"\nwrote {out}")
    print(f"  {len(payload['lines']):,} lines, {len(payload['platforms']):,} platforms, {size/1024:.0f} KB")


if __name__ == "__main__":
    sys.exit(main())

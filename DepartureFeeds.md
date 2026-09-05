# Departure feeds — research

Findings only. No decisions yet, no code. Everything below was probed live on
**2026-08-10**; re-probe before trusting it, these are other people's servers.

There is no single NYC departures API. Four publishers, and one of them does not
publish one at all.

---

## Probe results

| Publisher | Endpoint | Key | Shape | Per-stop | Size |
|---|---|---|---|---|---|
| Subway | `api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2F<feed>` × 8 | **none** | GTFS-RT protobuf | no | 5–182 KB |
| Bus (SIRI) | `bustime.mta.info/api/siri/stop-monitoring.json` | **required** | JSON | **yes** | small |
| Bus (GTFS-RT) | `gtfsrt.prod.obanyc.com/tripUpdates` | none | GTFS-RT protobuf | no | **2.4 MB** |
| Ferry | `nycferry.connexionz.net/rtt/public/utility/gtfsrealtime.aspx/tripupdate` | none | GTFS-RT protobuf | no | 1.4 KB |
| PATH | `panynj.gov/bin/portauthority/ridepath.json` | none | bespoke JSON | **yes**, all 13 at once | 10 KB |

All returned HTTP 200 unauthenticated except SIRI, which returned 401.

**MTA's own documentation is wrong about keys.** The developer page states an
account and key are required for the realtime feeds. All eight subway feeds served
real protobuf with no key and no headers.

---

## Subway

Eight feeds, split by line group, not by geography:

| feed | lines |
|---|---|
| `gtfs` | 1 2 3 4 5 6 7 S |
| `gtfs-ace` | A C E, Rockaway shuttle |
| `gtfs-bdfm` | B D F M |
| `gtfs-g` | G |
| `gtfs-jz` | J Z |
| `gtfs-l` | L |
| `gtfs-nqrw` | N Q R W |
| `gtfs-si` | Staten Island Railway |

There is no per-stop query. A feed is a snapshot of **every train currently running
on those lines**, each carrying its own remaining stop sequence. Departures for one
station are obtained by inverting that: scan every trip, keep the stop-time entries
whose stop matches, sort by time.

Decoded live, 2026-08-10:

| feed | trains | stop-time predictions | distinct platforms | bytes |
|---|---|---|---|---|
| `gtfs-l` | 26 | 457 | 48 | 24 KB |
| `gtfs` | 247 | 5,459 | 354 | 182 KB |

The `gtfs` feed also carries 150 vehicle-position entities and 1 alert, and its
trips span nine route ids — `1 2 3 4 5 6 6X 7 GS` — so the express variant and the
shuttle are their own routes, exactly as in the static feed.

**Realtime `stop_id` is our platform id, verbatim.** The feed returns `L02N`,
`138S`, `239S` — the same direction-suffixed identifiers already stored as
`Platform.id` (minus the `feed:` qualifier). This is what CLAUDE.md anticipated
under "Platforms are where lines attach": departures hang off platforms, and no
mapping table is needed.

Consequences, all of them structural:

- Answering "when is the next train at this platform" costs a whole line group.
- `route_id` and `stop_id` in the realtime feed are the **same identifiers as the
  static feed**, which is what makes the join possible at all.

### How many feeds one station needs

Computed by mapping every subway platform's lines onto the feed carrying them:

| feeds needed | stations |
|---|---|
| 1 | 423 |
| 2 | 60 |
| 3 | 13 |

**Three is the worst case**, and 85% of stations need exactly one. An earlier note
here claimed Times Square needed four; that was asserted from memory and is wrong.
It cannot happen — no station's lines span four groups, partly because what GTFS
calls a station is only ever one group of platforms to begin with.

Which routes sit in which feed, read off the live feeds rather than the docs:

| feed | routes |
|---|---|
| `gtfs` | 1 2 3 4 5 6 6X 7 GS |
| `gtfs-ace` | A C E H |
| `gtfs-bdfm` | B D F FS M |
| `gtfs-g` | G |
| `gtfs-jz` | J Z |
| `gtfs-l` | L |
| `gtfs-nqrw` | N Q R W |
| `gtfs-si` | SI |

`Z` and `FX` never appeared in a live sample — both are rush-hour only. They belong
to `gtfs-jz` and `gtfs-bdfm` respectively, and neither changes the table above,
since every station they touch already pulls that feed for `J` or `F`.

## Bus

Two mutually exclusive options.

- **SIRI** — genuinely per-stop, takes a GTFS stop id directly, returns JSON. Needs
  a key, free, issued in about half an hour from `register.developer.obanyc.com`.
- **GTFS-RT** — no key, but `tripUpdates` is 2.4 MB per poll. Every bus in the city.

## Ferry

Ordinary GTFS-RT, no key, and small enough that the whole-system download is a
non-issue. Same host as the static feed already in use.

## PATH

No official feed exists. Two unofficial routes:

- **`panynj.gov/bin/portauthority/ridepath.json`** — the backend behind PANYNJ's own
  RidePATH app. All 13 stations in one 10 KB response, each with per-destination
  countdowns, headsign, and line colour. Effectively a finished departures API.
  Undocumented, no stability contract.
- **`path.transitdata.nyc/gtfsrt`** — a third-party GTFS-RT translation of the above,
  maintained by one person.

Sample of the PANYNJ payload:

```json
{ "consideredStation": "NWK",
  "destinations": [{ "messages": [
    { "target": "WTC", "secondsToArrival": "1131", "arrivalTimeMessage": "19 min",
      "lineColor": "D93A30", "headSign": "World Trade Center" }]}]}
```

Note it keys stations by its own codes (`NWK`, `WTC`), **not** by the GTFS stop ids
the rest of the app uses. That mapping does not exist yet.

---

## Polling and rate limits

Everything here is poll-based. Nothing pushes, and no publisher offers a
subscription, websocket or long-poll.

**No publisher documents a rate limit.** One third-party SDK README claims Bus Time
enforces one request per 30 seconds; that figure appears on none of MTA's own pages
and is unverified. Do not design against it without confirming.

What the servers state in their own response headers:

| feed | cadence advertised | conditional request |
|---|---|---|
| Ferry | `Expires` 5s after `Last-Modified` | yes, `Last-Modified` |
| Bus GTFS-RT | `Cache-Control: private, max-age=10` | no |
| PATH | `Cache-Control: max-age=15, public` | **yes, `ETag`** |
| Subway | **nothing** | **no** |

**The subway feed sends no cache headers of any kind** — no `ETag`, no
`Last-Modified`, no `Cache-Control` — and returns **403 to `HEAD`**, so it cannot
even be probed cheaply. Every poll is a full download of the whole line group, and
nothing indicates whether anything changed.

Note this defeats the `HEAD`-then-range trick the static feeds use (see CLAUDE.md,
"The range-request trick"). That approach transfers to PATH and nothing else worth
having.

## Open consequences

1. Three of four speak protobuf. The project has no protobuf dependency today.
2. Bus is the only feed that forces a key, and the keyless alternative is not viable
   on a phone.
3. PATH depends on an endpoint nobody promised to keep.

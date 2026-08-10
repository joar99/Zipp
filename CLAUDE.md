# Zipp

An offline-first NYC public transit app.

This file records **why** the code looks the way it does. Most of the decisions
below were reached by inspecting the real feeds, and several are counter-intuitive
enough that they would otherwise be "corrected" back into bugs. Keep it current.

---

## Architecture

Five local Swift packages, acyclic:

```
ZippFoundation   (no dependencies)   models, DI container, repositories with no other needs
ZippNetworking   → Foundation        GTFS fetching + decoding; the only module that knows the wire format
ZippData         → Foundation, Net   SwiftData stack + repositories that need both
ZippNavigation   (no dependencies)   NavigationController, coordinators, sheet presentation
ZippiOS          → Foundation, Data, Navigation   views, view models, coordinators
```

MVVM-C throughout:

- **Coordinators** own view models, own presentation, and mediate between screens.
- **View models** own screen state and expose it; they never reach into the environment.
- **Views** render what they are given and report user events upward. A view never
  pushes data into a view model.
- Repositories are injected via `DependencyContainer` using a defaulted initialiser
  parameter. Note that default arguments evaluate at the *call site*, so anything
  that registers dependencies (i.e. `AppCoordinator`) must resolve them inside its
  body instead.

---

## Where the data comes from

There is no transit "API" for NYC in the usual sense. Every operator publishes
**GTFS**: a ZIP of CSV files at a static URL. Consequences:

- **No API key** for static feeds. (Realtime/GTFS-RT does need one — that is a
  separate, later problem.)
- **No pagination, no rate limits** worth worrying about. It is a file download.
- **No single NYC feed.** Nine separate archives are aggregated: subway, five
  borough bus feeds, MTA Bus Company, NYC Ferry, PATH.

LIRR and Metro-North are deliberately excluded: commuter rail whose stops are
overwhelmingly outside the five boroughs.

### The range-request trick

`stops.txt` is ~1 MB across all feeds. The archives containing it total ~52 MB,
because `stop_times.txt` (the timetable) dominates every one of them.

A ZIP keeps its table of contents at the *end* of the file, so `RemoteZipReader`
fetches the trailer, parses the central directory, and requests only the byte range
holding `stops.txt`. Measured: **908 KB instead of 52 MB, 98.3% saved.**

### Weekly refresh

`HEAD` for the ETag, compare with the stored one, and only range-fetch when it
differs. Deliberately **not** a conditional `GET` with `If-None-Match`: on a cache
*miss* that sends the entire archive and throws away the range optimisation.

The feeds churn far more often than stops do — `stop_times` changes with every
schedule tweak — so an unchanged-stops week still costs one HEAD per feed and
nothing more.

---

## What the feeds actually contain

Everything here was verified against live data. Re-verify before contradicting.

### Modes are one-per-stop

A full `stop_times → trips → routes` join over the ferry, PATH, subway and a bus
feed found **zero stops serving more than one `route_type`**. Re-verified against
the generated catalogue once every feed was joined: **0 of 15,405 platforms** serve
two. Even the NYC Ferry feed — which contains two bus routes for its shuttle
service — puts those on different stop IDs than the ferry landings.

There is also **no ID overlap between rail and bus** (1,552 rail IDs, 13,370 bus
IDs, zero shared).

So a stop place has exactly one mode. `StopPlace.Kind` is singular, not a set, and
the mode may be read from any one line calling there without reconciling the rest.

### Mode comes from the label, not from the feed

`Kind` is derived from the operators' published `route_type` and from **nothing
else**. It used to be inferred from which archive a stop arrived in. Both sources
are wrong sometimes, and the feed is actually wrong *less* often:

| | wrong | which stops |
|---|---|---|
| feed inference | 25 | NYC Ferry's two Rockaway shuttle *buses*, drawn as ferry landings |
| published label | 42 | Staten Island Railway, which calls itself commuter rail but is a metro |

They disagree on **67 of 15,405** stops; on the other 15,338 they agree exactly.

The label wins anyway, and the reason is not accuracy:

- Inference needs a hand-written rule per feed, kept forever, and a tenth feed
  arrives with no rule at all. The label costs nothing when an operator is added.
- Where inference is right it is right *by accident* — the Staten Island Railway
  reads as subway only because MTA happens to ship it in the subway archive.
- A wrong label is the operator's to fix, and fixable. A wrong inference is ours.

Mixing them — label except for these two known cases — was considered and
rejected: that is a heuristic table that grows every time a feed changes.

**The price, accepted knowingly:** the Staten Island Railway renders as rail rather
than subway.

`route_type` 2 is *Rail*, and both PATH and the Staten Island Railway publish it.
Nothing in the data separates them, so `Kind.rail` covers both and the old
`Kind.path` is gone. They are a state apart and never share a screen.

**A stop with no scheduled service now has no mode**, and the repository drops it
rather than inventing one — the count is logged per query at debug level. This is
the one behaviour the old feed-based fallback used to cover.

### Platforms have no location and no name of their own

- **1,021 of 1,021** platforms (992 subway, 29 PATH) sit at their parent station's
  *exact* coordinate.
- **1,021 of 1,021** have names byte-identical to their parent station's.

A platform is therefore **a direction, not a place**. `101N` and `101S` are the
northbound and southbound sides of one point on the map.

Two things follow. `Platform` carries no coordinate and no name — modelling either
would be inventing data. And the map pins **stations**, never platforms; drawing
platforms would stack every one of them on a single pixel.

### Platforms are where lines attach

All **565,093** `stop_times` references point at platforms; **none** point at
stations. So:

- subway/PATH: lines belong to platforms, and a station's lines are the union of
  its platforms'
- bus/ferry: lines belong to the stop directly, since there is no platform layer

This is the *only* reason `Platform` exists as a type. Before lines, a platform
was an ID and nothing else.

### GTFS cannot express a station complex

GTFS allows exactly **one** level of `parent_station` — a station cannot contain
another station. MTA spends that level on direction, so what GTFS calls a
"station" is really *the platforms for one group of lines*.

Times Square is therefore four station records (plus Port Authority), spread over
**293 metres**, with transfer times up to **420 seconds**. MTA expresses the
grouping in `transfers.txt` instead — 150 rows linking different stations into 35
complexes.

**We deliberately do not model complexes.** Reasons:

1. A complex has **no name**. 17 of the 35 have members that disagree
   (`Chambers St` + `Cortlandt St` + `Park Place` + `World Trade Center`), and
   nothing in the data says what to call the result.
2. A merged pin would sit at the **centroid** — for Times Square, mid-block on
   42nd Street, quite possibly nowhere near an entrance, while hiding that the
   A/C/E is a five-minute walk from the 1/2/3.
3. The payoff is small: 496 subway pins would become ~444, a 10% declutter.

`transfers.txt` exists in four feeds (subway, LIRR, Metro-North, PATH) but only
subway's links different stations. The others publish thousands of rows that point
a stop at itself.

### Entrances exist only for PATH

PATH publishes 22 entrances, averaging 65 m from their station and each with a
genuine coordinate of its own. **No other feed has any.** The subway feed has no
`location_type=2` records at all.

Deferred: one publisher out of nine is not enough to model against. When it
matters (walking directions), the subway's separate stations/entrances dataset is
the thing to fetch.

### Stops are duplicated across bus feeds

**686 stops** are published twice with the same ID, same name and near-identical
coordinates. 787 of the 935 colliding IDs involve MTA Bus Company overlapping a
borough feed; the other 148 are one NYC Transit route crossing a borough boundary
and landing in two files.

These are provably the same physical stop — identical IDs — so deduplicating them
requires no judgement. **Not yet implemented.**

Do *not* extend this to fuzzy spatial merging. Two bus stops on opposite corners
are genuinely different stops (different directions of travel), and merging by
proximity misfiles them: `TRINITY PL/RECTOR ST` is 88 m from **Wall St** station
but only 106 m from **Rector St**, the one it is named after.

### Feed quirks that have already caused bugs

- **Coordinates are padded.** Bus feeds publish `"  40.872562"`; `Double.init`
  rejects leading whitespace and returns `nil`. Every field is trimmed on decode.
  This silently discarded all 14,337 bus stops once.
- **Line endings differ per feed.** Subway uses bare LF, bus feeds use CRLF. Swift
  folds `\r\n` into a *single* `Character`, so a bare `case "\n"` matches nothing
  in a CRLF file and parses the entire feed as one row.
- **Columns differ per feed.** Bus feeds add `stop_desc`, `zone_id`, `stop_url`.
  Columns are bound by name, never by position.
- **Stop IDs are only unique within a feed**, which is why `StopPlaceEntity` has a
  compound `#Unique([\.feedID, \.stopID])`. Constraining on `stopID` alone made
  SwiftData silently upsert one operator's stop over another's.

---

## The model

```
StopPlace          what a rider walks to and sees departures from — the map pin
 └─ Kind           bus(Platform) | ferry(Platform) | subway([Platform]) | rail([Platform])
     └─ Platform   a direction within the stop; owns the lines
```

`Kind` has one case per `route_type` the feeds publish, and `rail` is PATH *and*
the Staten Island Railway because both publish the same one. See "Mode comes from
the label, not from the feed" above.

`StopPlace` is a **station** for subway/PATH and a **boarding point** for
bus/ferry. That asymmetry is the data's, not ours: buses have no station layer.

Why a struct wrapping an enum rather than a bare enum:

- `id`, `name` and `coordinate` are needed by every case (the map draws a pin from
  them), so a bare enum would duplicate them into all four payloads.
- The enum still gives exhaustiveness — adding a feed breaks the build until it is
  handled, which is wanted.
- `bus(Platform)` takes exactly one platform rather than an array, so "a bus stop
  with no platforms" is unrepresentable.

Every station has platforms — verified: subway exactly 2, PATH 2–4, **zero** with
none — so `subway([Platform])` never receives an empty array.

`Kind` replaces the earlier `Set<TransportMode>`. Since no stop is multi-modal, a
set was modelling a possibility that does not exist.

`TransportMode` exists again, but as something else entirely: the four `route_type`
values the feeds publish, carried on `Line`. It is the *input* to `Kind` rather than
a replacement for it — `Kind` adds the platform structure that a bare mode cannot
express.

### Facade vs storage

Three representations, deliberately:

| Type | Lives in | Purpose |
|---|---|---|
| `GTFSStopRow` | ZippNetworking | one CSV row, exactly as published. Never leaves the module. |
| `StopPlaceRecord` | ZippFoundation | one flat stop, `Sendable`, crosses module and actor boundaries |
| `StopPlace` | ZippFoundation | the assembled facade with its hierarchy |

`StopPlaceEntity` stores records flat, mirroring GTFS. The repository assembles the
hierarchy on read. Storing the tree instead would fight both SwiftData and the
incremental merge.

Two SwiftData traps already hit:

- **`#Predicate` will not take a force-unwrapped optional or membership in a
  captured `Set`.** It compiles and then throws at runtime, and because the caller
  used `try?` the map simply drew nothing while the store was perfectly fine. Fetch
  broadly and filter in Swift instead.
- **Platforms are cached in memory** (`platformCache`) because every read needs them
  and there are only 1,021 in total. Invalidated solely by a refresh that changed
  rows.

Records rather than `@Model` instances cross boundaries because SwiftData models
stay bound to the `ModelContext` that created them.

---

## Next steps

Roughly in order of value.

1. **Deduplicate the 686 repeated bus stops.** Exact ID match, no heuristics.
2. **Departures.** Live, not offline — the user's call. Note the asymmetry: MTA has
   no per-stop departures endpoint for subway (GTFS-RT is a protobuf dump of the
   whole system that you filter client-side), while buses expose SIRI
   `StopMonitoring`, which genuinely is per-stop. Both need an API key.
   This is the last mock left in the app.
3. **Seed the store at build time** so first launch is instant and needs no network.
4. **Platform direction.** `101N`/`101S` encode it in the ID suffix. Currently
   mocked off that suffix, which is why a bus stop reads "All departures".

**Done:**

- **Lines.** `Tools/generate_lines.py` performs the `stop_times → trips → routes`
  join at build time — 416 MB uncompressed, far too much to ship — and writes an
  834 KB `Lines.json` of 390 lines across 15,405 platforms. The weekly refresh still
  handles stops only. Regenerate when the feeds change materially.
- **`Kind` from `route_type`.** Free once (1) existed, because the generator was
  already writing `route_type` into the catalogue. Argued at length under "Mode
  comes from the label, not from the feed".

Also known, not worth its own item: `stopPlace(id:)` has no caller. If one appears,
give it the same `parentStationID == nil` filter `stopPlaces(in:)` has, or it will
happily return a station with no platforms.

Deliberately **not** planned: station complexes, cross-mode merging, offline
timetables, entrances. Each is argued above.

---

## Rendering notes

The map is SwiftUI `Map`, not `MKMapView`. SwiftUI has **no clustering, no
`displayPriority`, no `collisionMode`** — verified against the SDK — so density is
handled upstream instead:

- **Grid decimation** anchored to *absolute* coordinates, not the viewport, so
  panning does not reshuffle which stop wins a cell. Ties break deterministically
  (rail, then ferry, then bus, then by id) so the selection is stable frame to
  frame.
- **Cell size is the larger of two constraints**: enough cells to fill the render
  budget, *and* at least the annotation's own footprint converted from points into
  degrees. Budget alone is not enough — 60 plates over a phone screen yields ~80 pt
  cells for annotations ~190 pt wide, so neighbours overlap by construction. This
  is why `MapView` passes its size down via `GeometryReader`.
- **Per-detail budgets**: 250 dots, 60 plates. A plate lays out text and covers far
  more area, so they cannot share a budget.
- Camera changes are debounced 150 ms with the in-flight query cancelled.

Annotation content must stay cheap. **No materials, no shadows, no blurs**: a
material re-blurs its backdrop every frame the map moves, which at hundreds of
annotations was the single largest cost on screen. Detail level and contents are
applied together so a dot-sized crowd is never briefly rendered as plates.

### Animate the annotation, never the data

`.animation(_:value:)` on `StopPlaceAnnotation` is correct. Wrapping the
`visibleStopPlaces` assignment in `withAnimation` is **not**, and the difference was
measured rather than argued:

| | `withAnimation` | `.animation(value:)` |
|---|---|---|
| bodies built for 22 annotations | 143 | 22 |
| worst frame | ~108 ms | ~16–46 ms |

Animating the data keeps departing annotations alive for the duration, and since
`annotationDetail` is shared they render in the *new* detail on the way out — a
hundred outgoing dots each drawing themselves as a full plate before vanishing.

The transition animation was removed once for being "laggy as hell" and later
restored unchanged, after the real causes were fixed: the platform-lookup tax
below, blur materials, and a 400-annotation budget at both detail levels. It costs
almost nothing on its own.

### Things that looked like the bottleneck and were not

Measured with `CADisplayLink` frame-drop counts and stage timings, both since
removed:

- **Rasterising annotations to cached `UIImage`s** (the approach used in a sibling
  UIKit app) would have saved microseconds. SwiftUI already reuses annotations
  across a settle — 131 shown, 49 built — so construction was never the cost.
- **The actual cost was one line of my own**: `platformsByParentID()` re-fetched all
  1,021 platform rows on *every* query, ~30 ms regardless of whether the caller
  wanted 13 stops or 509. It is now held in memory and invalidated only by a
  refresh that changed rows. Assembly went from ~30 ms to ~0.2 ms.

Do not reach for render-level optimisation here before timing the data path.

# Performance audit

The performance suite measures how HolyBeans behaves as its journal grows.
It uses synthetic data and temporary databases. The reusable measurement harness lives under `benchmark/`. The baseline
findings below describe version 1.4.0 before the production improvements listed
here; keep baseline observations separate from follow-up measurements.

## First implementation (PR #16)

- `foldSuggestion` writes normalized UTF-16 units into a single bounded buffer,
  avoiding one short string per character. A streaming substring matcher stops
  at the first normalized match without allocating a folded copy of the whole
  note; overlapping patterns keep linear worst-case behavior. Exhaustive code-unit comparisons and
  mixed Unicode fixtures check the previous accent/whitespace behavior.
- History filtering runs outside widget builds. Large text searches execute in a
  worker, with one in-flight request and only the latest request queued. Clearing
  a search takes effect immediately; obsolete results cannot overwrite newer
  filters or journal data. Matching short metadata avoids processing notes when
  possible, with the complete-string fallback preserving cross-field phrases.
- Live brew subscriptions read changed rows and reuse unchanged objects. Screens
  sharing a repository also share the snapshot, including notes. SQLite TEMP
  triggers track writes independently of application timestamps, including
  replacement imports and deletions. A read transaction pairs the revision and
  rows; the last subscriber releases the cache and database subscription.
- Tabs mount on first visit and preserve their local state. Visited tabs receive
  current data so retaining tab state does not retain obsolete journals.
- The shell reuses its immutable `JournalData` snapshot and computes the latest
  style for each coffee once per relevant data revision.
- Gaussian curve smoothing reuses weights for regular sampling and shares each
  weight across series. Flow medians reuse candidate distribution evaluations
  and preordered segment bounds. Tests compare irregular sampling, signed flow,
  plateaus and the original numerical results; stored measurements are unchanged.
  Curves over 200 points are prepared in a coalescing worker. Only the displayed
  polyline is reduced to at most 1,024 samples, retaining endpoints and each
  bucket's extrema across all series. Cursor readings, statistics, bounds and
  exports continue using full-resolution data. Live charts show each completed
  coherent snapshot while keeping only the newest pending input; static charts
  discard obsolete results.

The connection-local change ledger is an implementation detail, not persisted
journal data: the database/backup versions stay compatible. It stores at most
one revision per brew ID touched during that connection, including deleted IDs.
See SQLite's [TEMP trigger behavior](https://www.sqlite.org/lang_createtrigger.html#temp_triggers_on_non_temp_tables)
and Drift's [stream invalidation rules](https://drift.simonbinder.eu/dart_api/streams/).
As with the previous Drift streams, writes through unrelated connections need
explicit invalidation; this change does not introduce cross-process watching.

That first iteration retained complete initial brew rows. The bounded read
architecture below replaces that shell subscription; full-row subscriptions
remain available to exports and callers that explicitly need them.

## Bounded journal and incremental curves

- The shell subscribes to SQL aggregates and at most three note-free previews
  per coffee, plus one favorite recipe and one latest active recipe per coffee.
  Counts, ratings, last use, years and typical doses cover the complete journal.
  A connection-local dirty-coffee ledger refreshes only affected summaries,
  including both owners of moved/replaced brews; unchanged previews are reused.
  Weekly counts expire entries as time passes without needing a new write.
  Four composite indexes support history, per-coffee and favorite lookups. They
  are installed on existing databases without rewriting rows or changing backup
  formats; historical schema reconstruction drops these current access indexes.
- History uses keyset pages of 50 matches and an LRU of six pages (300 previews).
  It prefetches near the end, reloads evicted pages when scrolling back, and
  invalidates cursors after a write. Searches preserve the same normalized
  substring/cross-field semantics, reading at most 64 candidates with notes at
  a time; long-note batches share one worker per page and obsolete searches
  stop between batches. Small bounded text batches avoid worker startup. Cached rows omit notes and
  pour JSON. Editing, rating, sharing, comparing and viewing details fetch the
  complete record by ID first.
- Equipment, recipient and roaster cards use complete aggregates. Statistics,
  year review and comparison request note-free analytics only when opened.
  Freshness detail requests all rated observations, preserving evidence from
  older brews and other coffees. Large statistics and freshness calculations
  run off the UI isolate; statistics lists construct visible sections lazily.
  Analytics still scale with the number of observations while those screens
  are open; this is not a constant-memory database engine.
- Each large chart reuses one worker. Append-only updates smooth the affected
  tail, update ranked sample values and add elapsed-time distribution events
  to an AVL tree. Corrections, truncations, series changes and first-drip changes
  rebuild the state. Median/mean/peak equivalence tests cover irregular sampling,
  signed flow, pauses, near-flat numerical cancellation and future first-drip
  markers. Sub-nanounit flow segments use a midpoint mass for stable median
  evaluation (at most 5e-10 flow-unit quantile error); raw data, mean and maximum
  are unchanged. Display reduction remains
  bounded at 1,024 points; raw samples, cursor values and exports retain their
  original resolution. Snapshot transfer and display decimation still scan
  samples; the implementation does not claim every operation is constant time.
- Removed the discarded search prototype and its standalone test. Retained the
  production regression tests, reusable access/UI/media/chart/startup benchmarks,
  this report and historical findings. Raw logs, JSONL, APKs and transient output
  remain ignored under `artifacts/`.

### Regression budgets

Structural limits run in ordinary CI: page/cache bounds, complete aggregates,
notes excluded from previews, stable pagination, cancellation, and incremental
curve equivalence/work counters. Device timings use a separate comparison:

```sh
python3 -m tool.performance snapshot artifacts/performance-phase2/device-confirmed.jsonl benchmark/device-baseline.json
python3 -m tool.performance compare artifacts/performance-phase2/device-repeat.jsonl benchmark/device-baseline.json
```

The snapshot contains only context, scenario identities and selected metrics,
not sample arrays or logs. Refreshing an existing snapshot retains its manually
maintained `provenance` block; review that metadata when the source run or device
changes. Comparisons require the same OS/build context and
harness version, a complete successful audit, and every baseline scenario and
metric. Limits are baseline × 1.25 + 5 ms for elapsed time, × 1.25 + 2 ms for
median time, × 1.20 + 2 ms for build/raster p95, × 1.50 + 5 ms for
build/raster maxima, × 1.25 + 5 ms for startup first/subsequent median times,
× 1.25 + 10 CPU ticks, and
× 1.20 + 4 MiB for post-GC main-isolate heap, plus × 1.20 + 16 MiB for
process RSS (which includes workers and native memory). These are provisional regression
allowances, not universal product promises. A failure requires investigation
and repeated controlled runs; do not refresh a baseline merely to make it pass.
Separate baselines are required for another phone. The available physical
validation device remains the Galaxy A53; a second lower-memory phone has not
been measured.

Harness version 6 measures production paginated/aggregate paths. Its
`history_first_page_*` operations return up to 50 matches and must not be
compared as if they were the old full-history search operations. Likewise,
`rate_one_and_receive_overview` waits for the shell aggregate, whereas the old
operation waited for a full-row stream. UI and chart scenarios retain their
user interactions. See the recorded measurements for actual changes.

### Final measurements on the available phone

The complete harness-v6 `phase2-confirmed` profile run passed on the Galaxy
A53 (Android 15, 60 Hz), using application source `cd36c82` from a historical
branch not preserved in this repository. It includes all nine
access fixtures, three UI journal sizes, media/backup round trips, startup and
three live-curve sizes. The phone was USB powered; battery temperature was
observed at 32 °C during the run. Raw evidence and the source manifest remain
ignored under `artifacts/performance-phase2/`.

| Scenario | First implementation | Bounded/incremental implementation |
|---|---:|---:|
| Loaded shell, 5,000 × 2,048-character notes | 586.1 ms | 251.1 ms |
| Loaded shell, 10,000 × 2,048-character notes | 863.3 ms | 282.8 ms |
| Loaded-shell Dart heap, 10,000 × 2,048-character notes | 67.9 MiB | 31.8 MiB |
| Retained model Dart heap, 10,000 × 8,192-character notes | 108.4 MiB | 25.6 MiB |
| Statistics maximum build, 10,000 × 2,048-character notes | 285.8 ms | 74.1 ms |
| Detail cycles maximum build, 10,000 × 2,048-character notes | 201.6 ms | 32.5 ms |
| Search typing build p95, 10,000 × 2,048-character notes | 8.9 ms | 10.9 ms |
| 10,000-point live curve process CPU | 1232.0 ticks | 560.0 ticks |
| 10,000-point live curve build p95 | 7.3 ms | 9.8 ms |
| 10,000-point live curve maximum build | 18.1 ms | 10.7 ms |

The retained-model heap measurement is the main Dart isolate after GC, not total
RAM. For the 10,000 × 8,192-character notes fixture, process RSS at model load changed from
420.7 to 330.5 MiB. Shell timing excludes OS/engine launch. Curve
CPU includes the same synthetic producer and 100 paced updates, with full final
samples verified. These are observed runs, not statistically established speedup
guarantees across devices.

The 10,000 × 8,192-character notes journal now returns its first 50 `citrico` matches in
10.6 ms median. A no-match query still scans all notes and takes
1789.3 ms; it remains cancellable and runs without retaining the complete
notes collection. This is not equivalent to the older resident-memory search
microbenchmark, which excluded database access. Rating and receiving the complete
shell summary takes 16.0 ms median for this fixture. The intermediate
all-coffee refresh cost 93.6 ms at 5,000 × 2,048-character notes; refreshing only dirty coffees
reduced that to 17.4 ms in the final run.

Not every frame metric improves: asynchronous loading adds short frames and
transitions, and isolated build/raster spikes remain. The strict comparator
flagged nine budget exceedances between two intermediate complete runs (including
first-load and GPU-frame variability). They are investigation signals, not proof
that a source change caused every spike. Budgets remain provisional; they are
not an unconditional timing gate in ordinary CI. The [compact device reference](../benchmark/device-baseline.json)
contains 158 scenario records without raw sample arrays or logs. Use repeated
controlled measurements and a separate reference on a second, lower-memory
physical phone before treating these allowances as stable device-wide targets.

The independent `phase2-repeat` run also passed all functional assertions and
completed Android instrumentation successfully. Historical revision `b17eaf4`,
also from a branch not preserved in this repository, was recorded as containing
the same application source as `cd36c82`. Its 158 measured scenarios
triggered 12 metric-budget exceedances: initial loading (one), search (three),
insertion (two), full-row reading (two), UI frames (three) and backup export
(one). Examples include the 1,000-entry `citrico` search median, 48.6 → 72.1 ms;
the 10,000-entry statistics raster p95, 8.1 → 15.7 ms; and backup export median,
75.8 → 105.5 ms. The comparator exits unsuccessfully for these alerts; neither
the reference nor allowances were changed to conceal them. Two runs cannot
establish stable timing limits or isolate the source of device variability.
The principal improvements persisted: the 10,000-entry shell loaded in
277.8 ms, retained long-note model heap was 25.6 MiB, and the 10,000-point
curve again used 560 process CPU ticks. Raw repeat records, its source manifest
and comparison output remain in the ignored evidence directory.

The [complete final-source CI](https://github.com/Mancuerna/holybeans-public/actions/runs/41911404458)
passed **1,713 Flutter tests, with seven private-backup fixture skips**, native
Android tests, 37 Python tooling tests, formatting, static analysis and
documentation checks. Pagination/cancellation, complete summaries, replacement
imports, rollback, old-schema migrations and incremental curve equivalence have
regression coverage. The [implementation PR](https://github.com/Mancuerna/holybeans-public/pull/18)
records delivery status; subsequent report-only changes preserve that validated
application source.

## First implementation measurements (PR #16)

The same Galaxy A53 and profile configuration were used for the follow-up.
Journal/UI/media/startup results use source `44b5179` and harness version 4;
the final asynchronous chart results use `068cc5b` and harness version 5.
Both instrumentation runs completed successfully. These are sequential exploratory
runs, not randomized alternating trials or release performance guarantees.

| Scenario | Baseline | Improved |
| --- | ---: | ---: |
| Update one rating and receive history, 5,000 × 2,048-character notes | 311.1 ms | 9.2 ms |
| Same update, 10,000 × 2,048 | 660.3 ms | 14.2 ms |
| Same update, 10,000 × 8,192 | 1,118.0 ms | 14.9 ms |
| Search `citrico`, 5,000 × 2,048 | 1,575.4 ms | 27.2 ms |
| Search `citrico`, 10,000 × 8,192 | 12,912.0 ms | 141.8 ms |
| Missing search, 10,000 × 8,192 | 13,261.4 ms | 896.1 ms |
| Search typing build p95, 5,000 × 2,048 | 1,575.0 ms | 11.5 ms |
| Search typing build p95, 10,000 × 2,048 | 3,192.5 ms | 8.9 ms |
| Live chart build p95, 10,000 initial points | 107.6 ms | 7.3 ms |
| Reopen real main to loaded shell, 5,000 entries, subsequent median | 730.9 ms | 613.7 ms |

Update/search timings are medians. The baseline search benchmark measures the
old matching expression; the improved `history_query_*` records measure the
production selection including filters and sorting. Neither is end-to-end
worker dispatch or touch latency. The fixture's `citrico` match is near the start
of notes; missing searches still scan their full text. UI frame records measure
actual production search with background work and assert the final text/results.

Nine rating changes now fetch nine brew rows instead of 45,000/90,000. There
are 27 SELECTs/returned rows including revision checks, so this is less data
transfer and decoding, not fewer SQL calls. Inserting one entry fetches one new
brew row. The 5,000-entry post-update VM heap falls from 56.5 to 37.2 MiB; the
10,000-entry long-note case falls from 205.7 to 108.4 MiB. These are retained
post-GC checkpoints including the harness, not peak RSS or a leak diagnosis.
Initial full-row loading still scales with history and note length.

| Final live chart | Frames | Build p95 / max | Raster p95 / max | Builds / rasters over 16.7 ms |
| ---: | ---: | ---: | ---: | ---: |
| 300 initial points | 313 | 9.0 / 13.1 ms | 5.0 / 10.0 ms | 0 / 0 |
| 3,000 initial points | 320 | 6.7 / 11.9 ms | 9.4 / 31.8 ms | 0 / 10 |
| 10,000 initial points | 326 | 7.3 / 18.1 ms | 7.2 / 26.4 ms | 1 / 3 |

The final chart harness waits until the readout contains all 100 added samples,
including the last worker result. The 10,000-point case completes in 5.56 s
versus 8.84 s at baseline. Coalescing can skip intermediate rendered snapshots;
recorded samples are retained. Worker execution improves UI scheduling, but is
not a promise of less total process CPU or battery use: the 10,000-point
scenario records 1,232 process CPU ticks versus 1,001 at baseline, while
rendering 326 frames instead of 107. This includes the harness and worker
overhead and is not an isolated kernel comparison. The final 200-point
worker threshold also removes over-budget builds from the 300-point case in
this run; one build spike and several raster spikes remain in the large cases.

Other limits remain visible: at 10,000 entries, statistics opening still has a
285.8 ms maximum build and detail navigation a 201.6 ms maximum. Search typing
has one 17.1 ms build and two over-budget raster frames at 10,000 entries;
at 5,000, no builds but four raster frames exceed budget. Continuous history
scrolling remains around 7 ms build/raster p95. These results support the search,
update and long-curve changes; they do not establish that every screen is now
free of frame spikes. At that point the next priorities were bounded initial data loading and
profiling the statistics/detail transition work, followed by another phone.

The repeated media/backup scenarios still pass their data and photo round-trip
assertions. Median export/ZIP/restore timings are 78.2/128.9/448.7 ms versus
81.0/138.2/410.9 ms at baseline. Restoration is slower in this run, and the
eight-photo batch is 4.65 s versus 4.39 s. Individual 1.9/12 MP resizes are
782.6/848.0 ms versus 817.3/953.3 ms. These small sequential sample sets do not
establish that each difference comes from the code changes; no photo/backup
speedup or battery improvement is claimed.

Raw follow-up evidence is local under `artifacts/performance-improvements/`:
`device-final.jsonl` for the nine access fixtures and UI/media/startup scenarios,
and `device-chart-threshold.jsonl` for final chart results. Chart records in
`device-final.jsonl` predate asynchronous preparation; `device-charts.jsonl`
is an intermediate run with a 500-point worker threshold. Both are superseded
by `device-chart-threshold.jsonl` for final chart conclusions.

## Baseline findings: 2026-11-04

Source: `28dd175` (1.4.0+161), Flutter 3.47.5, Dart 3.13.4. Measurements used a
Samsung Galaxy A53 (SM-A536B), Android 15, a 60 Hz display, and profile mode,
except for the explicitly labeled release cold launches.
The device reports 5,517,928 KiB total RAM; it was USB powered, with an initial
battery temperature of 27.8 C (31.6 C after the profile runs). Battery temperature
does not establish whether CPU/GPU throttling occurred. These are observations
from one device, not
performance guarantees for every supported phone.

### Journal growth exposes two substantial bottlenecks

Median milliseconds, synthetic file-backed SQLite, nine samples for reads and
updates and five for searches. Note sizes below are body characters per entry,
plus a short unique numeric prefix.
"Update" includes changing one rating and receiving the refreshed history;
it is not the SQLite write time alone.

| Entries | Note size | Read entire history | Update one entry | Search `citrico` |
| ---: | ---: | ---: | ---: | ---: |
| 100 | 2,048 | 3.6 | 5.8 | 32.4 |
| 1,000 | 2,048 | 67.4 | 64.7 | 328.2 |
| 5,000 | 2,048 | 254.7 | 311.1 | 1,575.4 |
| 10,000 | 2,048 | 524.7 | 660.3 | 3,230.2 |
| 10,000 | 8,192 | 843.6 | 1,118.0 | 12,912.0 |

Query instrumentation confirms nine single-entry updates return 45,000 history
rows at 5,000 entries and 90,000 at 10,000. An insertion returns the entire
N+1 history too. This is repeated fetching and object allocation, rather than
evidence of a memory leak.

The production history widget reproduces the search problem. Progressive input
with 5,000 entries and 2,048-character notes produces a maximum Dart build time
of 1,606.7 ms; with 10,000 entries, 3,219.0 ms. Even the 100-entry fixture reaches
48.1 ms. At 60 Hz the per-frame budget is about 16.7 ms. Searching folds the
complete metadata-plus-notes string for each non-archived entry on each input
change, including rows outside the viewport.

Continuous history scrolling is substantially healthier: with 10,000 entries,
665 observed frames have build/raster p95 of 7.0/7.0 ms, zero builds over budget,
and one raster frame over budget. Other transitions still have spikes: opening
statistics reaches a 332.6 ms build, and detail navigation reaches 201.6 ms.
These observations identify whole-screen work worth profiling; the standalone
statistics calculation is only 25.2 ms at 10,000 entries, so it cannot alone
explain the statistics-screen spike.

### Candidate changes measured separately

At 5,000 entries, reading the **same 50 projected rows** takes 12.33 ms without
an index and 0.75 ms with the temporary composite index (about 16x faster).
SQLite changes from a scan and temporary sorting tree to an index search.
At 10,000 entries the indexed page remains under 1 ms in these fixtures.
This supports paginated projections and an index; it is not a claim of an
equivalent speedup for loading the complete application.

Replacing the character-list normalization with regular-expression replacements
only saves roughly 13–15% in the large-note fixtures. Checking short metadata
first is more effective **when that metadata matches**: the 5,000-entry `audit`
query falls from 1,598.2 to 35.7 ms. It does not solve note searches or misses:
the same prototype takes 1,668.4 ms for `citrico` versus 1,588.9 ms currently.
Neither prototype is a complete search solution or a production change.

### Memory and images

After loading the model and collecting garbage, VM-reported heap usage is
24.6 MiB at 100 entries with 2,048-character notes, 61.0 MiB at 10,000, and
119.5 MiB at 10,000 with 8,192-character notes. These totals include the harness
and model, and exclude native memory. The VM request targets the main isolate,
but its isolate group can share the reported heap; it is not an exclusive
accounting of main-isolate objects. RSS is recorded separately.
Retaining every note makes memory scale with journal size.

Ten real detail open/close cycles increase the post-GC VM heap by only
4,096 bytes at 5,000 entries and 5,456 bytes at 10,000. This short scenario does
not show accumulating detail-page retention, and does not rule out other leaks.
The photo-scroll scenario keeps about 428 KiB in Flutter's image cache at
10,000 entries, with six cached thumbnails. Existing display-size decoding is
working in this scenario; original-resolution thumbnail caching is not the
observed problem.

### Startup, backups, photo processing, and charts

Ten separate process-cold launches of an isolated **release** build with an
empty journal report Android `LaunchState: COLD`. `am start -W` reports
`TotalTime` of 851 ms on the first launch after clearing test data, then
603 ms median across nine further launches (545–681 ms). This is Android's
activity-first-display metric, not a loaded-journal or first-interaction metric.
The process is force-stopped between runs; OS storage caches are not flushed,
and these are not ten post-reboot launches.

Calling the real `main()` in an existing process reaches a loaded shell in
191.9 ms on its first empty-journal invocation and 131.8 ms median afterwards.
With 5,000 entries and notes, those observations are 830.8 and 730.9 ms. These
include service initialization and database opening, but exclude OS/engine
startup. The app has no paired devices or enabled remote backup in this test.

For 1,000 entries plus eight photos, exporting JSON takes 81.0 ms median, ZIP
encoding 138.2 ms, and replacement restore 410.9 ms. The resulting archive is
998,281 bytes; restored data and photo bytes match the originals. These measure
local backup primitives, excluding Drive/network and system document-picker I/O.

Photo processing takes 817.3 ms for the 1.9 MP gradient JPEG and 953.3 ms for
the 12 MP image; the eight-photo batch takes 4.39 s with concurrency capped at
three. The production resizer already decodes at the retained size and encodes
in worker isolates. These elapsed times do not establish UI blocking, and this
benchmark does not sample peak native image memory.

| Live curve initial points | Observed frames | Build p95 | Raster p95 | Builds over 16.7 ms |
| ---: | ---: | ---: | ---: | ---: |
| 300 | 260 | 15.6 ms | 5.0 ms | 1 |
| 3,000 | 206 | 29.1 ms | 7.6 ms | 100 |
| 10,000 | 107 | 107.6 ms | 5.8 ms | 100 |

Each case supplies 100 updates with 50 ms pacing. The 10,000-point case takes
8.84 seconds rather than approximately five: the UI cannot sustain the requested
update rate. Points are spaced at 100 ms, so the larger cases represent unusually
long curves (about five and seventeen minutes), not ordinary espresso shots.
Code inspection shows smoothing and flow statistics recomputed for the full
curve on updates. Incremental derived values and limiting displayed points are
worth a separate experiment, while retaining full-resolution stored/exported
data. The measurements do not attribute the entire frame cost to smoothing.

### Original recommendations from the baseline

1. **Search:** stop normalizing every long note in the UI build. Design a
   normalized search representation/query that preserves accents, substring
   matching, and cross-field phrases; run expensive work off the UI isolate and
   discard obsolete results. Debouncing alone still leaves a long blocking scan.
   Metadata short-circuiting can be an interim improvement, with its limitations
   above. Avoid permanently duplicating every long note in another in-memory
   normalized string merely to improve typing latency.
2. **History access:** add a matching composite index and bounded projections;
   fetch full notes/details by ID. Subscribe to the needed page/latest rows,
   and use dedicated aggregate queries for statistics. Validate stable ordering,
   all sort/filter modes, and page boundaries during concurrent edits.
3. **Rebuild and derived-data scope:** cache the immutable journal snapshot and
   per-coffee latest-style/freshness inputs by data revision. Narrow notifications
   and expensive work in inactive tabs. At 10,000 entries, 100 `data` getter calls
   cost 6.45 ms and all 250 latest-style scans cost 47.45 ms. The getter copies
   lists of references, not note strings; the repeated scans remain avoidable.
4. **Long live curves:** bound rendering work to screen resolution and update
   derived series incrementally. Preserve raw values and verify peaks, cursor
   readings, final weight, and irregular sampling before changing the display.
5. **Regression budgets:** repeat representative release/profile scenarios on a
   second, lower-memory phone, then establish stable budgets for search, rating
   updates, launch, frame spikes, and memory growth. Keep deterministic
   correctness checks in CI and noisy device timing comparisons in a dedicated
   performance run.

Relevant code: [history matching](../lib/ui/brews/history_tab.dart),
[history subscriptions](../lib/data/repositories/journal_repository.dart),
[journal snapshots and derived state](../lib/ui/shell/journal_view_model.dart),
[normalization](../lib/domain/text_suggestions.dart), and
[live charts](../lib/ui/brews/extraction_chart.dart).

## Manual backup export workers (November 2026)

Manual exports encode JSON and ZIP data in workers while retaining the journal
lock and database transaction for a consistent snapshot. Photo capture reads
only referenced files, once each; missing photos remain omitted. Automatic
journal snapshots also use background JSON encoding.

The host benchmark now measures the actual `JournalBackup.exportArchive` path
three times per fixture. A 2 ms periodic timer records the largest event-loop
gap during each export. The table reports medians across those three samples,
before production changes at `c623dd6` and after this optimization, using the
same driver and fixture parameters on the same Linux host (Flutter 3.47.5,
Dart 3.13.4, in-memory SQLite). Every sample checks journal and photo equality.

| Preparations / photos | Export before → after | Largest gap before → after |
| --- | --- | --- |
| 50 / 2 | 65.0 → 74.2 ms | 51.8 → 12.0 ms |
| 500 / 10 | 348.0 → 322.5 ms | 283.3 → 27.3 ms |
| 2,500 / 40 | 1,368.7 → 1,370.5 ms | 1,089.6 → 128.2 ms |

This reduces main-isolate blocking rather than establishing faster throughput.
Database reads and snapshot preparation still run on the calling isolate, and
the largest fixture still has a measurable pause. These are host observations,
not Android frame timings, network speeds or CI timing thresholds. The
`manualExportSamples` records include all elapsed times, maximum gaps and timer
tick counts so the comparison can be repeated.

## Backup restore workers (November 2026)

Backup previews decode ZIP or legacy JSON in a worker and retain the decoded
source and photos across confirmation. Restoration validates rows in a worker
before creating the staging directory, then applies those same validated rows
after photo promotion. Undo snapshots also encode JSON in the background;
the existing journal lock, write gate and durable rollback markers remain.

The same host harness measures `restoreArchive` with its 2 ms heartbeat. These
are single complete restores per fixture, before at `dc4dffa` and after the
change, using the same driver and fixture parameters. Every restored collection,
inventory amount, curve and photo is compared with its source.

| Preparations / photos | Restore before → after | Largest gap before → after |
| --- | --- | --- |
| 50 / 2 | 121.2 → 106.4 ms | 56.5 → 16.0 ms |
| 500 / 10 | 388.1 → 269.7 ms | 144.7 → 50.7 ms |
| 2,500 / 40 | 1,261.2 → 1,001.5 ms | 520.0 → 178.4 ms |

These observations do not establish Android frame budgets or sustained
throughput. SQLite writes and photo coordination still run on the caller;
the largest fixture retains a noticeable pause. The `restoreSample` record
contains elapsed time, maximum event-loop gap and heartbeat count.

## Drive photo verification (November 2026)

Photo verification requests size and checksums from Drive, preferring SHA-256
and using MD5 when SHA-256 is unavailable. Without checksum metadata it still
downloads and verifies bytes. These fields are documented in the
[Drive File resource](https://developers.google.com/workspace/drive/api/reference/rest/v3/files).
Journal downloads retain SHA-256 verification. Photo IDs are resolved once per
publish and new reservations are persisted together before any upload.

`benchmark/drive_photo_verification_benchmark_test.dart` compares the previous
implementation at `5e85a63` with this change using the same fake-server driver.
Each fixture publishes 64 KiB synthetic photos, adds a preparation and publishes
again without changing the photos. The second publication records:

| Photos | Photo media downloads before → after | Photo bytes before → after | Queue writes before → after |
| ---: | ---: | ---: | ---: |
| 2 | 2 → 0 | 131,072 → 0 | 2 → 0 |
| 10 | 10 → 0 | 655,360 → 0 | 10 → 0 |
| 40 | 40 → 0 | 2,621,440 → 0 | 40 → 0 |

Queue reads fall from one per photo to one per publication; the first publication
writes all reservations once. Every fixture downloads the resulting copy and
asserts equal photo bytes and journal hash. These are request and file-operation
counts, not measured network latency or Android frame performance.

## Drive recovery file retention (November 2026)

The retention/export regression fixtures compare `e15f13c` with the cleanup:

| Completed scenario | Files retained before → after |
| --- | ---: |
| Eight successful safety copies | 8 → 5 |
| Read a downloaded copy with no pending upload | 1 payload → 0 |
| Share an exported ZIP, including a failed share | 1 temporary ZIP → 0 |

Safety copies are verified before promotion and pruning; the current copy and
four previous copies survive, including after the clock moves backwards. Failed
captures preserve existing copies. Downloads never remove the pending upload ID;
unreadable upload state conservatively keeps files and logs the cleanup error.
These file counts are covered by `drive_backup_retention_test.dart` and
`drive_backup_export_test.dart`, including retry and content checks.

## Scale control rebuilds (November 2026)

The timing section and reset control now listen to scale-session state instead
of every reading. Timer-dependent controls also follow the timer. The weight
chart subscribes to raw scale readings only while recording; live weight readouts
continue following the scale in both states.

`brew_scale_rebuild_test.dart` drives 100 readings with one widget pump per
reading and counts the actual listener elements through Flutter's debug rebuild
hook. With the same driver at `2c7baf1` and after the change:

| Element | Idle rebuilds before → after | Recording rebuilds before → after |
| --- | ---: | ---: |
| Timing section | 100 → 0 | 100 → 0 |
| Timer controls | 100 → 0 | 100 → 0 |
| Scale reset control | 100 → 0 | 100 → 0 |
| Weight chart listener | 100 → 0 | 100 → 100 |

The tests also check the latest displayed weight, connection changes, drip
waiting and timer ticks. These are host widget rebuild counts, not device frame
times. Active charts deliberately keep receiving samples during recording.

## Water-plan control rebuilds (November 2026)

The expanded water plan retains its recipe controls and table while scale
readings and timer ticks update the next-pour subtitle. Its clock listens to
the timer independently. Recipe edits and session-state changes still rebuild
controls when their inputs change.

`water_plan_rebuild_test.dart` counts the bloom-ratio dropdown's actual element
rebuilds. The same driver on `87f2869` and after this change produces:

| Input | Dropdown rebuilds before → after |
| --- | ---: |
| 100 scale readings, one pump each | 100 → 0 |
| 100 one-second timer ticks | 100 → 0 |

The tests also verify elapsed time, next-pour targets, recipe changes, stop/reset
and invalid-duration feedback. Existing layout tests cover scrolling and the
expanded timer. These are host element counts, not Android frame timings.

## Guide chart repaint isolation (November 2026)

Pressure and flow guides now put the grid, axis labels and dashed reference in
a separate repaint boundary. The live trace and markers share the same axis
bounds. Background invalidation includes reference contents, axis bounds, unit,
theme and locale; labels release their TextPainter after painting.

`shot_guide_repaint_test.dart` uses Flutter's debug paint callback to count the
actual chart render objects during 100 within-axis updates. With the same driver
on `7ff2bef` and after this change:

| Layer | Paints before → after |
| --- | ---: |
| Background/reference | 100 → 0 |
| Live trace/markers | 100 → 100 |

The test also verifies that expanding either axis, changing the reference,
minimum scale, unit, theme or locale repaints the background. These host paint
counts do not measure device frame time. Page rebuilds are addressed separately.

## Pressure guide point conversion (November 2026)

`PressureGuideChart` reuses its mapped reference and trace points until their
source changes. PressureGuide owns immutable reference lists, and PressureTrace
returns immutable snapshots that change only when its recorded points change.
The current elapsed time, target and measured value still update on every build.

`pressure_guide_points_test.dart` compares mapped list identities over 100
timer-only frames using the same driver on `9e31356` and after this change:

| Mapped list | New copies before → after |
| --- | ---: |
| Reference | 100 → 0 |
| Trace | 100 → 0 |

The initial lists are excluded. New readings, replacement references and reset
still update their mapped points and targets. This measures list reuse, not
allocated bytes or Android frame time.

## Pressure guide page rebuilds (November 2026)

Pressure readings and the 50 ms refresh now notify the live readouts, chart
and clock instead of calling page-level setState. Timer controls and instructions
follow a separate value containing running/start-enabled state. The Scaffold,
app bar, title and static help stay outside those frequent builders.

`pressure_guide_rebuild_test.dart` emits 100 readings with 50 ms pumps while
recording, using the same driver on `4fb832a` and after this change:

| Element | Rebuilds before → after |
| --- | ---: |
| Page | 100 → 0 |
| App bar | 100 → 0 |
| Reference title | 100 → 0 |
| Timer toggle | 100 → 0 |

The live reading, elapsed timer and recorded trace still advance; stopping and
resetting update the controls and trace. Existing tests cover stale readings,
disconnection, navigation and both locales. These are host element counts,
not device frame timings.

## Flow guide page rebuilds (November 2026)

Flow readings and the 100 ms refresh now update live weight, time and readouts
through a notifier. Controls follow running/start-enabled/connection state;
static content stays outside these builders, and the formatter is reused.

The same `flow_guide_rebuild_test.dart` driver on `4e995bb` and after this change
emits 100 readings with 100 ms pumps while recording:

| Elements | Rebuilds per element before → after |
| --- | ---: |
| Page, app bar, reference title, timer toggle | 100 → 0 |

Flow, weight and elapsed time still advance; disconnection disables starting.
Existing tests cover stale data, reset, navigation and large text in both locales.
These are host element counts, not device frame timings.

## Home stock aggregation reuse (November 2026)

Home caches active coffees, stock totals, ordering, low-stock alerts and recipe
groups for a journal/freezer snapshot. Low-stock calculation runs once per
snapshot, and recipe cards use coffee-indexed groups. Changing either journal
data or the frozen-portion list replaces the cache. Date-sensitive week counts,
seasonal entries and freezer age remain outside it.

`home_stock_rebuild_test.dart` uses a read-counting coffee list with three coffees
and 100 parent-driven rebuilds without data changes. The same driver on `561ff65`
and after this change measures **900 → 0 coffee element reads**, excluding the
initial build. It also verifies freezer-only and journal updates, and advances
the date by eight days to check the rolling-week count without recalculating stock.
These are collection-access counts, not total screen work or device frame times.

## Retained journal tabs (November 2026)

Visited offscreen tabs retain their widget while journal data, methods, frozen
portions, hidden parameters, list options and equipment selection stay unchanged.
They receive updated inputs immediately. The selected tab still refreshes with
its parent and on return from another tab, preserving date-sensitive content.
Unvisited tabs remain unmounted through the existing lazy stack.

`journal_tab_rebuild_test.dart` opens all four tabs in the real app, keeps a
coffee search, then alternates History and Equipment 100 times. The same driver
on `4ef029a` and after this change measures **100 → 0 Home builds** and
**100 → 0 Beans builds**. It also inserts a coffee while both are hidden,
checks both receive the new snapshot, and verifies the search survives returning
to Beans. These are host widget-build counts, not device frame-time measurements.

## Reproduce the measurements

Use the Flutter and Dart versions pinned in the README. Run the host benchmarks
separately from the normal regression suite. The full stress matrix can take
tens of minutes, especially with 8,192-character notes:

```sh
flutter test --no-pub benchmark --concurrency=1 --reporter expanded
```

`journal_access_benchmark_test.dart` prints one `JOURNAL_AUDIT` JSON object per
operation. `drive_sync_export_benchmark_test.dart` prints
`DRIVE_EXPORT_BENCHMARK` records. The latter uses in-memory SQLite and also
checks preservation of inventory, curves, and photos.

For Android, use a test device and the isolated Patrol application ID
`com.caffeinateddev.holybeans.patrol` configured in the repository:

```sh
HOLYBEANS_PATROL_BUILD_TYPE=profile patrol test --profile \
  --target patrol_test/performance_audit_test.dart --device DEVICE_ID \
  --show-flutter-logs
```

Optional Dart defines select a subset: `AUDIT_SECTION=data,ui,media,startup,charts`
(default `all`), `AUDIT_FIXTURE=5000x2048` for access benchmarks,
`AUDIT_UI_FIXTURE=5000x2048` for UI scenarios and `AUDIT_RUN=label`
for records.
Use the CLI's `--dart-define=NAME=value` option for each. The November audit used
an offline Gradle invocation of the generated Patrol bundle because the CLI's
network dependency check stalled in this environment.

The device test refuses to run outside profile mode. It creates no paired
hardware or Drive account. It never sends commands to coffee equipment.
Its startup scenario requires a freshly cleared Patrol sandbox and exercises
the real `main()` against a synthetic journal in that sandbox.

Results are written to the test package's external files directory as
`performance-audit.jsonl`. Collect the file during the test because the Android
orchestrator can clear app data afterwards. The test leaves a 20-second
collection window after writing `audit_complete`. Do not change the application
ID to the personal or production app to run these tests.

For the separate cold-launch experiment, build a release APK with Gradle
`:app:assembleRelease -Ppatrol-enabled=true -Ptarget=lib/main.dart
-Ptarget-platform=android-arm64`. Verify its application ID is the isolated
Patrol ID before installing. Against that package, use `adb shell am force-stop
com.caffeinateddev.holybeans.patrol` before each `adb shell am start -W -n
com.caffeinateddev.holybeans.patrol/com.caffeinateddev.holybeans.MainActivity`.
Keep the first launch after clearing the test sandbox separate from later
samples. The audit waited two seconds after each force-stop and three seconds
after each launch. Raw observations are in `cold-launch.json` locally.

## What each measurement means

The access matrix contains 100, 1,000, 5,000, and 10,000 preparations, each with
empty notes and with 2,048-character note bodies. A final stress case
uses 10,000 preparations with 8,192-character note bodies. Notes are
distinct and contain accents. Ten percent of preparations are archived. There
are up to 250 coffees, all active: this deliberately stresses per-coffee work
and is not a model of everyone's normal inventory. Fixtures use fixed dates.

Database access uses a file and a background SQLite isolate, matching
`AppDatabase.open()`. Fixture generation is outside timed operations.
Queries are instrumented to count SELECTs and returned rows, including the
history reread after a single rating change or insertion.

Most operations have two warmups and nine measured repetitions. Search has
five measured repetitions; media operations specify their counts in the JSON.
Records retain individual samples, median, empirical p95, and extremes. With
five or nine samples, empirical p95 is the maximum; it is not a reliable fleet
tail-latency estimate or a release gate. Initial model loading and insertion
are individual observations.

The pagination experiment compares complete rows with a projection of six
fields, 50 at a time, with and without a temporary composite index. It verifies
that the first two cursor pages match the existing ordering, then drops the
index before measuring the existing model. This is an experiment, not a
complete pagination implementation: filtering, concurrent changes, all sort
directions, and timestamp ties still need production-level coverage.

The `search_*` experiment mirrors the baseline matching structure and measures
hits, accent-folded hits, and misses, using the normalization at the tested
revision. The `history_query_*` records exercise the production selection.
The exploratory alternative avoids splitting the
entire string into single-character strings. A separate equivalence test checks
accent handling, whitespace, combining marks, emoji, and 1,000 deterministic
combinations. Actual search rendering is also exercised on the device.
The metadata-first prototype preserves the original full-string fallback,
including matches spanning the boundary between metadata and notes.

The UI scenarios use the production widgets with 100, 5,000, and 10,000
preparations and notes. They cover history opening and scrolling, progressive
search input, statistics, ten detail open/close cycles, and bean scrolling with
synthetic photos. Frame records separate Dart build duration and raster
duration, using the display's reported refresh rate as the budget. Frames are
filtered by their monotonic vsync timestamps. `interactionAndSettleMs` includes
test automation and settling; it is not a raw touch-to-photon latency.

Memory checkpoints report process RSS and, when the VM service is available,
VM memory usage requested through the main isolate after GC. The VM's
[isolate groups share a heap](https://github.com/dart-lang/sdk/blob/main/runtime/docs/README.md),
so this is not exclusive per-isolate ownership accounting. RSS also includes
native allocations, other isolates, allocator capacity, and caches. It must not
be described as the Dart heap or interpreted as a leak by itself. UI checkpoints
before/after navigation, after unmount, and after image-cache clearing help
separate retained objects from intentional cache occupancy. GC requests are
outside timed operations. GC event counts concern the main isolate. CPU clock
ticks cover the process across the measured repetitions; they are not a CPU
utilization percentage.

Media scenarios cover 1.9 MP and 12 MP synthetic JPEGs, an eight-photo bounded
parallel batch, and export/ZIP/restore of 1,000 preparations with photos. They
assert decoded image dimensions and full backup/photo round-trip equality.
Gradient images are reproducible but do not represent every camera JPEG.

Startup invokes the real `main()` repeatedly with empty and 5,000-preparation
journals. It measures service initialization and the shell becoming loaded
within the existing process. It excludes Android process creation and Flutter
engine startup, and must not be advertised as a cold-launch measurement.

The chart scenario renders the production live extraction chart with 300,
3,000, and 10,000 initial points, then supplies 100 growing synthetic curves at
50 ms intervals. Harness version 5 additionally waits for the final asynchronous
readout to contain the entire input curve before ending the frame window.
This stresses chart rendering and includes fixture generation;
it does not measure Bluetooth transport or physical extraction accuracy.

## Audit record quality

The first implementation CI on `be92bad` completed with **1,698 Flutter tests
passed, seven skipped and zero failed**, plus successful native Android tests,
Python tooling checks, formatting and static analysis. The seven skips still
require private backup fixtures. See the
[complete validation run](https://github.com/Mancuerna/holybeans-public/actions/runs/41897984725).
Subsequent documentation-only commits retain the same source fingerprint.

Implementation regressions cover incremental subscriptions and cancellation,
transaction rollback, replacement imports, Unicode matching, stale worker
results, retained tab state, full-resolution curve statistics and bounded
polylines. Widget tests that open large curves use real asynchronous settling:
the simulated clock in ordinary `pumpAndSettle` cannot complete worker-isolate
futures. Both previously timing-out flows and a dedicated large-curve rendering
test pass without removing their data assertions. The final validation status
is recorded on [PR #16](https://github.com/Mancuerna/holybeans-public/pull/16).

The baseline Flutter suite completed with **1,671 passed, seven skipped, and zero
failed**. The seven skips require private real-backup fixtures that were not
configured. Python tooling tests passed (31), as did native Android JVM tests
(four). Final static analysis and documentation-link checks passed. The
corrected device instrumentation test passed all selected access,
UI, media, startup, and chart scenarios. The host access matrix and existing
export benchmarks passed their 12 cases; the separate search-equivalence test
passed on a fresh invocation. These checks cover the exercised scenarios, not
every possible hardware/account configuration.

Raw local evidence is under `artifacts/performance-audit/` (ignored by Git).
`device-baseline.jsonl` contains the original nine access fixtures.
`device-results.jsonl` contains the corrected follow-up, labeled
`harnessVersion: 2`, including a repeated 5,000-entry access fixture and UI,
media, startup, and chart scenarios.

The first device run stopped because Patrol's binding did not inject text via
`WidgetTester.enterText`. Its UI search records are invalid and are excluded
from findings. Version 2 uses Patrol's text helper and asserts the actual field
contents and missing-search result. Version 1 also counted pending warmup GC
events; do not use its GC counts as measured-repeat totals. Version 2 drains
the event queue before and after timed samples. GC event delivery remains an
asynchronous diagnostic, not a latency gate.

The first combined host benchmark run encountered a stale compilation after
the prototype source changed while the runner was active. The access/export
cases passed; a fresh prototype run passed afterwards. These harness issues
are recorded separately from production test failures.

## Scope and interpretation

Use a physical device for UI conclusions. Host test timings are useful for
investigating algorithms and verifying the harness, but debug/JIT execution,
host workload, and storage differ from an Android release. Keep device model,
OS, build mode, refresh rate, temperature, source revision, and fixture with
results. Avoid concurrent workloads on the measured device.

Do not assert universal speedups from this exploratory suite. Validate a chosen
change with alternating before/after runs on the same device, correctness tests,
and a release build before setting regression budgets. A second low-memory
device, large-journal process-cold launches, iOS, real Drive/network conditions,
sustained battery/thermal behavior, and physical BLE and printer sessions remain
separate validation work. Existing simulated
protocol tests do not substitute for those hardware sessions.

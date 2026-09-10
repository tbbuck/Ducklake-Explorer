# DuckLake Explorer — Milestones

> Status: **Draft** · 2026-09-10 · See [SPEC.md](./SPEC.md) for the full spec.

Phased, read-only throughout. The two centres of gravity — the **query workbench** and
the **metadata/time-travel explorer** — are weighted equally, so the plan alternates
between them (M2 workbench, M3–M4 metadata) after a shared browsing foundation (M1).
Remote/object-store catalogs and geometry land in M5, but the connection layer is
designed for them from M1.

Each milestone lists **Goal · Deliverables · Acceptance · Demo**. Every non-trivial
unit gets tests; commit per logical unit.

---

## M0 — Spike & scaffold  *(de-risk the engine link)* — ✅ done
**Goal:** prove Swift can drive the local `libduckdb` and read a DuckLake end-to-end.
- **Deliverables**
  - SwiftUI app skeleton (single window) + Xcode/SwiftPM project.
  - C-API bridge to `/opt/homebrew/opt/duckdb/lib/libduckdb.dylib` (module map / bridging
    header against `include/duckdb.h`); thin Swift wrapper: connect, query, iterate,
    interrupt.
  - Runtime `LOAD ducklake` (+ `spatial`), then: `ATTACH 'ducklake:…' (READ_ONLY)`, run a
    `SELECT`, and read `snapshots()` — printed to a scratch view.
  - **Test-fixture generator** (`Fixtures/`): builds a small lake with 11 snapshots,
    a partitioned + sorted table, a delete, schema evolution, and a `GEOMETRY` column.
- **Acceptance:** ✅ a query returns rows into Swift via the C API (6/6 `swift test` green);
  `ducklake`/`spatial` load from `~/.duckdb/extensions`; the app compiles, links libduckdb,
  and codesigns ad-hoc. Distribution bundling of libduckdb + extensions is deferred to M5.
- **Demo:** launch → attach fixture → see rows + snapshot list. *(Deferred: the visual UI
  is on hold pending a design direction; the scratch `ContentView` is a placeholder.)*

## M1 — Open & browse  *(shared foundation)*
**Goal:** a real connection flow and a schema tree.
- **Deliverables**
  - Connection UI: open local file, **recent connections**, read-only attach, clear error
    surfacing; connection abstraction with a seam for remote (M5).
  - Catalog → schema → table/view → column tree with types/nullability; tree search.
  - Surface `ducklake_settings()` (backend, extension version, data path).
- **Acceptance:** open the fixture and an externally-created lake; tree matches
  `information_schema`; a bad path yields a clean error, not a crash.
- **Demo:** open a lake, navigate to a column.

## M2 — Query workbench
**Goal:** read-only SQL with a fast grid.
- **Deliverables**
  - SQL editor: highlighting, schema/table/column completion, run / run-selection, **cancel**.
  - Virtualized `NSTableView`-backed results grid; streamed/windowed rows off the main
    thread; type-aware rendering; column sort; copy.
  - Query history; result export (CSV / Parquet / JSON / clipboard) via `COPY … TO`.
  - Read-only guard rejecting mutating statements.
- **Acceptance:** run joins/aggregations; cancel a long query mid-flight; grid stays
  responsive at ≥1M rows.
- **Demo:** write a query, run, sort, export.

## M3 — Table inspector
**Goal:** expose the physical layer.
- **Deliverables**
  - Per-table panel: schema, row count, size, partitioning, sort order.
  - **Files** view via `ducklake_list_files(...)`: data + delete files, sizes, row/row-group
    counts, inlined vs. flushed; click a data file to preview its Parquet.
  - Column statistics where recorded.
- **Acceptance:** file list and counts reconcile with the catalog for the fixture and a
  real lake; Parquet preview opens.
- **Demo:** inspect a partitioned table, open one of its data files.

## M4 — Snapshots & time travel
**Goal:** make history first-class.
- **Deliverables**
  - Snapshot list (`snapshots()`); select a snapshot as the **active view** (re-attach with
    `SNAPSHOT_VERSION`/`SNAPSHOT_TIME`), so browser + inspector reflect it.
  - Per-query time travel (`AT (VERSION/TIMESTAMP)`) from the workbench.
  - **Snapshot diff** (tables/schema/file/row deltas) and a per-table **schema-evolution**
    timeline.
- **Acceptance:** time-travel results match expected historic state on the fixture; diff
  correctly reports a known change between two snapshots.
- **Demo:** step back a snapshot; diff two snapshots.

## M5 — Remote, geometry & polish
**Goal:** close the stated scope and make it shippable.
- **Deliverables**
  - **Remote catalogs/data**: attach DuckDB/SQLite catalogs and/or data on `s3://`/`https://`
    read-only; credentials UI backed by **Keychain** → temporary DuckDB secrets
    (`httpfs`/`aws`).
  - **Geometry**: WKB→WKT, `GEOMETRY` detection, map preview (provider per SPEC §9.5).
  - Preferences (extension directory / bundling, default export format); app icon.
  - **Bundle `libduckdb` + extension binaries** into the app (fix the dylib install name,
    set `extension_directory`) so users need neither Homebrew nor a network install; then
    Developer-ID signing & notarization (SPEC §9.2–9.3).
- **Acceptance:** open a real S3-backed lake read-only with credentials; render a geometry
  column on a map; signed app launches on a clean machine **with no Homebrew/DuckDB installed**.
- **Demo:** open a remote lake, map a geometry, export a result.

---

### Backlog / post-v1 (explicitly out of scope now)
- Write support (DML/DDL, snapshot creation).
- DuckLake maintenance (compaction, expire/cleanup, orphan removal).
- Postgres/MySQL catalog backends.
- Cross-platform (iPad / non-Apple).

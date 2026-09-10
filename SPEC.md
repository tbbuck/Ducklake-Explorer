# DuckLake Explorer — Specification

> Status: **Draft** · 2026-09-10 · Target DuckDB **v1.5.5+**

A native macOS application for opening a **DuckLake** lakehouse, understanding its
structure and history, and querying it read-only. It aims to be to DuckLake what a
good database GUI is to Postgres — but with first-class treatment of the things
DuckLake makes uniquely visible: **snapshots, time travel, schema evolution, and the
Parquet file layout underneath a table**.

---

## 1. Vision

Point the app at a DuckLake catalog (a `.ducklake`/DuckDB or SQLite file, local or on
object storage) and get, in one window:

- the **shape** of the lake — catalogs, schemas, tables, columns, types;
- the **history** — every snapshot, what changed between them, how the schema evolved;
- the **physics** — which Parquet data files and delete files back each table, their
  sizes, partitioning, sort order, and statistics;
- a **query workbench** for read-only SQL, including time-travel queries, with a fast
  results grid and export.

It is a *reader and explorer*, never a mutator. See Non-goals.

## 2. Goals & Non-goals

**Goals**
- Open DuckLake catalogs backed by **DuckDB or SQLite**, whether **local or remote**
  (object storage / HTTPS), read-only.
- Make snapshots and time travel a primary, obvious feature — not an afterthought.
- Expose the file/stat layer (`ducklake_list_files`, catalog metadata) that a generic
  SQL client hides.
- A responsive SQL workbench that stays smooth on large result sets.
- First-class handling of `GEOMETRY` columns (the user works in geospatial daily).
- Faithful error reporting — surface DuckDB's own errors, never swallow them.

**Non-goals (v1)**
- **No writes.** No `INSERT`/`UPDATE`/`DELETE`, no DDL, no snapshot creation.
- **No maintenance.** No compaction (`ducklake_merge_adjacent_files`), snapshot
  expiry (`ducklake_expire_snapshots`), cleanup, or orphan-file deletion.
- **No Postgres/MySQL catalog backends** (DuckDB/SQLite only; `postgres_scanner`
  isn't even installed locally).
- **No bundled/forked DuckDB engine** — we link the locally installed library.
- Not cross-platform (macOS only), not a general-purpose SQL IDE, not a BI tool.

## 3. Users & primary use cases

Primary user: a data / geospatial / analytics engineer who already lives in DuckDB and
keeps data in DuckLake. Representative tasks:

1. "Open this lake and show me what's in it" — browse schema tree, read column types.
2. "How has this table changed?" — list snapshots, diff two, view schema evolution.
3. "What does this table physically look like?" — data files, delete files, sizes,
   partitions, sort order, inlined vs. flushed, column stats.
4. "Let me poke at it" — write and run read-only SQL, including `AT (VERSION/TIMESTAMP)`
   time travel; page through / export results.
5. "Show me the geometry" — decode WKB, preview a `GEOMETRY` column on a map.
6. "Do all of the above against a lake whose data lives on S3."

## 4. Domain glossary (DuckLake)

| Term | Meaning in this app |
|---|---|
| **Catalog** | The metadata database (DuckDB or SQLite file) that DuckLake reads. `ducklake_settings().catalog_type` ∈ {`duckdb`, `sqlite`} for us. |
| **Data path** | Where Parquet data files live (local dir or object-store prefix); from `ducklake_settings().data_path`. |
| **Data file** | A Parquet file holding table rows, referenced by the catalog. |
| **Delete file** | A Parquet file recording deleted row positions; *partial deletion files* carry a per-row snapshot column so time travel stays correct. |
| **Inlined data** | Small inserts stored directly in the catalog DB (below `DATA_INLINING_ROW_LIMIT`) before being flushed to Parquet. A table may have both inlined and file-backed rows. |
| **Snapshot** | A consistent version of the whole lake, identified by a **version** (integer) and a **timestamp**. Listed via `snapshots()`. |
| **Time travel** | Reading the lake as of a snapshot: per-query `FROM t AT (VERSION => n)` / `AT (TIMESTAMP => …)`, or at attach time via `(SNAPSHOT_VERSION n)` / `(SNAPSHOT_TIME '…')`. |
| **Schema evolution** | Column add/drop/rename/type changes recorded across snapshots. |
| **Secret** | DuckDB credential (e.g. `TYPE s3`) needed to reach remote catalog/data files. |

## 5. Functional requirements

### 5.1 Connect & attach
- Open a **local** catalog file (`.ducklake`/DuckDB or SQLite) via file picker; open a
  **remote** one by URL (`s3://…`, `https://…`) with an associated secret.
- All attaches are **read-only** and enforced as such:
  - DuckDB: `ATTACH 'ducklake:catalog.ducklake' AS lake (READ_ONLY);`
  - SQLite: `ATTACH 'ducklake:sqlite:catalog.sqlite' AS lake (READ_ONLY);`
  - Data path resolved from catalog settings, or overridable with `DATA_PATH`.
- Detect backend and surface `ducklake_settings()` (catalog_type, extension_version,
  data_path). Warn (don't crash) if the extension version is newer/older than the
  linked engine expects.
- **Recent connections** list; re-open with one click. Never persist secrets in plain
  text (see 6.4).
- Multiple catalogs attachable in one window (switch between lakes).

### 5.2 Catalog browser
- Tree: **catalog → schema → table/view → column** with types and nullability, driven
  by `information_schema` / `duckdb_*` views scoped to the attached lake.
- Optional **raw metadata mode**: browse the underlying `ducklake_*` catalog tables
  (snapshot, table, data_file, column, …) directly — the metadata *is* data here, and
  power users will want to see it.
- Search/filter the tree.

### 5.3 Table inspector
For a selected table:
- **Schema**: columns, types, nullability, defaults, sort order, partitioning.
- **Rows / size**: row count, total on-disk size, file count.
- **Files**: `ducklake_list_files(catalog, table[, schema, snapshot_version|snapshot_time])`
  → data files and delete files, each with path, size, row/row-group counts; distinguish
  **inlined** vs. **flushed**. Click a data file to preview its Parquet directly.
- **Statistics**: per-column min/max/null counts where the catalog records them.
- Everything is **snapshot-aware** — the inspector reflects the currently selected
  snapshot (see 5.4).

### 5.4 Snapshots & time travel
- **Snapshot list** from `snapshots()` — version, timestamp, and a change summary.
- Select a snapshot to make it the **active view**: the browser, inspector, and new
  queries all reflect the lake as of that snapshot (implemented by re-attaching with
  `SNAPSHOT_VERSION`/`SNAPSHOT_TIME`, and/or rewriting queries with `AT (...)`).
- **Snapshot diff**: pick two snapshots and see what changed — tables added/dropped,
  schema changes, and (where cheap) row/file deltas.
- **Schema-evolution timeline** for a table across snapshots.
- Per-query time travel from the workbench without changing the active snapshot.

### 5.5 Query workbench
- SQL editor: syntax highlighting, DuckDB-aware completion (schemas/tables/columns of
  attached lakes), multiple statements, comment toggling.
- **Run** and **Cancel** (via `duckdb_interrupt`); run selection or whole buffer.
- **Results grid**: virtualized, handles large / streamed result sets without freezing
  the UI; column sort, type-aware rendering, copy cell/row.
- Result tabs / query history.
- Read-only guard: reject statements that would mutate (defense-in-depth on top of the
  read-only attach).

### 5.6 Geometry & spatial
- Detect `GEOMETRY`/`GEOGRAPHY`/WKB columns; render as readable WKT and/or a summary,
  never a raw blob.
- **Map preview** of a geometry column / query result (provider TBD — see Open
  Questions; leaning MapLibre Native + MapTiler, honouring the tree's map prefs).

### 5.7 Export
- Export a result set or table (at the active snapshot) to **CSV / Parquet / JSON**,
  or copy to clipboard. Uses DuckDB `COPY … TO` under the hood.

## 6. Non-functional requirements

### 6.1 Performance & responsiveness
- The UI thread never blocks on DuckDB. All queries run off the main thread; results
  stream/window into the grid.
- Usable on large catalogs (thousands of tables) and large result sets (millions of
  rows) via virtualization and lazy loading.

### 6.2 Concurrency model
- A DuckDB **connection is not safe for concurrent use**: serialize access through a
  single actor/serial queue per connection; use a separate connection for cancellable
  long-running queries; cancel via `duckdb_interrupt`.

### 6.3 Error handling
- Per the tree standard: **return/surface errors, never log-and-continue.** DuckDB
  errors are shown to the user verbatim (with context), not swallowed. The only
  tolerated best-effort path is DEBUG logging for operations that don't affect
  correctness (e.g. a stats pre-fetch that's purely an optimisation).

### 6.4 Security & privacy
- Read-only by construction. No telemetry.
- Remote credentials handled as DuckDB **secrets**; store user-entered secrets in the
  **macOS Keychain** and materialise **temporary** DuckDB secrets per session rather
  than relying on DuckDB's on-disk persistent secret store.

## 7. Architecture

- **Engine**: link the **local** `libduckdb` in-process (confirmed at
  `/opt/homebrew/opt/duckdb/lib/libduckdb.dylib`, header at
  `/opt/homebrew/opt/duckdb/include/duckdb.h`, v1.5.5). Access via the C API through a
  small Swift wrapper — the `DuckDBKit` SPM package with a `CDuckDB` system module map
  (see `Package.swift`). This honours "use the locally installed DuckDB" while keeping
  typed, streaming, in-process results — no CLI subprocess, no `~/.duckdbrc`
  side-effects, no output parsing. The Homebrew dylib is built for macOS 26, which sets
  the deployment floor (see §8); distribution bundles its own copy (§9).
- **Extensions**: `ducklake` is required; `httpfs` + `aws` for remote; `spatial` for
  geometry; `sqlite_scanner` for SQLite catalogs. These are **loadable** (not baked
  into the dylib), installed under `~/.duckdb/extensions`. Dev builds may rely on the
  user's extension dir; **distribution must bundle pinned extension binaries** and set
  `extension_directory` (see Open Questions).
- **UI**: SwiftUI for structure/navigation; the **results grid uses an AppKit
  `NSTableView`** (via `NSViewRepresentable`) for virtualization SwiftUI's `Table`
  can't match at scale.
- **State**: an observable app/session model owns attached catalogs, the active
  snapshot, and query tasks. Queries are `async` tasks dispatched to the DB actor.

## 8. Constraints & dependencies

- DuckDB **≥ 1.5.5**, linked locally; extensions as above.
- macOS **26+** (Tahoe); **Apple Silicon first**. The floor is 26 because Homebrew's
  `libduckdb` is built for macOS 26 — matching it avoids any load-time version mismatch.
- Swift 6 + SwiftUI + a thin AppKit layer. Engine layer is the `DuckDBKit` SPM package;
  the app project is generated from `project.yml` by **XcodeGen** (the one build-tool
  dependency). No third-party runtime dependencies without cause.
- Test fixtures: a script-built sample DuckLake with multiple snapshots, a partitioned
  table, delete files, and a geometry column (created in M0, reused by all milestones).

## 9. Open questions / to confirm

1. **Backend scope wording** — confirmed reading: DuckDB/SQLite catalogs, *local or on
   object storage*, with credential handling; no Postgres/MySQL. If "remote" was meant
   as *data files only, catalog stays local*, we can narrow the connection UI.
2. **Distribution & sandbox** — ✅ resolved: **Developer-ID + notarized, non-sandboxed**
   (M5), which suits arbitrary file access, loadable extensions, and outbound S3.
3. **Bundling for distribution** — ship the app with its own pinned `libduckdb` *and*
   the `ducklake`/`httpfs`/`aws`/`spatial`/`sqlite_scanner` extension binaries (set
   `extension_directory`, fix the dylib install name), so end users need neither Homebrew
   nor a network install. Dev builds link Homebrew and use `~/.duckdb/extensions`.
4. **macOS minimum** — ✅ resolved: **macOS 26** (matches the Homebrew libduckdb build).
5. **Map provider** — MapLibre Native + MapTiler (matches tree map prefs) vs MapKit.
6. **Raw metadata browsing** — is the `ducklake_*` catalog-table view in v1 or later?

# DuckLake Explorer — UI component spec (Stratum → SwiftUI)

> Status: **Draft** · 2026-09-10 · Companion to [SPEC.md](./SPEC.md). Maps the
> **Stratum** design direction (prototyped as Artifacts) onto SwiftUI/AppKit
> components. One line per component: what it *is* and what it's *for*.

## Architecture anchors

- **Structure/nav:** SwiftUI on macOS 14+ (Observation framework). The results grid
  and SQL editor drop to **AppKit via `NSViewRepresentable`** (SPEC §7) — `NSTableView`
  virtualises at ≥1M rows where SwiftUI `Table` can't.
- **Theming:** the two palettes (limestone *day* / JetBrains-Islands *night*) live as
  **semantic colours in an Asset Catalog** (`Any`+`Dark` appearances), so system
  light/dark is honoured for free. A manual toggle just sets `.preferredColorScheme`.
- **Fonts:** bundle **Hanken Grotesk** (UI/display) and **JetBrains Mono** (data/SQL —
  pairs with the Islands dark theme); expose as `Font.stratumDisplay/.stratumUI/.stratumMono`.
- **Engine:** all DuckDB access flows through one **`actor` per connection**
  (SPEC §6.2); views bind to `@Observable` models, never touch the C API directly.

---

## Design system & shell

- **`DuckLakeExplorerApp: App`** — `@main` + `WindowGroup`; owns menu `Commands`. *Entry point.*
- **`AppModel` (`@Observable`)** — attached lakes, active snapshot, appearance override, open query tabs, running tasks. *Single source of truth, injected via `@Environment`.*
- **`ExplorerView`** — the main window: an outer `HStack` of `HistoryRail` + a `NavigationSplitView(sidebar: SchemaTree, detail: TableInspector/Workbench)`. *The three-pane Stratum layout.*
- **`Theme`** — semantic colour + type tokens read from the Asset Catalog. *Keeps every view on-palette in both appearances.*
- **`ThemeToggle`** — sun/moon control → `AppModel.appearanceOverride`. *Manual day/night; defaults to system.*
- **`SnapshotChip`** — the "as of v147" pill in toolbars. *Always shows the active time context.*

## Snapshot history — the stratigraphic log

- **`HistoryRail`** — `ScrollView` + `LazyVStack` of `SnapshotLamina` (newest first); scales to hundreds. *Browse history like a git log.*
- **`SnapshotLamina`** — one row: version, relative time, truncated `commit_message`, schema-change tag. *A single snapshot, collapsed.*
- **`SnapshotDetailCard`** — expands the selected lamina: `author`, timestamp, `changes` chips, `commit_extra_info`. *Full `snapshots()` metadata.*
- **`CoreSpine`** — the continuous teal depth-gradient behind the laminae with the active marker. *The "you are here in time" identity.*
- **`Snapshot` (model)** — `id, time, schemaVersion, changes, author, commitMessage, commitExtraInfo`. *Maps the `snapshots()` row.*

## Schema tree

- **`SchemaTree`** — `List(selection:)` + `OutlineGroup` over catalog → schema → table/view → column. *Navigate structure; drives the inspector.*
- **`ColumnRow`** — name + type badge + geometry `⌖` marker. *Column with type/nullability at a glance.*
- **`CatalogNode` (model)** — recursive tree node from `information_schema`/`duckdb_*`. *Backing data for the tree.*

## Table inspector — physical + schema

- **`TableInspector`** — header (name, partition/badges, row/size/file metrics) + `CoreSampleView` + `SchemaStatsTable`. *"What is this table, physically?"*
- **`CoreSampleView`** — stacked Parquet-file layers sized by `record_count`, delete file as an erosion line; drawn with `Canvas`. *Makes the file layout literal.*
- **`FileLegendRow`** — file path, rows, size, inlined/flushed/delete. *The legend beside the core.*
- **`DataFile` (model)** — from `ducklake_list_files` / `ducklake_data_file`. *One data or delete file.*
- **`SchemaStatsTable`** — column · explicit type · null% · `ColumnDistribution`. *Schema and stats together; explicit type names kept.*
- **`ColumnDistribution`** — type-adaptive mini-viz switching over the column type. *A type-aware column profile.*
  - **`HistogramView`** (numeric/timestamp), **`DistinctBar`** (varchar → distinct count), **`PercentTrueBar`** (boolean → % true), **`GeometryMix`** (geometry-type split). *One mark per type; `Canvas`/`Shape` drawn.*

## Query workbench & results grid

- **`QueryRail` / `WorkbenchView`** — SQL editor + Run/Cancel + result tabs (slim rail in the inspector, full view when query-first). *Read-only SQL incl. `AT (VERSION/TIMESTAMP)`.*
- **`SQLEditor`** — `NSViewRepresentable` over `NSTextView`: highlighting + schema/table/column completion. *The editor.*
- **`ResultsGrid`** — `NSViewRepresentable` over `NSTableView`; streamed, windowed rows, type-aware cells (numeric right-aligned, geometry → WKT + glyph). *Fast grid at ≥1M rows (SPEC §7).*
- **`QueryTask` (model)** — async run with `duckdb_interrupt` cancel, off the main thread. *Run/cancel without blocking the UI.*

## Snapshot diff

- **`SnapshotDiffView`** — two `SnapshotPicker`s (from/to) + `DiffSpine` + grouped `DiffSection`s. *Compare two snapshots.*
- **`SnapshotPicker`** — from/to selector showing version, time, author, message. *Choose the endpoints.*
- **`DiffSection` / `DiffRow`** — grouped Schema-evolution / Rows / Files, each row add · alter · delete with a count. *What changed, categorised.* Fed by `snapshots().changes`, `table_changes()`, and `ducklake_column` deltas.

## Connect & recent lakes

- **`ConnectView`** — launch window: `RecentLakesList` + `OpenCatalogPanel`. *The open flow.*
- **`RecentLakeCard`** — name, backend badge, path, `n snapshots · last opened`. *One-click reopen.* Bound to persisted `[RecentConnection]` (secrets never persisted here).
- **`OpenCatalogPanel`** — local file `fileImporter` + remote `Catalog URL` field + `DuckDBSecretField` + read-only note + Open. *Attach local or remote, read-only.*

## Storage access — DuckDB secret picker (credentials, v1)

- **`SecretPicker` (sheet)** — single-select `List` of `SecretRow` from `duckdb_secrets()`, scope-match highlight, footer create-hint + "Use & open". *v1 chooses **which DuckDB secret** to use; the app never enters or stores credentials.*
- **`SecretRow`** — name, type badge, provider, scope, persistence pill, "covers this lake" pill. *One secret at a glance.*
- **`DuckDBSecret` (model)** — `name, type, provider, persistent, storage, scope`. *Maps a `duckdb_secrets()` row.*
- **`DuckDBSecretField`** — the read-only summary on Connect that opens the picker. *Shows the chosen secret + scope.*

> Divergence from SPEC §6.4: v1 relies on DuckDB's own secret manager rather than a
> Keychain-entry form. Confirm and I'll fold this into SPEC §5.1/§6.4.

## Metadata mode — raw `ducklake_*` catalog tables

- **`MetadataBrowser`** — `CatalogTableList` sidebar + `CatalogTableGrid`. *"The metadata is data."*
- **`CatalogTableList` / `CatalogTableRow`** — grouped `ducklake_*` tables (Snapshots · Schema · Data files · Statistics · Tags·Settings) with row counts. *Pick a catalog table.*
- **`CatalogTableGrid`** — reuses `ResultsGrid` over `SELECT * FROM ducklake_data_file …`. *Browse a catalog table's rows.*

## Shared primitives

- **`Badge` / `TypeBadge` / `Pill` / `ChangeChip`** — small labels (backend, read-only, secret type, diff +/~/−). *Encode state and type in form, not just text.*
- **`PanelLabel`** — the mono section eyebrow with a hairline rule. *Section headers.*

# DuckLake Explorer

A native macOS app for opening a [DuckLake](https://ducklake.select) lakehouse and
exploring it read-only — schema, snapshots, time travel, the Parquet file layout, and
an ad-hoc SQL workbench. See **[SPEC.md](./SPEC.md)** and **[MILESTONES.md](./MILESTONES.md)**.

## Layout

- `Package.swift`, `Sources/DuckDBKit`, `Sources/CDuckDB` — the engine layer, an SPM
  package wrapping the locally-installed `libduckdb` (Homebrew, v1.5.5) via its C API.
  Headless-testable with `swift test`.
- `project.yml`, `Sources/App` — the SwiftUI macOS app (generated Xcode project via
  XcodeGen). Depends on the `DuckDBKit` product.
- `Fixtures/` — a committed sample DuckLake (`build_fixture.sh` rebuilds it).

## Prerequisites

- macOS 15+ (build machine currently macOS 26 / Xcode 26).
- Homebrew `duckdb` (provides `libduckdb.dylib` + headers): `brew install duckdb`.
- `brew install xcodegen`.

## Build & test

```sh
# Engine layer — fast, headless:
swift test

# Generate and build the app:
xcodegen generate
xcodebuild -project DuckLakeExplorer.xcodeproj -scheme DuckLakeExplorer build
open ~/Library/Developer/Xcode/DerivedData/DuckLakeExplorer-*/Build/Products/Debug/"DuckLake Explorer.app"
```

The `.xcodeproj` is generated (gitignored); edit `project.yml` and re-run `xcodegen generate`.

## Map basemap (MapTiler key)

The Map view renders [MapLibre GL](https://maplibre.org) tiles from
[MapTiler](https://www.maptiler.com), which needs an API key. **No key is committed.** To
render tiles, drop yours into an untracked config and regenerate:

```sh
echo 'MAPTILER_API_KEY = your_maptiler_key' > Config/maptiler.local.xcconfig
xcodegen generate
```

`Config/maptiler.local.xcconfig` is gitignored; the key flows `MAPTILER_API_KEY` →
`Info.plist` (`MapTilerAPIKey`) at build time → `MapConfig.swift` at runtime. Without a key
the app runs fine — the basemap tiles just don't load.

> Dev builds link Homebrew's `libduckdb` by absolute path and sign ad-hoc. Bundling the
> library + DuckLake extensions and Developer-ID signing/notarization are M5.

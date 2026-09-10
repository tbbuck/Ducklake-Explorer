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

> Dev builds link Homebrew's `libduckdb` by absolute path and sign ad-hoc. Bundling the
> library + DuckLake extensions and Developer-ID signing/notarization are M5.

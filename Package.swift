// swift-tools-version: 6.0
import PackageDescription

// DuckLakeCore: the engine layer. Wraps the official libduckdb release (v2.0.0) via its
// C API. Kept as an SPM package so it is testable headlessly with `swift test`; the
// macOS app (see project.yml) links the DuckDBKit product.
//
// scripts/fetch-duckdb.sh puts the library + header here. The dylib's install name is
// @rpath/libduckdb.dylib, so development builds need the rpath below;
// scripts/bundle-duckdb-engine.sh replaces it for distribution.
let duckdbLib = "\(Context.packageDirectory)/Vendor/duckdb"

let package = Package(
    name: "DuckLakeCore",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "DuckDBKit", targets: ["DuckDBKit"]),
    ],
    targets: [
        // System module exposing duckdb.h (see module.modulemap).
        .systemLibrary(name: "CDuckDB", path: "Sources/CDuckDB"),
        .target(
            name: "DuckDBKit",
            dependencies: ["CDuckDB"],
            linkerSettings: [
                .unsafeFlags(["-L\(duckdbLib)", "-lduckdb", "-Xlinker", "-rpath", "-Xlinker", duckdbLib]),
            ]
        ),
        .testTarget(
            name: "DuckDBKitTests",
            dependencies: ["DuckDBKit"]
        ),
    ]
)

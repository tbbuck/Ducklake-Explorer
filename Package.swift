// swift-tools-version: 6.0
import PackageDescription

// DuckLakeCore: the engine layer. Wraps the locally-installed libduckdb (Homebrew,
// v1.5.5) via its C API. Kept as an SPM package so it is testable headlessly with
// `swift test`; the macOS app (see project.yml) links the DuckDBKit product.
//
// Homebrew ships the library + headers here; the dylib's install name is absolute,
// so no rpath is needed for local development. Bundling for distribution is M5.
let duckdbLib = "/opt/homebrew/opt/duckdb/lib"

let package = Package(
    name: "DuckLakeCore",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "DuckDBKit", targets: ["DuckDBKit"]),
    ],
    targets: [
        // System module exposing duckdb.h (absolute path — see module.modulemap).
        .systemLibrary(name: "CDuckDB", path: "Sources/CDuckDB"),
        .target(
            name: "DuckDBKit",
            dependencies: ["CDuckDB"],
            linkerSettings: [
                .unsafeFlags(["-L\(duckdbLib)", "-lduckdb"]),
            ]
        ),
        .testTarget(
            name: "DuckDBKitTests",
            dependencies: ["DuckDBKit"]
        ),
    ]
)

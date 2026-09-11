import Foundation
import DuckDBKit

/// Where the packaged app keeps DuckDB's extensions, and how it configures the engine.
///
/// The `.duckdb_extension` files can't be bundled — their metadata+signature footer isn't
/// notarizable, and DuckDB confirms signing dynamically-loaded extensions isn't currently
/// possible (duckdb/duckdb#16926). So a packaged build points `extension_directory` at a
/// per-user Application Support folder and lets DuckDB autoinstall ducklake/spatial/httpfs/
/// aws/sqlite_scanner there on first use (loaded under the disable-library-validation
/// entitlement). Dev/unbundled builds return nil and fall back to the engine's default
/// `~/.duckdb`, which already has them.
enum EngineSupport {
    /// A writable per-user extension directory for the packaged app; nil in dev/unbundled builds.
    static func extensionDirectory() -> String? {
        // "Packaged" = we shipped our own libduckdb alongside the app.
        let bundledLibrary = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Frameworks/libduckdb.dylib")
        guard FileManager.default.fileExists(atPath: bundledLibrary.path) else { return nil }
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let directory = support.appendingPathComponent(
            "DuckLake Explorer/duckdb-extensions", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        return directory.path
    }

    /// Engine config for this context. A packaged build pins `extension_directory` to the
    /// per-user folder above; dev uses the default. Autoinstall and DuckDB's own signature
    /// check both stay on — the fetched extensions are DuckDB-signed, so nothing is loaded
    /// unsigned.
    static func config() -> DuckDBConfig {
        extensionDirectory().map { DuckDBConfig(extensionDirectory: $0) } ?? DuckDBConfig()
    }
}

/// Where a DuckLake catalog lives. The `attachTarget` builds the `ducklake:` connection
/// string; this is the seam where remote (object-store) catalogs plug in — the SQL is the
/// same shape, they just need `httpfs`/`aws` loaded and a secret (M5).
public enum LakeSource: Sendable, Equatable {
    /// A DuckDB-backed catalog file (`*.ducklake`), local path or remote URI.
    case duckDBFile(String)
    /// A SQLite-backed catalog file, local path or remote URI.
    case sqliteFile(String)
    /// A catalog whose `ducklake:` target you supply verbatim (advanced/escape hatch).
    case raw(String)

    public var attachTarget: String {
        switch self {
        case .duckDBFile(let p): return "ducklake:\(Self.escape(p))"
        case .sqliteFile(let p): return "ducklake:sqlite:\(Self.escape(p))"
        case .raw(let t):        return Self.escape(t)
        }
    }

    /// SQL to attach the *underlying* catalog database (not via DuckLake) read-only, so the
    /// raw `ducklake_*` metadata tables (column stats, etc.) can be queried. Nil for `.raw`.
    public func rawCatalogAttach(alias: String) -> String? {
        switch self {
        case .duckDBFile(let p): return "ATTACH '\(Self.escape(p))' AS \(alias) (READ_ONLY);"
        case .sqliteFile(let p): return "ATTACH 'sqlite:\(Self.escape(p))' AS \(alias) (READ_ONLY);"
        case .raw:               return nil
        }
    }

    static func escape(_ s: String) -> String {
        var out = ""
        for ch in s { out += ch == "'" ? "''" : String(ch) }
        return out
    }
}

/// A read-only DuckLake session: owns a DuckDB connection behind an actor so all queries
/// run off the main thread and serialised, while `cancel()` can interrupt an in-flight
/// query from any task.
///
/// This is the M1/M2 plumbing; the (placeholder) M0 UI still drives `DuckDB` directly.
public actor LakeSession {
    /// `nonisolated` so `cancel()` can reach `interrupt()` without hopping onto the actor
    /// (which is busy running the query). `DuckDB` is `@unchecked Sendable`; every method
    /// other than `interrupt()` is only ever called from this actor's isolation.
    private nonisolated let db: DuckDB
    private var source: LakeSource?
    private var alias = "lake"

    public init(config: DuckDBConfig = .init()) throws {
        db = try DuckDB(config: config)
    }

    /// Installs (if needed) and loads the extensions every lake needs. `ducklake` and `spatial`
    /// are required; the remote (`httpfs`/`aws`) and SQLite-catalog (`sqlite_scanner`) extensions
    /// are best-effort, so a machine without them can still open local DuckDB lakes.
    ///
    /// `INSTALL` resolves each from the engine's `extension_directory`, fetching from DuckDB's
    /// repo only when it isn't already cached there — so a packaged app's first run downloads
    /// them into its per-user directory, while dev builds and tests (whose `~/.duckdb` already
    /// has them) do no network I/O. `LOAD` then loads the cached copy.
    public func loadCoreExtensions() throws {
        func ensure(_ name: String, required: Bool) throws {
            if required {
                try db.run("INSTALL \(name);")
                try db.run("LOAD \(name);")
            } else {
                _ = try? db.run("INSTALL \(name);")
                _ = try? db.run("LOAD \(name);")
            }
        }
        try ensure("ducklake", required: true)
        try ensure("spatial", required: true)
        try ensure("httpfs", required: false)
        try ensure("aws", required: false)
        try ensure("sqlite_scanner", required: false)
    }

    /// Attaches a catalog READ-ONLY under `alias`, optionally making it the active catalog.
    @discardableResult
    public func attach(_ source: LakeSource, as alias: String = "lake", activate: Bool = true) throws -> QueryResult {
        self.source = source
        self.alias = alias
        let result = try db.run("ATTACH '\(source.attachTarget)' AS \(alias) (READ_ONLY);")
        if activate { try db.run("USE \(alias);") }
        // Best-effort: attach the raw catalog DB for column stats / metadata browsing. This is
        // a pure enrichment — if it fails, the core read-only exploration is unaffected.
        if let rawAttach = source.rawCatalogAttach(alias: "\(alias)_meta") {
            _ = try? db.run(rawAttach)
        }
        return result
    }

    /// Runs a read-only query, optionally capping collected rows. Throws `CancellationError`
    /// without touching the engine if the calling task was cancelled before the actor reached
    /// it — so a query superseded while queued behind another never actually runs.
    @discardableResult
    public func query(_ sql: String, maxRows: Int? = nil) throws -> QueryResult {
        try Task.checkCancellation()
        return try db.run(sql, maxRows: maxRows)
    }

    /// Re-attaches the lake as of `version` (nil = latest) so schema, files, and queries all
    /// reflect that snapshot. The raw metadata catalog stays attached (it spans all versions).
    public func timeTravel(to version: Int64?) throws {
        guard let source else { return }
        try db.run("USE memory;")
        try db.run("DETACH \(alias);")
        let options = version.map { "READ_ONLY, SNAPSHOT_VERSION \($0)" } ?? "READ_ONLY"
        try db.run("ATTACH '\(source.attachTarget)' AS \(alias) (\(options));")
        try db.run("USE \(alias);")
    }

    /// Cancels the query currently executing on this session. Safe to call from any task
    /// while a `query` is in flight (it calls the thread-safe `duckdb_interrupt`).
    public nonisolated func cancel() {
        db.interrupt()
    }
}

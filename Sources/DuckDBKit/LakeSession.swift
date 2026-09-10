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

    public init() throws {
        db = try DuckDB()
    }

    /// Loads the extensions every lake needs: `ducklake` (required) and `spatial` (geometry).
    public func loadCoreExtensions() throws {
        try db.run("LOAD ducklake;")
        try db.run("LOAD spatial;")
    }

    /// Attaches a catalog READ-ONLY under `alias`, optionally making it the active catalog.
    @discardableResult
    public func attach(_ source: LakeSource, as alias: String = "lake", activate: Bool = true) throws -> QueryResult {
        let result = try db.run("ATTACH '\(source.attachTarget)' AS \(alias) (READ_ONLY);")
        if activate { try db.run("USE \(alias);") }
        return result
    }

    /// Runs a read-only query, optionally capping collected rows.
    @discardableResult
    public func query(_ sql: String, maxRows: Int? = nil) throws -> QueryResult {
        try db.run(sql, maxRows: maxRows)
    }

    /// Cancels the query currently executing on this session. Safe to call from any task
    /// while a `query` is in flight (it calls the thread-safe `duckdb_interrupt`).
    public nonisolated func cancel() {
        db.interrupt()
    }
}

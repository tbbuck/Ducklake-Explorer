import CDuckDB
import Foundation

/// An error surfaced by DuckDB. We never swallow these — the underlying engine
/// message is carried through verbatim (see the project's error-handling rule).
public enum DuckError: Error, CustomStringConvertible {
    case open(String)
    case connect(String)
    case query(sql: String, message: String)

    public var description: String {
        switch self {
        case .open(let m):    return "DuckDB open failed: \(m)"
        case .connect(let m): return "DuckDB connect failed: \(m)"
        case .query(let sql, let m):
            return "DuckDB query failed: \(m)\n  SQL: \(sql)"
        }
    }
}

/// A materialised query result, stringified. This is deliberately simple for the
/// M0 spike; the query workbench (M2) will move to the columnar `duckdb_fetch_chunk`
/// API for typed, streamed, virtualised results.
public struct QueryResult: Sendable {
    public let columns: [String]
    public let rows: [[String?]]

    public var rowCount: Int { rows.count }

    /// The first cell of the first row — handy for `SELECT count(*)`-style probes.
    public var scalar: String? { rows.first?.first ?? nil }
}

/// A thin, in-process wrapper over the locally-linked libduckdb.
///
/// Not thread-safe: a `duckdb_connection` must not be used concurrently. For M0
/// it is driven from a single thread; M2 introduces a serial actor around it and
/// uses `interrupt()` for cancellation.
public final class DuckDB {
    private var db: duckdb_database?
    private var conn: duckdb_connection?

    /// Opens a database. `path` nil (the default) opens an in-memory database,
    /// which is what we use before `ATTACH`-ing a DuckLake catalog.
    public init(path: String? = nil) throws {
        var err: UnsafeMutablePointer<CChar>?
        let state: duckdb_state = {
            if let path {
                return path.withCString { duckdb_open_ext($0, &db, nil, &err) }
            }
            return duckdb_open_ext(nil, &db, nil, &err)
        }()
        if state != DuckDBSuccess {
            let message = err.map { String(cString: $0) } ?? "unknown error"
            if let err { duckdb_free(err) }
            throw DuckError.open(message)
        }
        if duckdb_connect(db, &conn) != DuckDBSuccess {
            duckdb_close(&db)
            throw DuckError.connect("could not open a connection")
        }
    }

    deinit {
        if conn != nil { duckdb_disconnect(&conn) }
        if db != nil { duckdb_close(&db) }
    }

    /// Runs one SQL statement and returns its (materialised) result.
    @discardableResult
    public func run(_ sql: String) throws -> QueryResult {
        var result = duckdb_result()
        let state = sql.withCString { duckdb_query(conn, $0, &result) }
        defer { duckdb_destroy_result(&result) }

        if state != DuckDBSuccess {
            let message = duckdb_result_error(&result).map { String(cString: $0) } ?? "unknown error"
            throw DuckError.query(sql: sql, message: message)
        }

        let columnCount = duckdb_column_count(&result)
        var columns = [String]()
        columns.reserveCapacity(Int(columnCount))
        for col in 0..<columnCount {
            columns.append(String(cString: duckdb_column_name(&result, col)))
        }

        let rowCount = duckdb_row_count(&result)
        var rows = [[String?]]()
        rows.reserveCapacity(Int(rowCount))
        for row in 0..<rowCount {
            var cells = [String?]()
            cells.reserveCapacity(Int(columnCount))
            for col in 0..<columnCount {
                if let cString = duckdb_value_varchar(&result, col, row) {
                    cells.append(String(cString: cString))
                    duckdb_free(cString)
                } else {
                    cells.append(nil)
                }
            }
            rows.append(cells)
        }
        return QueryResult(columns: columns, rows: rows)
    }

    /// Requests cancellation of the currently-running query on this connection.
    public func interrupt() {
        if conn != nil { duckdb_interrupt(conn) }
    }
}

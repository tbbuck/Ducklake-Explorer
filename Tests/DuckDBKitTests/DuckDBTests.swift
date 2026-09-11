import XCTest
import Foundation
import DuckDBKit

/// Low-level wrapper tests: prove the Swift wrapper drives the locally-linked libduckdb,
/// loads DuckLake + spatial, attaches the sample lake read-only, and decodes typed values
/// from the engine's native data chunks.
final class DuckDBTests: XCTestCase {

    /// Absolute path to the committed fixture, derived from this file's location so it
    /// resolves regardless of the test runner's working directory.
    private var fixturePath: String { TestFixture.path }

    private func openFixture() throws -> DuckDB {
        let db = try DuckDB()
        // INSTALL first so a clean machine (e.g. CI) without pre-installed extensions bootstraps
        // them from DuckDB's repo; a no-op once cached.
        try db.run("INSTALL ducklake;")
        try db.run("LOAD ducklake;")
        try db.run("INSTALL spatial;")
        try db.run("LOAD spatial;")
        // Override the fixture's relative stored data_path with its absolute location, so reads
        // resolve regardless of the test runner's working directory.
        try db.run("""
            ATTACH 'ducklake:\(fixturePath)' AS lake
                (READ_ONLY, DATA_PATH '\(TestFixture.dataPath)', OVERRIDE_DATA_PATH true);
            """)
        try db.run("USE lake;")
        return db
    }

    func testAttachAndReadCurrentState() throws {
        let db = try openFixture()
        XCTAssertEqual(try db.run("SELECT count(*) FROM observations;").scalarString, "5")
        XCTAssertEqual(try db.run("SELECT count(*) FROM regions;").scalarString, "3")
    }

    func testSnapshotsListed() throws {
        let db = try openFixture()
        XCTAssertEqual(try db.run("SELECT count(*) FROM ducklake_snapshots('lake');").scalarString, "11")
    }

    func testTimeTravelToEarlierVersion() throws {
        let db = try openFixture()
        // Snapshot 4 is the first insert batch (4 rows), before the later delete.
        XCTAssertEqual(
            try db.run("SELECT count(*) FROM observations AT (VERSION => 4);").scalarString, "4")
    }

    func testGeometryDecodesToWKT() throws {
        let db = try openFixture()
        let wkt = try db.run(
            "SELECT ST_AsText(geom) FROM observations ORDER BY id LIMIT 1;").scalarString
        XCTAssertEqual(wkt, "POINT (-1.55 53.8)")
    }

    func testTypedColumnsAndValues() throws {
        let db = try openFixture()
        let result = try db.run(
            "SELECT id, species, recorded_at FROM observations ORDER BY id LIMIT 1;")
        XCTAssertEqual(result.columns.map(\.type), [.integer, .varchar, .timestamp])
        XCTAssertEqual(result.rows.first, [.int(1), .string("Vulpes vulpes"), .string("2026-01-05 08:15:00")])
    }

    func testFileLayerIsQueryable() throws {
        let db = try openFixture()
        let files = try db.run("SELECT * FROM ducklake_list_files('lake', 'observations');")
        XCTAssertGreaterThan(files.rowCount, 0)
        XCTAssertTrue(files.columnNames.contains("data_file"))
    }

    func testErrorsAreSurfacedNotSwallowed() throws {
        let db = try openFixture()
        XCTAssertThrowsError(try db.run("SELECT * FROM table_that_does_not_exist;")) { error in
            XCTAssertTrue(String(describing: error).contains("does_not_exist"))
        }
    }

    /// Exercises the per-type decoders end-to-end, including exact HUGEINT/DECIMAL via
    /// Int128 and temporal formatting.
    func testScalarTypeDecoding() throws {
        let db = try DuckDB()
        let r = try db.run("""
            SELECT
                TRUE                                   AS b,
                CAST(-42 AS INTEGER)                   AS i,
                CAST(18446744073709551615 AS UBIGINT)  AS u,
                CAST(3.5 AS DOUBLE)                    AS d,
                'hi'                                   AS s,
                CAST(123456789012345678901234 AS HUGEINT) AS h,
                CAST(1234.56 AS DECIMAL(10,2))         AS dec,
                DATE '2026-01-05'                      AS dt,
                TIMESTAMP '2026-01-05 08:15:00'        AS ts,
                NULL::INTEGER                          AS n;
            """)
        XCTAssertEqual(r.rows[0][0], .bool(true))
        XCTAssertEqual(r.rows[0][1], .int(-42))
        XCTAssertEqual(r.rows[0][2], .uint(UInt64.max))
        XCTAssertEqual(r.rows[0][3], .double(3.5))
        XCTAssertEqual(r.rows[0][4], .string("hi"))
        XCTAssertEqual(r.rows[0][5], .string("123456789012345678901234"))
        XCTAssertEqual(r.rows[0][6], .string("1234.56"))
        XCTAssertEqual(r.rows[0][7], .string("2026-01-05"))
        XCTAssertEqual(r.rows[0][8], .string("2026-01-05 08:15:00"))
        XCTAssertEqual(r.rows[0][9], .null)
    }

    /// A result spanning multiple data chunks (>2048 rows) must decode fully.
    func testMultiChunkResult() throws {
        let db = try DuckDB()
        let r = try db.run("SELECT i FROM range(5000) t(i);")
        XCTAssertEqual(r.rowCount, 5000)
        XCTAssertEqual(r.rows.first, [.int(0)])
        XCTAssertEqual(r.rows.last, [.int(4999)])
    }

    func testMaxRowsCaps() throws {
        let db = try DuckDB()
        let r = try db.run("SELECT i FROM range(5000) t(i);", maxRows: 10)
        XCTAssertEqual(r.rowCount, 10)
    }

    // MARK: - Startup configuration

    /// The bundle depends on startup-only flags reaching the engine through `duckdb_open_ext`.
    /// The `.app` path itself can't be unit-tested, but the config plumbing can: prove the flags
    /// round-trip and the connection still runs queries.
    func testOpensWithStartupConfig() throws {
        let db = try DuckDB(config: DuckDBConfig(allowUnsignedExtensions: true, disableAutoinstall: true))
        XCTAssertEqual(try db.run("SELECT 42;").scalarString, "42")
        XCTAssertEqual(try db.run("SELECT current_setting('allow_unsigned_extensions');").scalarString, "true")
        XCTAssertEqual(try db.run("SELECT current_setting('autoinstall_known_extensions');").scalarString, "false")
    }

    /// A populated `extensionDirectory` is applied as the engine's `extension_directory`.
    func testExtensionDirectoryConfigApplied() throws {
        let dir = NSTemporaryDirectory() + "ducklake-ext-test"
        let db = try DuckDB(config: DuckDBConfig(extensionDirectory: dir))
        let applied = try XCTUnwrap(db.run("SELECT current_setting('extension_directory');").scalarString)
        XCTAssertTrue(applied.hasSuffix("ducklake-ext-test"), "extension_directory not applied: \(applied)")
    }

    /// The default (empty) config must remain byte-for-byte the historical open path.
    func testDefaultConfigIsUnchanged() throws {
        let db = try DuckDB()
        XCTAssertEqual(try db.run("SELECT 1;").scalarString, "1")
    }

    // MARK: - Secret creation

    /// The CREATE SECRET statement emits only non-empty fields, escapes string values, quotes the
    /// name, and folds multiple scopes into a list.
    func testSecretStatementShape() {
        let one = DuckDBSecret(name: "my s3", keyID: "AKIA", secret: "p'w", endpoint: "e.com",
                               region: "us-east-1", urlStyle: "path", scope: "s3://b/")
        XCTAssertEqual(one.statement(persistent: true),
            #"CREATE PERSISTENT SECRET "my s3" (TYPE s3, KEY_ID 'AKIA', SECRET 'p''w', ENDPOINT 'e.com', REGION 'us-east-1', URL_STYLE 'path', SCOPE 's3://b/');"#)
        let multi = DuckDBSecret(keyID: "K", secret: "S", scope: "s3://a/, s3://b/")
        XCTAssertEqual(multi.statement(persistent: false),
            #"CREATE SECRET (TYPE s3, KEY_ID 'K', SECRET 'S', SCOPE ('s3://a/', 's3://b/'));"#)
    }

    /// The generated statement is valid DuckDB SQL and actually registers a secret.
    func testCreateSecretRunsInDuckDB() throws {
        let db = try DuckDB()
        try db.run("INSTALL httpfs;")
        try db.run("LOAD httpfs;")
        let s = DuckDBSecret(name: "test_s3", keyID: "AKIA", secret: "shh", region: "us-east-1",
                             urlStyle: "path", scope: "s3://bucket/")
        try db.run(s.statement(persistent: false))
        let r = try db.run("SELECT name FROM duckdb_secrets() WHERE name = 'test_s3';")
        XCTAssertEqual(r.rows.first?.first, .string("test_s3"))
    }
}

/// Shared fixture path, resolved from this file's location.
enum TestFixture {
    static var path: String {
        URL(fileURLWithPath: #filePath)          // .../Tests/DuckDBKitTests/DuckDBTests.swift
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/sample.ducklake")
            .path
    }

    /// Absolute data dir for the fixture (`…/sample.ducklake.files`). The committed catalog
    /// stores this path relative, so tests pass it as an explicit DATA_PATH override.
    static var dataPath: String { path + ".files" }
}

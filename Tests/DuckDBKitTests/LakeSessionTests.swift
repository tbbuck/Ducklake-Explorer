import XCTest
import DuckDBKit

/// Exercises the async session layer: attach + query run off the calling thread through
/// the actor, results come back typed, and the local/remote `LakeSource` seam builds the
/// right `ducklake:` targets.
final class LakeSessionTests: XCTestCase {

    private func openSession() async throws -> LakeSession {
        let session = try LakeSession()
        try await session.loadCoreExtensions()
        try await session.attach(.duckDBFile(TestFixture.path), dataPath: TestFixture.dataPath)
        return session
    }

    func testAttachAndTypedQuery() async throws {
        let session = try await openSession()
        let r = try await session.query("SELECT id, species, recorded_at FROM observations ORDER BY id LIMIT 1;")
        XCTAssertEqual(r.columns.map(\.type), [.integer, .varchar, .timestamp])
        XCTAssertEqual(r.rows.first, [.int(1), .string("Vulpes vulpes"), .string("2026-01-05 08:15:00")])
    }

    func testTimeTravelViaSession() async throws {
        let session = try await openSession()
        let r = try await session.query("SELECT count(*) FROM observations AT (VERSION => 4);")
        XCTAssertEqual(r.scalarString, "4")
    }

    func testTimeTravelReattach() async throws {
        let session = try await openSession()
        var count = try await session.query("SELECT count(*) FROM observations;").scalarString
        XCTAssertEqual(count, "5")
        try await session.timeTravel(to: 4)   // first insert batch
        count = try await session.query("SELECT count(*) FROM observations;").scalarString
        XCTAssertEqual(count, "4")
        try await session.timeTravel(to: nil)  // back to latest
        count = try await session.query("SELECT count(*) FROM observations;").scalarString
        XCTAssertEqual(count, "5")
    }

    func testMaxRowsCaps() async throws {
        let session = try await openSession()
        let r = try await session.query("SELECT * FROM observations;", maxRows: 2)
        XCTAssertEqual(r.rowCount, 2)
    }

    func testCancelIsCallableAndSessionRecovers() async throws {
        let session = try await openSession()
        session.cancel()  // no query in flight — must be a safe no-op
        let r = try await session.query("SELECT count(*) FROM observations;")
        XCTAssertEqual(r.scalarString, "5")
    }

    // MARK: - Catalog formats

    /// Both DuckLake formats the app must read: new lakes, and ones from before the upgrade.
    private func formats() -> [(version: String, path: String, dataPath: String)] {
        [("1.1", TestFixture.path, TestFixture.dataPath),
         ("1.0", TestFixture.legacyPath, TestFixture.legacyDataPath)]
    }

    private func catalogVersion(_ session: LakeSession) async throws -> String? {
        try await session.query("SELECT value FROM lake.options() WHERE option_name = 'version';").scalarString
    }

    /// Reads a lake of each format, across time travel, without migrating it: this app is
    /// read-only, so an older catalog must stay at its original version.
    func testReadsEachCatalogFormatWithoutMigrating() async throws {
        for format in formats() {
            let session = try LakeSession()
            try await session.loadCoreExtensions()
            try await session.attach(.duckDBFile(format.path), dataPath: format.dataPath)

            var version = try await catalogVersion(session)
            XCTAssertEqual(version, format.version)
            let snapshots = try await session.query("SELECT count(*) FROM ducklake_snapshots('lake');")
            XCTAssertEqual(snapshots.scalarString, "11", format.version)
            let wkt = try await session.query("SELECT ST_AsText(geom) FROM observations ORDER BY id LIMIT 1;")
            XCTAssertEqual(wkt.scalarString, "POINT (-1.55 53.8)", format.version)

            try await session.timeTravel(to: 4)
            let earlier = try await session.query("SELECT count(*) FROM observations;")
            XCTAssertEqual(earlier.scalarString, "4", format.version)
            version = try await catalogVersion(session)
            XCTAssertEqual(version, format.version)
        }
    }

    /// The Snapshot Diff and Meta views query the raw catalog tables. Attaching them is
    /// best-effort, and those views swallow query errors, so a schema change would only show
    /// up as empty panes: pin the shape of those queries for each format.
    func testRawCatalogQueriesOnEachFormat() async throws {
        for format in formats() {
            let session = try LakeSession()
            try await session.loadCoreExtensions()
            try await session.attach(.duckDBFile(format.path), dataPath: format.dataPath)

            let tables = try await session.query("""
                SELECT table_name FROM lake_meta.ducklake_table
                WHERE begin_snapshot <= 10 AND (end_snapshot IS NULL OR end_snapshot > 10)
                ORDER BY table_name;
                """)
            XCTAssertEqual(tables.rows.map { $0[0] }, [.string("observations"), .string("regions")], format.version)

            let columns = try await session.query("""
                SELECT t.table_name || '.' || c.column_name AS col, c.column_type
                FROM lake_meta.ducklake_column c
                JOIN lake_meta.ducklake_table t
                  ON t.table_id = c.table_id
                 AND t.begin_snapshot <= 10 AND (t.end_snapshot IS NULL OR t.end_snapshot > 10)
                WHERE c.begin_snapshot <= 10 AND (c.end_snapshot IS NULL OR c.end_snapshot > 10)
                  AND c.column_name = 'observer';
                """)
            XCTAssertEqual(columns.rows.first?[0], .string("observations.observer"), format.version)

            let listed = try await session.query("""
                SELECT table_name, estimated_size
                FROM duckdb_tables()
                WHERE database_name = 'lake_meta' AND table_name = 'ducklake_snapshot';
                """)
            XCTAssertEqual(listed.rowCount, 1, format.version)
        }
    }

    func testSourceTargets() {
        XCTAssertEqual(LakeSource.duckDBFile("/tmp/a.ducklake").attachTarget, "ducklake:/tmp/a.ducklake")
        XCTAssertEqual(LakeSource.sqliteFile("/tmp/a.sqlite").attachTarget, "ducklake:sqlite:/tmp/a.sqlite")
        XCTAssertEqual(LakeSource.duckDBFile("a'b.ducklake").attachTarget, "ducklake:a''b.ducklake")
    }
}

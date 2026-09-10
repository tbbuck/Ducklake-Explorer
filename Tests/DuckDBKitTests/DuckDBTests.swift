import XCTest
import DuckDBKit

/// M0 acceptance: prove the Swift wrapper can drive the locally-linked libduckdb,
/// load the DuckLake + spatial extensions, attach the sample lake READ_ONLY, and
/// read data, snapshots, time-travel, geometry, and the file layer.
final class DuckDBTests: XCTestCase {

    /// Absolute path to the committed fixture, derived from this file's location
    /// so it resolves regardless of the test runner's working directory.
    private var fixturePath: String {
        URL(fileURLWithPath: #filePath)          // .../Tests/DuckDBKitTests/DuckDBTests.swift
            .deletingLastPathComponent()          // .../Tests/DuckDBKitTests
            .deletingLastPathComponent()          // .../Tests
            .deletingLastPathComponent()          // package root
            .appendingPathComponent("Fixtures/sample.ducklake")
            .path
    }

    /// Opens the fixture read-only with the DuckLake + spatial extensions loaded.
    private func openFixture() throws -> DuckDB {
        let db = try DuckDB()
        try db.run("LOAD ducklake;")
        try db.run("LOAD spatial;")
        try db.run("ATTACH 'ducklake:\(fixturePath)' AS lake (READ_ONLY);")
        try db.run("USE lake;")
        return db
    }

    func testAttachAndReadCurrentState() throws {
        let db = try openFixture()
        XCTAssertEqual(try db.run("SELECT count(*) FROM observations;").scalar, "5")
        XCTAssertEqual(try db.run("SELECT count(*) FROM regions;").scalar, "3")
    }

    func testSnapshotsListed() throws {
        let db = try openFixture()
        XCTAssertEqual(try db.run("SELECT count(*) FROM ducklake_snapshots('lake');").scalar, "11")
    }

    func testTimeTravelToEarlierVersion() throws {
        let db = try openFixture()
        // Snapshot 4 is the first insert batch (4 rows), before the later delete.
        XCTAssertEqual(
            try db.run("SELECT count(*) FROM observations AT (VERSION => 4);").scalar, "4")
    }

    func testGeometryDecodesToWKT() throws {
        let db = try openFixture()
        let wkt = try db.run(
            "SELECT ST_AsText(geom) FROM observations ORDER BY id LIMIT 1;").scalar
        XCTAssertEqual(wkt, "POINT (-1.55 53.8)")
    }

    func testFileLayerIsQueryable() throws {
        let db = try openFixture()
        let files = try db.run("SELECT * FROM ducklake_list_files('lake', 'observations');")
        XCTAssertGreaterThan(files.rowCount, 0)
        XCTAssertTrue(files.columns.contains("data_file"))
    }

    func testErrorsAreSurfacedNotSwallowed() throws {
        let db = try openFixture()
        XCTAssertThrowsError(try db.run("SELECT * FROM table_that_does_not_exist;")) { error in
            XCTAssertTrue(String(describing: error).contains("does_not_exist"))
        }
    }
}

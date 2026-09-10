import XCTest
import DuckDBKit

/// Exercises the async session layer: attach + query run off the calling thread through
/// the actor, results come back typed, and the local/remote `LakeSource` seam builds the
/// right `ducklake:` targets.
final class LakeSessionTests: XCTestCase {

    private func openSession() async throws -> LakeSession {
        let session = try LakeSession()
        try await session.loadCoreExtensions()
        try await session.attach(.duckDBFile(TestFixture.path))
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

    func testSourceTargets() {
        XCTAssertEqual(LakeSource.duckDBFile("/tmp/a.ducklake").attachTarget, "ducklake:/tmp/a.ducklake")
        XCTAssertEqual(LakeSource.sqliteFile("/tmp/a.sqlite").attachTarget, "ducklake:sqlite:/tmp/a.sqlite")
        XCTAssertEqual(LakeSource.duckDBFile("a'b.ducklake").attachTarget, "ducklake:a''b.ducklake")
    }
}

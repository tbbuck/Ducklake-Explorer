import Foundation
import DuckDBKit

/// Headless smoke test for the *packaged* app. Loads the bundled engine exactly as the app
/// does at runtime — the same `DuckDBConfig` (bundled `extension_directory`, unsigned loading,
/// no autoinstall) and the same by-path `loadCoreExtensions` — then attaches a lake read-only
/// and counts its snapshots, and exits.
///
/// Its point is to prove, without the GUI, that the *signed, hardened* binary can load its own
/// `libduckdb` (linked at launch) and `dlopen` the re-signed extensions under macOS library
/// validation — the thing a Developer-ID + notarized build has to get right. Run it directly
/// so AMFI still enforces the signature:
///
///   "DuckLake Explorer.app/Contents/MacOS/DuckLake Explorer" --selftest /path/to/lake.ducklake
///
/// Exits 0 on success, 1 on a load/query failure, 2 on a usage error.
enum SelfTest {
    static func run() -> Never {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--selftest"), flag + 1 < args.count else {
            FileHandle.standardError.write(Data("selftest: usage --selftest <lake-path>\n".utf8))
            exit(2)
        }
        let lakePath = args[flag + 1]

        // Same resolution as AppModel: a packaged .app ships its extensions here; otherwise nil
        // (falls back to the machine's ~/.duckdb, which is the dev/unbundled case).
        let extensionDirectory: String? = {
            guard let resources = Bundle.main.resourcePath else { return nil }
            let dir = resources + "/duckdb-extensions"
            return FileManager.default.fileExists(atPath: dir) ? dir : nil
        }()

        // Bridge the async load path to this synchronous entry point. The box carries the
        // result out of the task; the semaphore's signal→wait ordering makes that read safe.
        final class Result: @unchecked Sendable { var code: Int32 = 0 }
        let result = Result()
        let done = DispatchSemaphore(value: 0)
        Task {
            do {
                let config = extensionDirectory.map {
                    DuckDBConfig(extensionDirectory: $0, allowUnsignedExtensions: true, disableAutoinstall: true)
                } ?? DuckDBConfig()
                let session = try LakeSession(config: config)
                try await session.loadCoreExtensions(fromDirectory: extensionDirectory)
                let source: LakeSource = lakePath.lowercased().hasSuffix(".sqlite")
                    ? .sqliteFile(lakePath) : .duckDBFile(lakePath)
                try await session.attach(source)
                let snapshots = try await session.query(
                    "SELECT count(*) FROM ducklake_snapshots('lake');").scalarString ?? "?"
                let origin = extensionDirectory ?? "system (~/.duckdb)"
                print("selftest OK — extensions from \(origin); snapshots=\(snapshots)")
            } catch {
                FileHandle.standardError.write(Data("selftest FAIL — \(error)\n".utf8))
                result.code = 1
            }
            done.signal()
        }
        done.wait()
        exit(result.code)
    }
}

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

        let extensionDirectory = EngineSupport.extensionDirectory()

        // Bridge the async load path to this synchronous entry point. The box carries the
        // result out of the task; the semaphore's signal→wait ordering makes that read safe.
        final class Result: @unchecked Sendable { var code: Int32 = 0 }
        let result = Result()
        let done = DispatchSemaphore(value: 0)
        Task {
            do {
                let session = try LakeSession(config: EngineSupport.config())
                try await session.loadCoreExtensions()   // autoinstalls from DuckDB's repo if missing
                let source: LakeSource = lakePath.lowercased().hasSuffix(".sqlite")
                    ? .sqliteFile(lakePath) : .duckDBFile(lakePath)
                // If the catalog has a sibling "<catalog>.files" data dir (the fixture layout),
                // override its stored (relative) data_path with the absolute location.
                let candidate = lakePath + ".files"
                var isDirectory: ObjCBool = false
                let dataPath = FileManager.default.fileExists(atPath: candidate, isDirectory: &isDirectory)
                    && isDirectory.boolValue ? candidate : nil
                try await session.attach(source, dataPath: dataPath)
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

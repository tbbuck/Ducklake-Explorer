import SwiftUI
import Foundation

@main
struct DuckLakeExplorerApp: App {
    @State private var model = AppModel()

    init() {
        StratumFonts.register()
    }

    var body: some Scene {
        WindowGroup {
            ExplorerView()
                .environment(model)
                .frame(minWidth: 1180, minHeight: 720)
                .preferredColorScheme(model.appearanceOverride)
                .task {
                    #if DEBUG
                    // Dev convenience: auto-open a lake so the shell is populated — the
                    // real (remote-data) herd lake if present, else the committed fixture.
                    // Replaced by the ConnectView open flow.
                    if model.lakePath == nil {
                        let herd = "/Users/tom/Code/Claude/ducklake-explorer/herd-lake.sqlite"
                        let fixture = "/Users/tom/Code/Claude/ducklake-explorer/Fixtures/sample.ducklake"
                        await model.open(path: FileManager.default.fileExists(atPath: herd) ? herd : fixture)
                    }
                    #endif
                }
        }
        .windowStyle(.titleBar)
    }
}

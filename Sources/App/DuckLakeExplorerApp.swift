import SwiftUI

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
                .frame(minWidth: 1040, minHeight: 660)
                .preferredColorScheme(model.appearanceOverride)
                .task {
                    #if DEBUG
                    // Dev convenience: auto-open the committed fixture so the shell is
                    // populated. Replaced by the ConnectView open flow.
                    if model.lakePath == nil {
                        await model.open(path: "/Users/tom/Code/Claude/ducklake-explorer/Fixtures/sample.ducklake")
                    }
                    #endif
                }
        }
        .windowStyle(.titleBar)
    }
}

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
                    // Dev convenience: auto-open the most-recent lake so launches are
                    // populated. Release builds start at the ConnectView.
                    if model.lakePath == nil, let recent = model.recents.first {
                        await model.open(path: recent.path)
                    }
                    #endif
                }
        }
        .windowStyle(.titleBar)
    }
}

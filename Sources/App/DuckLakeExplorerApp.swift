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
        }
        .windowStyle(.titleBar)
    }
}

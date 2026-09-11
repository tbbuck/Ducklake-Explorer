import SwiftUI
import Foundation

/// Process entry point. Diverts to the headless self-test when asked (see `SelfTest`);
/// otherwise launches the normal SwiftUI app.
@main
enum AppEntry {
    static func main() {
        if CommandLine.arguments.contains("--selftest") {
            SelfTest.run()   // runs the bundled-engine load path, then exits — never returns
        }
        DuckLakeExplorerApp.main()
    }
}

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

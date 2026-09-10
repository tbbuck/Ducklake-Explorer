import SwiftUI
import UniformTypeIdentifiers

/// The main window: the three-pane Stratum layout (HistoryRail · SchemaTree · DetailPane)
/// once a lake is open, or a connect prompt before that.
struct ExplorerView: View {
    @Environment(AppModel.self) private var model
    @State private var showImporter = false

    var body: some View {
        @Bindable var model = model
        Group {
            if model.lakePath == nil {
                ConnectPlaceholder(open: { showImporter = true })
            } else {
                NavigationSplitView {
                    HistoryRail()
                        .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
                } content: {
                    SchemaTree()
                        .navigationSplitViewColumnWidth(min: 220, ideal: 270)
                } detail: {
                    DetailPane()
                }
                .navigationTitle(model.lakeName ?? "DuckLake Explorer")
            }
        }
        .background(Palette.base)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if model.lakePath != nil {
                    HStack(spacing: 12) {
                        Picker("", selection: $model.detailMode) {
                            ForEach(AppModel.DetailMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                        SnapshotChip(snapshot: model.activeSnapshot)
                    }
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if model.lakePath != nil { ThemeToggle() }
                Button { showImporter = true } label: { Image(systemName: "folder") }
                    .help("Open a DuckLake catalog")
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data]) { result in
            if case .success(let url) = result {
                Task { await model.open(path: url.path) }
            }
        }
        .overlay(alignment: .bottom) {
            if let error = model.errorText {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.stratumMono(11))
                    .foregroundStyle(Palette.danger)
                    .textSelection(.enabled)
                    .padding(10)
                    .background(Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 8))
                    .padding()
            }
        }
    }
}

/// Pre-open state — the seed of UI-SPEC's `ConnectView` (recents + open panel come next).
private struct ConnectPlaceholder: View {
    let open: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "cylinder.split.1x2")
                .font(.system(size: 44)).foregroundStyle(Palette.accent)
            Text("DuckLake Explorer").font(.stratumDisplay(26))
                .foregroundStyle(Palette.textPrimary)
            Text("Open a .ducklake catalog to explore its schema, snapshots, and files — read-only.")
                .font(.stratumUI(13)).foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: 380)
            Button(action: open) {
                Text("Open DuckLake…").font(.stratumUI(13, .medium))
                    .padding(.horizontal, 16).padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent).tint(Palette.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.base)
    }
}

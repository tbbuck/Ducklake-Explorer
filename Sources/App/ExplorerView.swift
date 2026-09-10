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
                ConnectView(openLocal: { showImporter = true })
            } else {
                NavigationSplitView {
                    HistoryRail()
                        .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
                } content: {
                    ZStack {
                        if model.detailMode == .metadata {
                            CatalogTableList()
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        } else {
                            SchemaTree()
                                .transition(.move(edge: .leading).combined(with: .opacity))
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: model.detailMode == .metadata)
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
        .overlay {
            if model.isLoading {
                LakeLoadingView(name: model.lakeName ?? "lake")
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: model.isLoading)
    }
}

/// The full-cover loader shown while a lake is first attaching; fades out over the populated
/// three-pane once loading completes.
private struct LakeLoadingView: View {
    let name: String
    @State private var pulse = false

    var body: some View {
        ZStack {
            Palette.base
            VStack(spacing: 18) {
                ProgressView()
                    .controlSize(.large)
                    .scaleEffect(pulse ? 1.0 : 0.94)
                    .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)
                Text("Opening \(name)…")
                    .font(.stratumUI(14, .medium))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .ignoresSafeArea()
        .onAppear { pulse = true }
    }
}

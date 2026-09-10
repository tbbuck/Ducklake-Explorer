import SwiftUI

/// Read-only SQL workbench: an editor, Run/Cancel (off the main thread, cancellable via
/// `duckdb_interrupt`), and the virtualised `ResultsGrid`.
struct WorkbenchView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                PanelLabel("Query")
                TextEditor(text: $model.sql)
                    .font(.stratumMono(12))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 128)
                    .background(Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.hairline))

                HStack(spacing: 12) {
                    Button {
                        model.isQuerying ? model.cancelQuery() : model.runQuery()
                    } label: {
                        Text(model.isQuerying ? "Cancel" : "Run")
                            .font(.stratumUI(12, .medium))
                            .frame(width: 58)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(model.isQuerying ? Palette.accent2 : Palette.accent)
                    .keyboardShortcut(.return, modifiers: .command)

                    if model.isQuerying {
                        ProgressView().controlSize(.small)
                    } else if let result = model.queryResult {
                        Text(model.queryRowsCapped ? "\(result.rowCount) rows (capped)" : "\(result.rowCount) rows")
                            .font(.stratumMono(10)).foregroundStyle(Palette.textTertiary)
                    }
                    Spacer()
                    Text("read-only").font(.stratumMono(9))
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Palette.track, in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(16)

            Divider().overlay(Palette.hairline)
            results
        }
        .background(Palette.base)
    }

    @ViewBuilder private var results: some View {
        if let error = model.queryError {
            ScrollView {
                Text(error)
                    .font(.stratumMono(11)).foregroundStyle(Palette.danger)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        } else if let result = model.queryResult, !result.columns.isEmpty {
            ResultsGrid(result: result)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "command").font(.system(size: 22)).foregroundStyle(Palette.textTertiary)
                Text("⌘↩ to run").font(.stratumMono(11)).foregroundStyle(Palette.textTertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

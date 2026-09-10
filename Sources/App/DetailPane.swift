import SwiftUI
import DuckDBKit

/// The right pane. For this slice it's a lightweight table summary — the seed of the full
/// `TableInspector` (CoreSampleView + SchemaStatsTable + distributions) from UI-SPEC §5.3.
struct DetailPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let node = model.selectedNode, node.kind == .table || node.kind == .view {
                TableSummary(node: node)
            } else {
                EmptyState()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.base)
    }
}

private struct TableSummary: View {
    @Environment(AppModel.self) private var model
    let node: CatalogNode

    @State private var rowCount: String = "—"
    @State private var fileCount: String = "—"

    private var columns: [CatalogNode] { node.children ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    Text(node.name).font(.stratumDisplay(22)).tracking(-0.4)
                        .foregroundStyle(Palette.textPrimary)
                    Badge(text: node.kind == .view ? "view" : "table")
                    Spacer()
                    SnapshotChip(snapshot: model.activeSnapshot)
                }

                HStack(spacing: 28) {
                    Metric(label: "Rows", value: rowCount)
                    Metric(label: "Columns", value: "\(columns.count)")
                    Metric(label: "Files", value: fileCount)
                }

                VStack(alignment: .leading, spacing: 0) {
                    PanelLabel("Schema")
                    ForEach(columns) { column in
                        HStack(spacing: 10) {
                            Image(systemName: column.symbol)
                                .font(.system(size: 11))
                                .foregroundStyle(column.isGeometry ? Palette.geometry : Palette.textTertiary)
                                .frame(width: 16)
                            Text(column.name).font(.stratumMono(12))
                                .foregroundStyle(Palette.textPrimary)
                            Spacer()
                            Text(column.dataType ?? "")
                                .font(.stratumMono(11))
                                .foregroundStyle(typeColor(column.dataType))
                            Text(column.nullable ? "nullable" : "not null")
                                .font(.stratumMono(9))
                                .foregroundStyle(Palette.textTertiary)
                                .frame(width: 64, alignment: .trailing)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        Divider().overlay(Palette.hairline)
                    }
                }
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.hairline))
            }
            .padding(24)
        }
        .task(id: node.id) { await loadMetrics() }
    }

    private func loadMetrics() async {
        rowCount = "…"; fileCount = "…"
        do {
            let rows = try await model.query("SELECT count(*) FROM \"\(node.name)\";")
            rowCount = rows.scalarString ?? "—"
            let files = try await model.query("SELECT count(*) FROM ducklake_list_files('lake', '\(node.name)');")
            fileCount = files.scalarString ?? "—"
        } catch {
            rowCount = "—"; fileCount = "—"
        }
    }
}

private struct Metric: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.stratumMono(20, .medium)).foregroundStyle(Palette.accent)
            Text(label.uppercased()).font(.stratumMono(9, .medium)).tracking(0.8)
                .foregroundStyle(Palette.textTertiary)
        }
    }
}

private struct EmptyState: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 32)).foregroundStyle(Palette.textTertiary)
            Text("Select a table to inspect it")
                .font(.stratumUI(13)).foregroundStyle(Palette.textSecondary)
        }
    }
}

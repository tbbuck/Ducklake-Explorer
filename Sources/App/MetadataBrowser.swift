import SwiftUI
import DuckDBKit

/// "The metadata is data." In Meta mode the raw `ducklake_*` catalog tables (via the attached
/// `lake_meta` catalog) take over the two right panes: `CatalogTableList` slides into the middle
/// pane in place of the schema tree, and `CatalogTableGrid` shows the selected table in the
/// detail pane. Both share `model.metaTable` so the selection survives leaving and re-entering
/// Meta mode.

/// The middle pane while in Meta mode: the raw catalog tables, grouped under the UI-spec
/// headings (Snapshots · Schema · Data files · Statistics · Tags·Settings · Inlined data).
struct CatalogTableList: View {
    @Environment(AppModel.self) private var model
    @State private var tables: [CatalogTableRow] = []

    /// Tables bucketed into their catalog group, in display order, dropping empty groups.
    private var grouped: [(group: CatalogGroup, rows: [CatalogTableRow])] {
        CatalogGroup.allCases.compactMap { group in
            let rows = tables.filter { CatalogGroup.of($0.name) == group }
            return rows.isEmpty ? nil : (group, rows)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelLabel("Catalog tables")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(grouped, id: \.group) { section in
                        Text(section.group.title)
                            .font(.stratumMono(9, .medium)).tracking(0.9)
                            .foregroundStyle(Palette.textTertiary)
                            .padding(.horizontal, 10).padding(.top, 14).padding(.bottom, 3)
                        ForEach(section.rows) { table in row(table) }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Palette.surface)
        .task { await loadList() }
    }

    private func row(_ table: CatalogTableRow) -> some View {
        Button { model.metaTable = table.name } label: {
            HStack(spacing: 8) {
                Text(table.short).font(.stratumMono(11)).foregroundStyle(Palette.textPrimary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 6)
                Text(table.rows).font(.stratumMono(9)).foregroundStyle(Palette.textTertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(model.metaTable == table.name ? Palette.accentSoft : .clear)
            .contentShape(Rectangle())   // whole row is the hit target, not just the text
        }
        .buttonStyle(.plain)
    }

    private func loadList() async {
        guard tables.isEmpty else { return }
        // Names + estimated row counts of the catalog tables (excluding the many transient
        // per-transaction inlined-data tables).
        guard let r = try? await model.query("""
            SELECT table_name, estimated_size
            FROM duckdb_tables()
            WHERE database_name = 'lake_meta' AND table_name LIKE 'ducklake_%'
              AND table_name NOT LIKE 'ducklake_inlined_data_%'
            ORDER BY table_name;
            """) else { return }
        tables = r.rows.map { row in
            let name = row[0].displayString
            // 10,000 is the sqlite_scanner default estimate (no real stats) — hide it.
            let estimate = row.count > 1 ? row[1].int64 : nil
            let count = (estimate == nil || estimate == 10_000) ? "" : Format.count(estimate!)
            return CatalogTableRow(name: name, rows: count)
        }
        if model.metaTable == nil {
            model.metaTable = tables.first(where: { $0.name == "ducklake_snapshot" })?.name ?? tables.first?.name
        }
    }
}

/// The detail pane while in Meta mode: the selected catalog table's rows.
struct CatalogTableGrid: View {
    @Environment(AppModel.self) private var model
    @State private var result: QueryResult?
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        ZStack {
            if let error {
                ScrollView {
                    Text(error).font(.stratumMono(11)).foregroundStyle(Palette.danger)
                        .textSelection(.enabled).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if let result, !result.columns.isEmpty {
                ResultsGrid(result: result)
            } else {
                Color.clear
            }
            if loading { ProgressView().controlSize(.small) }
        }
        .task(id: model.metaTable ?? "") { await loadTable() }
    }

    private func loadTable() async {
        guard let table = model.metaTable else { result = nil; return }
        loading = true
        error = nil
        do {
            let r = try await model.query("SELECT * FROM lake_meta.\"\(table)\" LIMIT 5000;", maxRows: 5000)
            guard model.metaTable == table else { return }   // superseded by a newer selection
            result = r
        } catch {
            guard model.metaTable == table else { return }
            self.error = String(describing: error)
            result = nil
        }
        if model.metaTable == table { loading = false }
    }
}

/// The UI-spec buckets for the `ducklake_*` catalog tables. `allCases` order is the display
/// order; inlined-data tables sink to the bottom.
enum CatalogGroup: String, CaseIterable {
    case snapshots, schema, dataFiles, statistics, tagsSettings, inlined

    var title: String {
        switch self {
        case .snapshots:    return "SNAPSHOTS"
        case .schema:       return "SCHEMA"
        case .dataFiles:    return "DATA FILES"
        case .statistics:   return "STATISTICS"
        case .tagsSettings: return "TAGS · SETTINGS"
        case .inlined:      return "INLINED DATA"
        }
    }

    /// Classifies a `ducklake_*` table by name (checks are ordered — most specific first).
    static func of(_ name: String) -> CatalogGroup {
        let n = name.hasPrefix("ducklake_") ? String(name.dropFirst("ducklake_".count)) : name
        if n.hasPrefix("inlined_") { return .inlined }
        if n == "snapshot" || n == "snapshot_changes" { return .snapshots }
        if n.contains("stat") { return .statistics }
        if n.contains("file") { return .dataFiles }
        if n.contains("tag") || n == "metadata" { return .tagsSettings }
        return .schema
    }
}

private struct CatalogTableRow: Identifiable {
    let name: String
    let rows: String
    var id: String { name }
    var short: String { name.hasPrefix("ducklake_") ? String(name.dropFirst("ducklake_".count)) : name }
}

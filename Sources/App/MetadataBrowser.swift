import SwiftUI
import DuckDBKit

/// "The metadata is data." Browses the raw `ducklake_*` catalog tables (via the attached
/// `lake_meta` catalog) in the results grid.
struct MetadataBrowser: View {
    @Environment(AppModel.self) private var model

    @State private var tables: [CatalogTableRow] = []
    @State private var selected: String?
    @State private var result: QueryResult?
    @State private var error: String?

    var body: some View {
        HStack(spacing: 0) {
            list
            Divider().overlay(Palette.hairline)
            grid
        }
        .task { await loadList() }
        .task(id: selected ?? "") { await loadTable() }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelLabel("Catalog tables")
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(tables) { table in
                        Button { selected = table.name } label: {
                            HStack(spacing: 8) {
                                Text(table.short).font(.stratumMono(11)).foregroundStyle(Palette.textPrimary)
                                    .lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 6)
                                Text(table.rows).font(.stratumMono(9)).foregroundStyle(Palette.textTertiary)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .frame(maxWidth: .infinity)
                            .background(selected == table.name ? Palette.accentSoft : .clear)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(width: 250)
        .background(Palette.surface)
    }

    @ViewBuilder private var grid: some View {
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
        if selected == nil { selected = tables.first(where: { $0.name == "ducklake_snapshot" })?.name ?? tables.first?.name }
    }

    private func loadTable() async {
        guard let selected else { return }
        error = nil
        do {
            result = try await model.query("SELECT * FROM lake_meta.\"\(selected)\" LIMIT 5000;", maxRows: 5000)
        } catch {
            self.error = String(describing: error)
            result = nil
        }
    }
}

private struct CatalogTableRow: Identifiable {
    let name: String
    let rows: String
    var id: String { name }
    var short: String { name.hasPrefix("ducklake_") ? String(name.dropFirst("ducklake_".count)) : name }
}

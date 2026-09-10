import SwiftUI

/// Compares the schema at two snapshots — tables and columns added / dropped / changed —
/// computed from the catalog's `begin_snapshot`/`end_snapshot` ranges (offline).
struct SnapshotDiffView: View {
    @Environment(AppModel.self) private var model

    @State private var from: Snapshot?
    @State private var to: Snapshot?
    @State private var diff: SnapshotDiff?
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Palette.hairline)
            ScrollView { content.padding(16) }
        }
        .background(Palette.base)
        .onAppear {
            // Default to a recent window (last ~20 snapshots) — focused and quick to compute.
            if from == nil { from = model.snapshots.count > 20 ? model.snapshots[20] : model.snapshots.last }
            if to == nil { to = model.snapshots.first }
        }
        .task(id: "\(from?.id ?? -1)>\(to?.id ?? -1)") { await compute() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            SnapshotPicker(label: "From", snapshots: model.snapshots, selection: $from)
            Image(systemName: "arrow.right")
                .font(.system(size: 12)).foregroundStyle(Palette.accent)
            SnapshotPicker(label: "To", snapshots: model.snapshots, selection: $to)
            Spacer()
            if loading { ProgressView().controlSize(.small) }
        }
        .padding(16)
    }

    @ViewBuilder private var content: some View {
        if let diff {
            if diff.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "equal.circle").font(.system(size: 26)).foregroundStyle(Palette.textTertiary)
                    Text("No schema changes between these snapshots")
                        .font(.stratumUI(12)).foregroundStyle(Palette.textSecondary)
                }
                .frame(maxWidth: .infinity).padding(.top, 40)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    DiffSection(title: "Tables", added: diff.tablesAdded, removed: diff.tablesDropped)
                    DiffSection(title: "Columns", added: diff.columnsAdded,
                                removed: diff.columnsDropped, changed: diff.columnsChanged)
                }
            }
        }
    }

    private func compute() async {
        guard let from, let to, from.id != to.id else { diff = SnapshotDiff(); return }
        loading = true
        defer { loading = false }
        let lo = min(from.id, to.id)
        let hi = max(from.id, to.id)

        let tablesLo = await tables(at: lo)
        let tablesHi = await tables(at: hi)
        let colsLo = await columns(at: lo)
        let colsHi = await columns(at: hi)

        var result = SnapshotDiff()
        result.tablesAdded = tablesHi.subtracting(tablesLo).sorted()
        result.tablesDropped = tablesLo.subtracting(tablesHi).sorted()
        result.columnsAdded = Set(colsHi.keys).subtracting(colsLo.keys).sorted()
        result.columnsDropped = Set(colsLo.keys).subtracting(colsHi.keys).sorted()
        result.columnsChanged = colsLo.keys
            .filter { colsHi[$0] != nil && colsHi[$0] != colsLo[$0] }
            .map { "\($0): \(colsLo[$0]!) → \(colsHi[$0]!)" }
            .sorted()
        diff = result
    }

    private func tables(at snapshot: Int64) async -> Set<String> {
        guard let result = try? await model.query("""
            SELECT table_name FROM lake_meta.ducklake_table
            WHERE begin_snapshot <= \(snapshot) AND (end_snapshot IS NULL OR end_snapshot > \(snapshot));
            """) else { return [] }
        return Set(result.rows.compactMap { $0.first?.stringValue })
    }

    private func columns(at snapshot: Int64) async -> [String: String] {
        guard let result = try? await model.query("""
            SELECT t.table_name || '.' || c.column_name AS col, c.column_type
            FROM lake_meta.ducklake_column c
            JOIN lake_meta.ducklake_table t
              ON t.table_id = c.table_id
             AND t.begin_snapshot <= \(snapshot) AND (t.end_snapshot IS NULL OR t.end_snapshot > \(snapshot))
            WHERE c.begin_snapshot <= \(snapshot) AND (c.end_snapshot IS NULL OR c.end_snapshot > \(snapshot));
            """) else { return [:] }
        var map: [String: String] = [:]
        for row in result.rows where !row[0].isNull {
            map[row[0].displayString] = row.count > 1 ? row[1].displayString : ""
        }
        return map
    }
}

/// A from/to snapshot chooser with a scrollable popover (handles thousands of snapshots).
private struct SnapshotPicker: View {
    let label: String
    let snapshots: [Snapshot]
    @Binding var selection: Snapshot?
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(label.uppercased()).font(.stratumMono(9, .medium)).tracking(0.8)
                    .foregroundStyle(Palette.textTertiary)
                Text(verbatim: selection.map { "v\($0.id)" } ?? "—")
                    .font(.stratumMono(13, .medium)).foregroundStyle(Palette.textPrimary)
                Text(selection?.time ?? " ").font(.stratumMono(9)).foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }
            .frame(width: 150, alignment: .leading)
            .padding(8)
            .background(Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.hairline))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(snapshots) { snapshot in
                        Button { selection = snapshot; open = false } label: {
                            HStack(spacing: 8) {
                                Text(verbatim: "v\(snapshot.id)")
                                    .font(.stratumMono(11, .medium)).foregroundStyle(Palette.textPrimary)
                                Spacer()
                                Text(snapshot.time).font(.stratumMono(9)).foregroundStyle(Palette.textTertiary)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .frame(maxWidth: .infinity)
                            .background(snapshot.id == selection?.id ? Palette.accentSoft : .clear)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(width: 250, height: 340)
            .background(Palette.surface)
        }
    }
}

private struct DiffSection: View {
    let title: String
    var added: [String] = []
    var removed: [String] = []
    var changed: [String] = []

    var body: some View {
        if added.isEmpty && removed.isEmpty && changed.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                PanelLabel(counts)
                ForEach(added, id: \.self) { DiffRow(text: $0, kind: .add) }
                ForEach(changed, id: \.self) { DiffRow(text: $0, kind: .change) }
                ForEach(removed, id: \.self) { DiffRow(text: $0, kind: .remove) }
            }
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.hairline))
        }
    }

    private var counts: String {
        var parts = ["\(title)  +\(added.count)  −\(removed.count)"]
        if !changed.isEmpty { parts.append("~\(changed.count)") }
        return parts.joined(separator: "  ")
    }
}

private struct DiffRow: View {
    enum Kind { case add, remove, change }
    let text: String
    let kind: Kind

    var body: some View {
        HStack(spacing: 8) {
            Text(symbol).font(.stratumMono(11, .semibold)).foregroundStyle(color).frame(width: 12)
            Text(text).font(.stratumMono(11)).foregroundStyle(Palette.textPrimary)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
    }

    private var symbol: String {
        switch kind { case .add: return "+"; case .remove: return "−"; case .change: return "~" }
    }
    // Tokens: additions use accent (teal); deletions/alterations use accent-2 (amber).
    private var color: Color { kind == .add ? Palette.accent : Palette.accent2 }
}

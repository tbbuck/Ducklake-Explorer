import SwiftUI

/// "What is this table, physically?" — header + metrics, the `CoreSampleView` file-stack,
/// and the schema. Everything here reads **catalog metadata** (`duckdb_tables`,
/// `ducklake_list_files`), so it works even when the data lives on S3 (the herd lake).
struct TableInspector: View {
    @Environment(AppModel.self) private var model
    let node: CatalogNode

    @State private var files: [DataFile] = []
    @State private var estRows: String = "…"

    private var columns: [CatalogNode] { node.children ?? [] }
    private var dataFiles: [DataFile] { files.filter { $0.kind == .data } }
    private var totalSize: Int64 { dataFiles.reduce(0) { $0 + $1.sizeBytes } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                metrics
                Divider().overlay(Palette.hairline)
                HStack(alignment: .top, spacing: 20) {
                    coreColumn.frame(width: 220, alignment: .leading)
                    schemaColumn.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24)
        }
        .task(id: node.id) { await load() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(node.name).font(.stratumDisplay(22)).tracking(-0.4)
                .foregroundStyle(Palette.textPrimary)
            Badge(text: node.kind == .view ? "view" : "table")
            Spacer()
            SnapshotChip(snapshot: model.activeSnapshot)
        }
    }

    private var metrics: some View {
        HStack(spacing: 30) {
            Metric(label: "Rows", value: estRows)
            Metric(label: "Columns", value: "\(columns.count)")
            Metric(label: "Files", value: "\(dataFiles.count)")
            Metric(label: "Size", value: totalSize > 0 ? Format.bytes(totalSize) : "—")
        }
    }

    private var coreColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelLabel("Core sample")
            HStack(alignment: .top, spacing: 14) {
                CoreSampleView(files: files).padding(.leading, 12)
                FileLegend(files: files)
            }
            .padding(.top, 4)
        }
    }

    private var schemaColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelLabel("Schema")
            ForEach(columns) { column in
                HStack(spacing: 10) {
                    Image(systemName: column.symbol)
                        .font(.system(size: 11))
                        .foregroundStyle(column.isGeometry ? Palette.geometry : Palette.textTertiary)
                        .frame(width: 16)
                    Text(column.name).font(.stratumMono(12)).foregroundStyle(Palette.textPrimary)
                        .lineLimit(1).layoutPriority(1)
                    Spacer(minLength: 8)
                    Text(column.dataType ?? "").font(.stratumMono(11))
                        .foregroundStyle(typeColor(column.dataType))
                        .lineLimit(1)
                    Text(column.nullable ? "nullable" : "not null")
                        .font(.stratumMono(9)).foregroundStyle(Palette.textTertiary)
                        .frame(width: 62, alignment: .trailing)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                Divider().overlay(Palette.hairline)
            }
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.hairline))
    }

    private func load() async {
        estRows = "…"; files = []
        do {
            let rows = try await model.query(
                "SELECT estimated_size FROM duckdb_tables() WHERE database_name = 'lake' AND table_name = '\(node.name)';")
            if let s = rows.scalarString, let n = Int64(s) { estRows = Format.count(n) }
            else { estRows = rows.scalarString ?? "—" }

            let listed = try await model.query("""
                SELECT data_file, data_file_size_bytes, delete_file, delete_file_size_bytes
                FROM ducklake_list_files('lake', '\(node.name)');
                """)
            var parsed: [DataFile] = []
            for row in listed.rows {
                if !row[0].isNull {
                    parsed.append(DataFile(id: row[0].displayString, path: row[0].displayString,
                                           sizeBytes: row[1].int64 ?? 0, kind: .data))
                }
                if row.count > 2, !row[2].isNull {
                    parsed.append(DataFile(id: row[2].displayString, path: row[2].displayString,
                                           sizeBytes: row[3].int64 ?? 0, kind: .delete))
                }
            }
            files = parsed
        } catch {
            estRows = "—"
        }
    }
}

private struct Metric: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.stratumMono(18, .medium)).foregroundStyle(Palette.accent)
            Text(label.uppercased()).font(.stratumMono(9, .medium)).tracking(0.8)
                .foregroundStyle(Palette.textTertiary)
        }
    }
}

/// The literal core: stacked Parquet layers sized by file size, coloured down the strata
/// ramp, with delete files drawn as amber "erosion" lines.
struct CoreSampleView: View {
    let files: [DataFile]

    private let strata = [Palette.strataSand, Palette.strataSilt, Palette.strataMarl,
                          Palette.strataShale, Palette.strataSlate]

    var body: some View {
        let data = files.filter { $0.kind == .data }
        let deletes = files.filter { $0.kind == .delete }
        let total = max(1, data.reduce(0) { $0 + $1.sizeBytes })

        Canvas { context, size in
            var y: CGFloat = 0
            for (index, file) in data.enumerated() {
                let height = size.height * CGFloat(file.sizeBytes) / CGFloat(total)
                let rect = CGRect(x: 0, y: y, width: size.width, height: max(1, height))
                context.fill(Path(rect), with: .color(strata[index % strata.count]))
                context.stroke(
                    Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) },
                    with: .color(Palette.base.opacity(0.45)), lineWidth: 0.5)
                y += height
            }
            for (j, _) in deletes.enumerated() {
                let dy = size.height * CGFloat(j + 1) / CGFloat(deletes.count + 1)
                context.stroke(
                    Path { $0.move(to: CGPoint(x: 0, y: dy)); $0.addLine(to: CGPoint(x: size.width, y: dy)) },
                    with: .color(Palette.accent2), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
            }
        }
        .frame(width: 78, height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(colors: [.black.opacity(0.16), .clear, .black.opacity(0.16)],
                                     startPoint: .leading, endPoint: .trailing))
                .blendMode(.multiply).allowsHitTesting(false))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border, lineWidth: 1))
        .overlay {
            if files.isEmpty {
                Text("no files").font(.stratumMono(9)).foregroundStyle(Palette.textTertiary)
            }
        }
    }
}

/// The legend beside the core — one row per file, sized, with a delete tag.
private struct FileLegend: View {
    let files: [DataFile]
    private let cap = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(files.prefix(cap)) { file in
                HStack(spacing: 7) {
                    Circle()
                        .fill(file.kind == .delete ? Palette.accent2 : Palette.strataMarl)
                        .frame(width: 6, height: 6)
                    Text(shortName(file.name)).font(.stratumMono(9)).foregroundStyle(Palette.textSecondary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 6)
                    Text(Format.bytes(file.sizeBytes)).font(.stratumMono(9))
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            if files.count > cap {
                Text("+\(files.count - cap) more").font(.stratumMono(9))
                    .foregroundStyle(Palette.textTertiary).padding(.top, 1)
            }
        }
    }

    /// Trims the DuckLake UUID filename to a short token.
    private func shortName(_ name: String) -> String {
        let stem = name.replacingOccurrences(of: ".parquet", with: "")
            .replacingOccurrences(of: "ducklake-", with: "")
        return String(stem.prefix(8)) + "…"
    }
}

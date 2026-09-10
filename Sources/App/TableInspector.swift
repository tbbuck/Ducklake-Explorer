import SwiftUI
import DuckDBKit

/// "What is this table, physically?" — header, snapshot detail, metrics, the horizontal
/// Parquet-file bar (+ scrollable legend), and a sample of the data. Metadata is read from
/// the catalog (works when data is remote); the sample loads separately so it never blocks
/// the fast metadata.
struct TableInspector: View {
    @Environment(AppModel.self) private var model
    let node: CatalogNode

    // Fast (catalog metadata)
    @State private var files: [DataFile] = []
    @State private var rowCount: String = "…"
    @State private var columnCount: String = "…"
    // Slower (actual data) — loads separately; its spinner is driven by model.loadingTableID
    @State private var sample: QueryResult?
    @State private var sampleError: String?

    private var dataFiles: [DataFile] { files.filter { $0.kind == .data } }
    private var totalSize: Int64 { dataFiles.reduce(0) { $0 + $1.sizeBytes } }
    private var taskID: String { "\(node.id)#\(model.activeSnapshot?.id ?? -1)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let snapshot = model.activeSnapshot { SnapshotDetailPanel(snapshot: snapshot) }
            metrics
            Divider().overlay(Palette.hairline)
            parquetSection
            Divider().overlay(Palette.hairline)
            sampleSection
        }
        .padding(20)
        .task(id: taskID) { await loadMetadata() }
        .task(id: taskID) { await loadSample() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(node.name).font(.stratumDisplay(22)).tracking(-0.4)
                .foregroundStyle(Palette.textPrimary)
            Badge(text: node.kind == .view ? "view" : "table")
            Spacer()
        }
    }

    private var metrics: some View {
        HStack(spacing: 30) {
            Metric(label: "Rows", value: rowCount)
            Metric(label: "Columns", value: columnCount)
            Metric(label: "Files", value: "\(dataFiles.count)")
            Metric(label: "Size", value: totalSize > 0 ? Format.bytes(totalSize) : "—")
        }
    }

    private var parquetSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelLabel("Parquet files")
            HStack(alignment: .top, spacing: 16) {
                CoreSampleView(files: files).frame(maxWidth: .infinity)
                ScrollView(.vertical, showsIndicators: true) {
                    FileLegend(files: files)
                }
                .frame(width: 240, height: 78)
            }
            .padding(.horizontal, 12).padding(.top, 6)
        }
    }

    private var sampleSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelLabel("Sample data · top 200")
            ZStack {
                if let sample, !sample.columns.isEmpty {
                    ResultsGrid(result: sample)
                } else if let sampleError {
                    ScrollView {
                        Text(sampleError).font(.stratumMono(11)).foregroundStyle(Palette.danger)
                            .textSelection(.enabled).padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if model.loadingTableID == node.id {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
    }

    /// Catalog metadata — fast. Assigned with animation and without blanking first, so
    /// switching tables cross-fades rather than flickering off/on.
    private func loadMetadata() async {
        let name = node.name
        var parsed: [DataFile] = []
        if let listed = try? await model.query("""
            SELECT data_file, data_file_size_bytes, delete_file, delete_file_size_bytes
            FROM ducklake_list_files('lake', '\(name)');
            """) {
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
        }
        if Task.isCancelled { return }   // a newer table superseded this load
        var rows = "—"
        if let r = try? await model.query(
            "SELECT estimated_size FROM duckdb_tables() WHERE database_name = 'lake' AND table_name = '\(name)';"),
           let s = r.scalarString, let n = Int64(s) {
            rows = Format.count(n)
        }
        if Task.isCancelled { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            files = parsed
            rowCount = rows
            columnCount = "\(node.children?.count ?? 0)"
        }
    }

    /// The actual data sample — slower (may hit S3), so it carries its own loader and never
    /// holds up the metadata above.
    private func loadSample() async {
        sampleError = nil
        sample = nil
        withAnimation(.easeInOut(duration: 0.2)) { model.loadingTableID = node.id }
        defer {
            // Clear the spinner only if we still own it — a newer selection may have taken over.
            if model.loadingTableID == node.id {
                withAnimation(.easeInOut(duration: 0.2)) { model.loadingTableID = nil }
            }
        }
        do {
            let result = try await model.query("SELECT * FROM \"\(node.name)\" LIMIT 200;", maxRows: 200)
            try Task.checkCancellation()
            withAnimation(.easeInOut(duration: 0.2)) { sample = result }
        } catch is CancellationError {
            // superseded while queued — let the newer load populate the view
        } catch {
            if !Task.isCancelled { sampleError = String(describing: error) }  // real error, still current
        }
    }
}

/// The active snapshot's full `snapshots()` details, shown above the inspector.
struct SnapshotDetailPanel: View {
    let snapshot: Snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(verbatim: "v\(snapshot.id)").font(.stratumMono(13, .semibold))
                    .foregroundStyle(Palette.accent)
                Text(snapshot.time).font(.stratumMono(10)).foregroundStyle(Palette.textSecondary)
                Badge(text: snapshot.changeTag, color: tagColor)
                Spacer()
                Text(verbatim: "schema v\(snapshot.schemaVersion)")
                    .font(.stratumMono(9)).foregroundStyle(Palette.textTertiary)
            }
            Text(snapshot.changes).font(.stratumMono(10)).foregroundStyle(Palette.textSecondary)
                .lineLimit(2).textSelection(.enabled)
            if let message = snapshot.commitMessage {
                Text(message).font(.stratumUI(11)).foregroundStyle(Palette.textPrimary)
            }
            if snapshot.author != nil || snapshot.commitExtraInfo != nil {
                HStack(spacing: 12) {
                    if let author = snapshot.author {
                        Label(author, systemImage: "person")
                            .font(.stratumMono(9)).foregroundStyle(Palette.textTertiary)
                    }
                    if let extra = snapshot.commitExtraInfo {
                        Text(extra).font(.stratumMono(9)).foregroundStyle(Palette.textTertiary).lineLimit(1)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.hairline))
    }

    private var tagColor: Color {
        switch snapshot.changeTag {
        case "delete", "schema": return Palette.accent2
        default: return Palette.accent
        }
    }
}

private struct Metric: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.stratumMono(18, .medium)).foregroundStyle(Palette.accent)
                .contentTransition(.numericText())
            Text(label.uppercased()).font(.stratumMono(9, .medium)).tracking(0.8)
                .foregroundStyle(Palette.textTertiary)
        }
    }
}

/// The literal core, **horizontal**: Parquet layers laid out left→right, sized by file, down
/// the strata ramp, with delete files as amber "erosion" lines.
struct CoreSampleView: View {
    let files: [DataFile]

    private let strata = [Palette.strataSand, Palette.strataSilt, Palette.strataMarl,
                          Palette.strataShale, Palette.strataSlate]

    var body: some View {
        let data = files.filter { $0.kind == .data }
        let deletes = files.filter { $0.kind == .delete }
        let total = max(1, data.reduce(0) { $0 + $1.sizeBytes })

        Canvas { context, size in
            var x: CGFloat = 0
            for (index, file) in data.enumerated() {
                let width = size.width * CGFloat(file.sizeBytes) / CGFloat(total)
                let rect = CGRect(x: x, y: 0, width: max(1, width), height: size.height)
                context.fill(Path(rect), with: .color(strata[index % strata.count]))
                context.stroke(
                    Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height)) },
                    with: .color(Palette.base.opacity(0.45)), lineWidth: 0.5)
                x += width
            }
            for (j, _) in deletes.enumerated() {
                let dx = size.width * CGFloat(j + 1) / CGFloat(deletes.count + 1)
                context.stroke(
                    Path { $0.move(to: CGPoint(x: dx, y: 0)); $0.addLine(to: CGPoint(x: dx, y: size.height)) },
                    with: .color(Palette.accent2), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
            }
        }
        .frame(height: 78)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(colors: [.black.opacity(0.16), .clear, .black.opacity(0.16)],
                                     startPoint: .top, endPoint: .bottom))
                .blendMode(.multiply).allowsHitTesting(false))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border, lineWidth: 1))
        .overlay {
            if files.isEmpty {
                Text("no files").font(.stratumMono(9)).foregroundStyle(Palette.textTertiary)
            }
        }
    }
}

/// The legend beside the core — one row per file (scrollable), sized, delete files tagged.
private struct FileLegend: View {
    let files: [DataFile]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(files) { file in
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func shortName(_ name: String) -> String {
        let stem = name.replacingOccurrences(of: ".parquet", with: "")
            .replacingOccurrences(of: "ducklake-", with: "")
        return String(stem.prefix(8)) + "…"
    }
}

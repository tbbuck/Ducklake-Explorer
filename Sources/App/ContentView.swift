import SwiftUI
import DuckDBKit
import UniformTypeIdentifiers

/// M0 scratch UI: open a DuckLake read-only, list its tables and snapshots, and
/// run ad-hoc SQL against it. Deliberately thin — queries run synchronously on the
/// main actor and results render in a simple Grid. M1/M2 replace this with a proper
/// connection layer, an off-main-thread query actor, and a virtualised results grid.
@MainActor
@Observable
final class ExplorerModel {
    private(set) var path: String?
    private(set) var settings: QueryResult?
    private(set) var tables: [String] = []
    private(set) var snapshots: QueryResult?
    private(set) var result: QueryResult?
    private(set) var error: String?
    var sql: String = ""

    private var db: DuckDB?

    func open(_ url: URL) {
        do {
            let db = try DuckDB()
            try db.run("LOAD ducklake;")
            try db.run("LOAD spatial;")
            try db.run("ATTACH 'ducklake:\(url.path)' AS lake (READ_ONLY);")
            try db.run("USE lake;")
            self.db = db
            path = url.path
            settings = try db.run(
                "SELECT catalog_type, extension_version, data_path FROM ducklake_settings('lake');")
            tables = try db.run("""
                SELECT table_name FROM information_schema.tables
                WHERE table_catalog = 'lake' AND table_schema = 'main'
                ORDER BY table_name;
                """).rows.compactMap { $0.first?.displayString }
            snapshots = try db.run("""
                SELECT snapshot_id, snapshot_time, changes
                FROM ducklake_snapshots('lake') ORDER BY snapshot_id;
                """)
            error = nil
            if let first = tables.first {
                sql = "SELECT * FROM \(first);"
                runQuery()
            }
        } catch {
            self.error = String(describing: error)
        }
    }

    func select(table: String) {
        sql = "SELECT * FROM \(table);"
        runQuery()
    }

    func runQuery() {
        guard let db else { return }
        do {
            result = try db.run(sql)
            error = nil
        } catch {
            self.error = String(describing: error)
            result = nil
        }
    }
}

struct ContentView: View {
    @State private var model = ExplorerModel()
    @State private var showImporter = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showImporter = true
                } label: {
                    Label("Open DuckLake…", systemImage: "folder")
                }
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { outcome in
            if case .success(let urls) = outcome, let url = urls.first {
                model.open(url)   // non-sandboxed: no security-scoped bookmark needed
            }
        }
        .navigationTitle(model.path.map { "DuckLake Explorer — \(($0 as NSString).lastPathComponent)" }
            ?? "DuckLake Explorer")
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List {
            if model.path == nil {
                ContentUnavailableView(
                    "No lake open", systemImage: "tray",
                    description: Text("Open a .ducklake catalog to explore it."))
            } else {
                Section("Tables") {
                    ForEach(model.tables, id: \.self) { table in
                        Button(table) { model.select(table: table) }
                            .buttonStyle(.plain)
                    }
                }
                if let snapshots = model.snapshots {
                    Section("Snapshots (\(snapshots.rowCount))") {
                        ForEach(Array(snapshots.rows.enumerated()), id: \.offset) { _, row in
                            VStack(alignment: .leading, spacing: 1) {
                                Text("v\(row.first?.displayString ?? "?")")
                                    .font(.callout.monospacedDigit())
                                Text(row.count > 1 ? row[1].displayString : "")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 220)
    }

    // MARK: Detail

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let settings = model.settings, let row = settings.rows.first {
                HStack(spacing: 16) {
                    ForEach(Array(settings.columnNames.enumerated()), id: \.offset) { i, name in
                        Label("\(name): \(row[i].displayString)", systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal).padding(.vertical, 8)
                Divider()
            }

            VStack(alignment: .leading, spacing: 6) {
                TextEditor(text: $model.sql)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 90)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                HStack {
                    Button("Run") { model.runQuery() }
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(model.path == nil)
                    if let result = model.result {
                        Text("\(result.rowCount) rows").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .padding()

            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .padding(.horizontal)
            }

            Divider()
            if let result = model.result {
                ResultGridView(result: result)
            } else {
                Spacer()
            }
        }
    }
}

/// A minimal grid for the M0 result preview. Replaced by a virtualised
/// NSTableView-backed grid in M2.
struct ResultGridView: View {
    let result: QueryResult

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 3) {
                GridRow {
                    ForEach(result.columns, id: \.name) { column in
                        Text(column.name).font(.caption.bold())
                    }
                }
                ForEach(Array(result.rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(cell.displayString)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(cell.isNull ? .secondary : .primary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding()
        }
    }
}

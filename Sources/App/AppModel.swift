import SwiftUI
import DuckDBKit

/// Single source of truth for the window: the open lake, its snapshots and schema, the
/// active time context, selection, and appearance. Views bind to this; only this touches
/// the `LakeSession` actor.
@MainActor
@Observable
final class AppModel {
    // Connection
    private(set) var lakePath: String?
    private(set) var backend: String?          // ducklake_settings().catalog_type
    private(set) var extensionVersion: String?

    // Data
    private(set) var snapshots: [Snapshot] = []
    private(set) var schemaRoots: [CatalogNode] = []
    var activeSnapshot: Snapshot?
    var selectedNodeID: String?
    var expandedNodeIDs: Set<String> = []

    // Workbench
    enum DetailMode: String, CaseIterable, Sendable {
        case inspect = "Inspect", query = "Query", diff = "Diff", map = "Map"
    }
    var detailMode: DetailMode = .inspect
    var sql: String = ""
    private(set) var queryResult: QueryResult?
    private(set) var queryError: String?
    private(set) var isQuerying = false
    private(set) var queryRowsCapped = false
    private var queryTask: Task<Void, Never>?
    private let queryRowCap = 5000

    // Chrome
    var appearanceOverride: ColorScheme?
    private(set) var errorText: String?
    private(set) var isLoading = false

    private var session: LakeSession?
    private(set) var recents: [RecentConnection] = []
    private let recentsKey = "recentLakes.v1"

    init() { loadRecents() }

    var lakeName: String? { lakePath.map { ($0 as NSString).lastPathComponent } }

    var selectedNode: CatalogNode? {
        guard let id = selectedNodeID else { return nil }
        return Self.find(id, in: schemaRoots)
    }

    func isExpanded(_ id: String) -> Bool { expandedNodeIDs.contains(id) }
    func setExpanded(_ id: String, _ value: Bool) {
        if value { expandedNodeIDs.insert(id) } else { expandedNodeIDs.remove(id) }
    }
    func toggleExpanded(_ id: String) {
        if expandedNodeIDs.contains(id) { expandedNodeIDs.remove(id) } else { expandedNodeIDs.insert(id) }
    }

    // MARK: Opening

    func open(path: String) async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            let session = try LakeSession()
            try await session.loadCoreExtensions()
            let source: LakeSource = path.lowercased().hasSuffix(".sqlite")
                ? .sqliteFile(path) : .duckDBFile(path)
            try await session.attach(source)
            self.session = session
            self.lakePath = path

            let settings = try await session.query(
                "SELECT catalog_type, extension_version FROM ducklake_settings('lake');")
            if let row = settings.rows.first {
                backend = row[0].displayString
                extensionVersion = row[1].displayString
            }
            try await loadSnapshots()
            try await loadSchema()
            if sql.isEmpty {
                sql = """
                    SELECT snapshot_id, snapshot_time, schema_version
                    FROM ducklake_snapshots('lake')
                    ORDER BY snapshot_id DESC
                    LIMIT 200;
                    """
            }
            addRecent(path: path)
        } catch {
            errorText = String(describing: error)
        }
    }

    // MARK: Recents

    func loadRecents() {
        guard let data = UserDefaults.standard.data(forKey: recentsKey),
              let list = try? JSONDecoder().decode([RecentConnection].self, from: data) else { return }
        recents = list.sorted { $0.lastOpened > $1.lastOpened }
    }

    private func addRecent(path: String) {
        let kind = path.lowercased().hasSuffix(".sqlite") ? "sqlite" : "duckdb"
        let entry = RecentConnection(
            path: path, name: (path as NSString).lastPathComponent, kind: kind,
            snapshotCount: snapshots.count, lastOpened: Date())
        recents = Array(([entry] + recents.filter { $0.path != path }).prefix(12))
        if let data = try? JSONEncoder().encode(recents) {
            UserDefaults.standard.set(data, forKey: recentsKey)
        }
    }

    // MARK: Workbench

    /// Runs the editor's SQL off the main thread, capping collected rows for the grid.
    /// A light read-only guard rejects obvious mutations (the attach is read-only anyway).
    func runQuery() {
        guard session != nil else { return }
        let head = String(sql.drop(while: \.isWhitespace).prefix(while: { $0.isLetter || $0 == "_" })).uppercased()
        let banned: Set<String> = ["INSERT", "UPDATE", "DELETE", "CREATE", "DROP", "ALTER",
                                   "TRUNCATE", "MERGE", "ATTACH", "DETACH", "COPY"]
        if banned.contains(head) {
            queryError = "Read-only explorer — \(head) statements aren't allowed."
            queryResult = nil
            return
        }

        queryTask?.cancel()
        isQuerying = true
        queryError = nil
        queryRowsCapped = false
        let sqlToRun = sql
        let cap = queryRowCap
        queryTask = Task { [weak self] in
            guard let self, let session = self.session else { return }
            do {
                let result = try await session.query(sqlToRun, maxRows: cap)
                if !Task.isCancelled {
                    self.queryResult = result
                    self.queryRowsCapped = result.rowCount >= cap
                    self.queryError = nil
                }
            } catch {
                if !Task.isCancelled {
                    self.queryError = String(describing: error)
                    self.queryResult = nil
                }
            }
            if !Task.isCancelled { self.isQuerying = false }
        }
    }

    /// Interrupts an in-flight query (thread-safe) and drops the task.
    func cancelQuery() {
        session?.cancel()
        queryTask?.cancel()
        isQuerying = false
    }

    /// Runs an arbitrary read-only query against the open lake (used by detail panes).
    func query(_ sql: String, maxRows: Int? = nil) async throws -> QueryResult {
        guard let session else { throw DuckError.connect("no lake open") }
        return try await session.query(sql, maxRows: maxRows)
    }

    func activate(_ snapshot: Snapshot) {
        guard snapshot.id != activeSnapshot?.id, let session else { return }
        activeSnapshot = snapshot
        // The newest snapshot is "latest" (no version constraint); otherwise pin to it.
        let version: Int64? = (snapshot.id == snapshots.first?.id) ? nil : snapshot.id
        Task {
            do {
                try await session.timeTravel(to: version)
                try await loadSchema()   // reflects schema evolution as-of this snapshot
            } catch {
                errorText = String(describing: error)
            }
        }
    }

    // MARK: Loading

    private func loadSnapshots() async throws {
        guard let session else { return }
        let result = try await session.query("""
            SELECT snapshot_id, snapshot_time::VARCHAR, schema_version,
                   CAST(changes AS VARCHAR), author, commit_message,
                   CAST(commit_extra_info AS VARCHAR)
            FROM ducklake_snapshots('lake')
            ORDER BY snapshot_id DESC;
            """)
        snapshots = result.rows.compactMap(Snapshot.init(row:))
        activeSnapshot = snapshots.first   // newest
    }

    private func loadSchema() async throws {
        guard let session else { return }
        let tables = try await session.query("""
            SELECT table_name, table_type FROM information_schema.tables
            WHERE table_catalog = 'lake' AND table_schema = 'main'
            ORDER BY table_name;
            """)
        let columns = try await session.query("""
            SELECT table_name, column_name, data_type, is_nullable
            FROM information_schema.columns
            WHERE table_catalog = 'lake' AND table_schema = 'main'
            ORDER BY table_name, ordinal_position;
            """)

        var columnsByTable: [String: [CatalogNode]] = [:]
        for row in columns.rows {
            let table = row[0].displayString
            let column = row[1].displayString
            columnsByTable[table, default: []].append(
                CatalogNode(
                    id: "lake.main.\(table).\(column)", name: column, kind: .column,
                    dataType: row[2].displayString, nullable: row[3].displayString == "YES",
                    children: nil))
        }

        let tableNodes: [CatalogNode] = tables.rows.map { row in
            let table = row[0].displayString
            let isView = row[1].displayString.uppercased().contains("VIEW")
            return CatalogNode(
                id: "lake.main.\(table)", name: table, kind: isView ? .view : .table,
                dataType: nil, nullable: false, children: columnsByTable[table] ?? [])
        }

        let schema = CatalogNode(
            id: "lake.main", name: "main", kind: .schema, dataType: nil, nullable: false,
            children: tableNodes)
        schemaRoots = [CatalogNode(
            id: "lake", name: lakeName ?? "lake", kind: .catalog, dataType: nil, nullable: false,
            children: [schema])]
        if expandedNodeIDs.isEmpty {
            expandedNodeIDs = Self.branchIDs(schemaRoots)   // open fully on first load
        }
        // Keep the current selection if it still exists as-of this snapshot; else pick richest.
        if selectedNodeID == nil || Self.find(selectedNodeID!, in: schemaRoots) == nil {
            selectedNodeID = tableNodes.max { ($0.children?.count ?? 0) < ($1.children?.count ?? 0) }?.id
        }
    }

    private static func branchIDs(_ nodes: [CatalogNode]) -> Set<String> {
        var ids = Set<String>()
        for node in nodes where !(node.children ?? []).isEmpty {
            ids.insert(node.id)
            ids.formUnion(branchIDs(node.children ?? []))
        }
        return ids
    }

    private static func find(_ id: String, in nodes: [CatalogNode]) -> CatalogNode? {
        for node in nodes {
            if node.id == id { return node }
            if let children = node.children, let hit = find(id, in: children) { return hit }
        }
        return nil
    }
}

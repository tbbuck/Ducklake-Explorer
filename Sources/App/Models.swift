import Foundation
import DuckDBKit

/// One `ducklake_snapshots()` row — a lamina in the stratigraphic log.
struct Snapshot: Identifiable, Sendable, Hashable {
    let id: Int64            // snapshot_id
    let time: String
    let schemaVersion: Int64
    let changes: String      // CAST(changes AS VARCHAR), e.g. "{tables_inserted_into=[1]}"
    let author: String?
    let commitMessage: String?
    let commitExtraInfo: String?

    /// A short human tag derived from the `changes` map (e.g. "insert", "schema", "delete").
    var changeTag: String {
        let c = changes.lowercased()
        if c.contains("schema") || c.contains("created") || c.contains("altered") { return "schema" }
        if c.contains("delete") { return "delete" }
        if c.contains("inserted") { return "insert" }
        return "change"
    }

    init?(row: [DuckValue]) {
        guard row.count >= 7, let id = row[0].int64 else { return nil }
        self.id = id
        self.time = row[1].displayString
        self.schemaVersion = row[2].int64 ?? 0
        self.changes = row[3].displayString
        self.author = row[4].isNull ? nil : row[4].displayString
        self.commitMessage = row[5].isNull ? nil : row[5].displayString
        self.commitExtraInfo = row[6].isNull ? nil : row[6].displayString
    }
}

/// A node in the schema tree: catalog → schema → table/view → column.
struct CatalogNode: Identifiable, Hashable, Sendable {
    enum Kind: Sendable { case catalog, schema, table, view, column }

    let id: String           // stable dotted path, e.g. "lake.main.observations.geom"
    let name: String
    let kind: Kind
    let dataType: String?    // for columns
    let nullable: Bool
    var children: [CatalogNode]?

    var isGeometry: Bool { (dataType ?? "").uppercased().contains("GEOMETRY") }

    var symbol: String {
        switch kind {
        case .catalog: return "cylinder.split.1x2"
        case .schema:  return "square.stack.3d.up"
        case .table:   return "tablecells"
        case .view:    return "eye"
        case .column:  return isGeometry ? "dot.scope" : "number"
        }
    }
}

/// One physical file backing a table — a Parquet data file or its delete (erosion) file.
/// Sourced from `ducklake_list_files` (catalog metadata; readable even when data is remote).
struct DataFile: Identifiable, Sendable {
    enum Kind: Sendable { case data, delete }
    let id: String        // the file path (unique per table)
    let path: String
    let sizeBytes: Int64
    let kind: Kind

    var name: String { (path as NSString).lastPathComponent }
}

/// A schema diff between two snapshots, computed from the catalog's version ranges.
struct SnapshotDiff: Sendable {
    var tablesAdded: [String] = []
    var tablesDropped: [String] = []
    var columnsAdded: [String] = []       // "table.column"
    var columnsDropped: [String] = []     // "table.column"
    var columnsChanged: [String] = []     // "table.column: oldType → newType"

    var isEmpty: Bool {
        tablesAdded.isEmpty && tablesDropped.isEmpty && columnsAdded.isEmpty
            && columnsDropped.isEmpty && columnsChanged.isEmpty
    }
}

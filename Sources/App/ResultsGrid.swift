import SwiftUI
import AppKit
import DuckDBKit

/// A virtualised results grid backed by `NSTableView` — handles large result sets where
/// SwiftUI's `Table` can't. Numeric columns are right-aligned; nulls are muted.
struct ResultsGrid: NSViewRepresentable {
    let result: QueryResult

    func makeCoordinator() -> Coordinator { Coordinator(result: result) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        table.style = .plain
        table.usesAlternatingRowBackgroundColors = false
        table.backgroundColor = .stratumGrid(0xEFEEE7, 0x1E1F22)
        table.gridStyleMask = [.solidHorizontalGridLineMask]
        table.gridColor = .stratumGrid(0xDAD5C9, 0x393B40)
        table.rowHeight = 22
        table.intercellSpacing = NSSize(width: 8, height: 0)
        table.headerView = NSTableHeaderView()
        table.allowsColumnResizing = true
        table.allowsMultipleSelection = true
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        context.coordinator.table = table
        context.coordinator.rebuildColumns(for: result)

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .stratumGrid(0xEFEEE7, 0x1E1F22)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.result = result
        guard let table = scroll.documentView as? NSTableView else { return }
        context.coordinator.rebuildColumns(for: result)
        table.reloadData()
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var result: QueryResult
        weak var table: NSTableView?
        private var signature: [String] = []

        init(result: QueryResult) { self.result = result }

        /// Rebuilds columns only when the shape actually changes (avoids churn on reload).
        func rebuildColumns(for result: QueryResult) {
            guard let table else { return }
            let newSignature = result.columns.map { "\($0.name)|\($0.type.label)" }
            guard newSignature != signature else { return }
            signature = newSignature
            for column in table.tableColumns { table.removeTableColumn(column) }
            for (index, column) in result.columns.enumerated() {
                let tableColumn = NSTableColumn(identifier: .init("c\(index)"))
                tableColumn.title = column.name
                tableColumn.width = 150
                tableColumn.minWidth = 48
                tableColumn.resizingMask = .userResizingMask
                tableColumn.headerCell.font = Self.mono(11, bold: true)
                table.addTableColumn(tableColumn)
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int { result.rows.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn,
                  let index = Int(tableColumn.identifier.rawValue.dropFirst()),
                  row < result.rows.count, index < result.rows[row].count
            else { return nil }

            let field = tableView.makeView(withIdentifier: tableColumn.identifier, owner: self) as? NSTextField
                ?? {
                    let textField = NSTextField(labelWithString: "")
                    textField.identifier = tableColumn.identifier
                    textField.font = Self.mono(11)
                    textField.lineBreakMode = .byTruncatingTail
                    textField.cell?.usesSingleLineMode = true
                    return textField
                }()

            let value = result.rows[row][index]
            field.stringValue = value.isNull ? "NULL" : value.displayString
            field.textColor = value.isNull
                ? .stratumGrid(0x6C736E, 0x8B9099)
                : .stratumGrid(0x223038, 0xE3E5EA)
            field.alignment = result.columns[index].type.isNumeric ? .right : .left
            return field
        }

        private static func mono(_ size: CGFloat, bold: Bool = false) -> NSFont {
            let name = bold ? "JetBrainsMono-SemiBold" : "JetBrains Mono"
            return NSFont(name: name, size: size)
                ?? NSFont(name: "JetBrains Mono", size: size)
                ?? .monospacedSystemFont(ofSize: size, weight: bold ? .semibold : .regular)
        }
    }
}

private extension NSColor {
    /// Dynamic light/dark NSColor mirroring the Stratum palette (for AppKit views).
    static func stratumGrid(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        }
    }
}

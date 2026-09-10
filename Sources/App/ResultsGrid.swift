import SwiftUI
import AppKit
import DuckDBKit

/// A virtualised results grid backed by `NSTableView` — handles large result sets where
/// SwiftUI's `Table` can't. Column headers show the name over its data type; cells are
/// coloured by type (numeric = brass, varchar/null = grey, everything else = teal); numeric
/// columns are right-aligned. Column widths default to the content about to be shown, with
/// varchars capped so they can't run away.
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
        table.headerView = StratumHeaderView()
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
                let header = StratumHeaderCell(textCell: column.name)
                header.typeText = column.type.label
                header.typeColor = Self.typeAccent(column.type)
                tableColumn.headerCell = header
                tableColumn.width = Self.width(for: index, in: result)
                tableColumn.minWidth = 56
                tableColumn.resizingMask = .userResizingMask
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
                    textField.font = stratumMonoFont(12)
                    textField.lineBreakMode = .byTruncatingTail
                    textField.cell?.usesSingleLineMode = true
                    return textField
                }()

            let value = result.rows[row][index]
            let type = result.columns[index].type
            field.stringValue = value.isNull ? "NULL" : value.displayString
            field.textColor = Self.valueColor(type, isNull: value.isNull)
            field.alignment = type.isNumeric ? .right : .left
            return field
        }

        // MARK: Type-driven colour & width

        /// Cell text colour: null/varchar → grey, numeric → brass, everything else → teal.
        static func valueColor(_ type: DuckTypeID, isNull: Bool) -> NSColor {
            if isNull { return .stratumGrid(0x6C736E, 0x8B9099) }        // muted-2 grey
            if type == .varchar { return .stratumGrid(0x515B5A, 0xB4B8C0) }  // muted grey
            if type.isNumeric { return .stratumGrid(0xA97B36, 0xD6A55D) }    // brass / "orange"
            return .stratumGrid(0x1E7A72, 0x3FA091)                          // ink-teal / "green"
        }

        /// The header's type label colour: brass, but teal for geometry/boolean (per tokens).
        static func typeAccent(_ type: DuckTypeID) -> NSColor {
            switch type {
            case .geometry, .boolean: return .stratumGrid(0x1E7A72, 0x3FA091)
            default:                  return .stratumGrid(0xA97B36, 0xD6A55D)
            }
        }

        /// A sensible default width from the header name and a sample of the values, capped so
        /// varchars (measured up to 64 chars) can't run away.
        static func width(for index: Int, in result: QueryResult) -> CGFloat {
            let column = result.columns[index]
            let charW = ("0" as NSString).size(withAttributes: [.font: stratumMonoFont(12)]).width
            var maxChars = column.name.count
            let sample = min(result.rows.count, 200)
            for r in 0..<sample {
                let cell = result.rows[r][index]
                let length = cell.isNull ? 4 : min(cell.displayString.count, 64)
                if length > maxChars { maxChars = length }
            }
            let content = CGFloat(maxChars) * charW + 20   // + cell inset / grid spacing
            let cap: CGFloat = (column.type == .varchar) ? 300 : 460
            return min(max(content, 60), cap)
        }
    }
}

/// A flat, two-line column header: the column name over its data type, styled per Stratum.
final class StratumHeaderCell: NSTableHeaderCell {
    var typeText: String = ""
    var typeColor: NSColor = .secondaryLabelColor

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        NSColor.stratumGrid(0xFCFBF6, 0x303236).setFill()          // panel-2 header ground
        cellFrame.fill()
        NSColor.stratumGrid(0xDAD5C9, 0x393B40).setFill()          // bottom hairline
        NSRect(x: cellFrame.minX, y: cellFrame.maxY - 1, width: cellFrame.width, height: 1).fill()
        drawInterior(withFrame: cellFrame, in: controlView)
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        let inset: CGFloat = 9
        let width = max(0, cellFrame.width - inset - 6)
        (stringValue as NSString).draw(
            in: NSRect(x: cellFrame.minX + inset, y: cellFrame.minY + 5, width: width, height: 15),
            withAttributes: [.font: stratumMonoFont(11, semibold: true),
                             .foregroundColor: NSColor.stratumGrid(0x223038, 0xE3E5EA)])
        (typeText as NSString).draw(
            in: NSRect(x: cellFrame.minX + inset, y: cellFrame.minY + 21, width: width, height: 12),
            withAttributes: [.font: stratumMonoFont(9), .foregroundColor: typeColor])
    }
}

/// The header view, forced flipped (top-left origin, so the cell's two-line drawing is
/// predictable) and to a fixed taller height for the name-over-type layout.
final class StratumHeaderView: NSTableHeaderView {
    override var isFlipped: Bool { true }
    override var frame: NSRect {
        get { super.frame }
        set { super.frame = NSRect(origin: newValue.origin, size: NSSize(width: newValue.width, height: 40)) }
    }
}

/// JetBrains Mono at a size, falling back gracefully — shared by the grid cells and header.
private func stratumMonoFont(_ size: CGFloat, semibold: Bool = false) -> NSFont {
    let name = semibold ? "JetBrainsMono-SemiBold" : "JetBrains Mono"
    return NSFont(name: name, size: size)
        ?? NSFont(name: "JetBrains Mono", size: size)
        ?? .monospacedSystemFont(ofSize: size, weight: semibold ? .semibold : .regular)
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

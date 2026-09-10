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
        table.rowHeight = 24
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
                // Encode name + type in the cell's own title ("name\ntype"): NSCell copies its
                // built-in title correctly, whereas Swift ivars added to an NSCell subclass are
                // bitwise-copied without a retain and double-freed on teardown (crash).
                tableColumn.headerCell = StratumHeaderCell(textCell: "\(column.name)\n\(column.type.label)")
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
                    let cell = VCenterTextFieldCell()           // vertically centres text in the row
                    cell.isBordered = false
                    cell.drawsBackground = false
                    cell.usesSingleLineMode = true
                    cell.lineBreakMode = .byTruncatingTail
                    textField.cell = cell
                    textField.isEditable = false
                    textField.isSelectable = false
                    textField.identifier = tableColumn.identifier
                    textField.font = stratumMonoFont(12)
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

        /// A sensible default width from the header (name and type) and a sample of the values,
        /// capped so varchars (measured up to 64 chars) can't run away.
        static func width(for index: Int, in result: QueryResult) -> CGFloat {
            let column = result.columns[index]
            let charW = ("0" as NSString).size(withAttributes: [.font: stratumMonoFont(12)]).width
            var maxChars = max(column.name.count, column.type.label.count)
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

/// A flat, two-line column header: the column name over its data type. Name and type ride in
/// the cell's own `title` as "name\ntype" — deliberately no Swift stored properties, because
/// NSCell's bitwise `copyWithZone:` doesn't retain subclass ivars and double-frees them on
/// teardown (the close→reopen crash).
final class StratumHeaderCell: NSTableHeaderCell {
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        guard cellFrame.isValidForDrawing else { return }
        NSColor.stratumGrid(0xFCFBF6, 0x303236).setFill()          // panel-2 header ground
        cellFrame.fill()
        let flipped = controlView.isFlipped
        NSColor.stratumGrid(0xDAD5C9, 0x393B40).setFill()          // hairline along the bottom edge
        NSRect(x: cellFrame.minX, y: flipped ? cellFrame.maxY - 1 : cellFrame.minY,
               width: cellFrame.width, height: 1).fill()
        drawInterior(withFrame: cellFrame, in: controlView)
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        guard cellFrame.isValidForDrawing else { return }
        let parts = stringValue.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let name = parts.first.map(String.init) ?? stringValue
        let type = parts.count > 1 ? String(parts[1]) : ""
        let inset: CGFloat = 9
        let width = max(0, cellFrame.width - inset - 6)
        let flipped = controlView.isFlipped
        // Name on top, type below — positioned from the visual top of the header, either flip.
        let nameY = flipped ? cellFrame.minY + 9 : cellFrame.maxY - 24
        let typeY = flipped ? cellFrame.minY + 27 : cellFrame.maxY - 41
        (name as NSString).draw(
            in: NSRect(x: cellFrame.minX + inset, y: nameY, width: width, height: 15),
            withAttributes: [.font: stratumMonoFont(11, semibold: true),
                             .foregroundColor: NSColor.stratumGrid(0x223038, 0xE3E5EA)])
        if !type.isEmpty {
            (type as NSString).draw(
                in: NSRect(x: cellFrame.minX + inset, y: typeY, width: width, height: 14),
                withAttributes: [.font: stratumMonoFont(9), .foregroundColor: Self.typeColor(type)])
        }
    }

    /// Type-label colour derived from the label text: brass, teal for geometry/boolean.
    static func typeColor(_ label: String) -> NSColor {
        let u = label.uppercased()
        if u.contains("GEOMETRY") || u.contains("BOOL") { return .stratumGrid(0x1E7A72, 0x3FA091) }
        return .stratumGrid(0xA97B36, 0xD6A55D)
    }
}

/// The header view — forced to a fixed, taller height for the name-over-type layout.
final class StratumHeaderView: NSTableHeaderView {
    static let height: CGFloat = 48
    // NSTableView resizes the header via setFrameSize (which bypasses the `frame` setter), so
    // both must pin the height for the taller header to actually take and push the body down.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(NSSize(width: newSize.width, height: Self.height))
    }
    override var frame: NSRect {
        get { super.frame }
        set { super.frame = NSRect(origin: newValue.origin, size: NSSize(width: newValue.width, height: Self.height)) }
    }
}

/// JetBrains Mono at a size, falling back gracefully — shared by the grid cells and header.
private func stratumMonoFont(_ size: CGFloat, semibold: Bool = false) -> NSFont {
    let name = semibold ? "JetBrainsMono-SemiBold" : "JetBrains Mono"
    return NSFont(name: name, size: size)
        ?? NSFont(name: "JetBrains Mono", size: size)
        ?? .monospacedSystemFont(ofSize: size, weight: semibold ? .semibold : .regular)
}

/// A text field cell that vertically centres its single-line text within the row.
final class VCenterTextFieldCell: NSTextFieldCell {
    override func titleRect(forBounds rect: NSRect) -> NSRect {
        let textHeight = cellSize(forBounds: rect).height
        var r = rect
        let delta = (rect.height - textHeight) / 2
        if delta > 0 { r.origin.y += delta; r.size.height -= delta }
        return super.titleRect(forBounds: r)
    }
    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.drawInterior(withFrame: titleRect(forBounds: cellFrame), in: controlView)
    }
}

private extension NSRect {
    /// Guards custom drawing against the degenerate / NaN frames that can appear transiently
    /// during header relayout — a bad rect crashes CoreText.
    var isValidForDrawing: Bool {
        width > 1 && height > 1
            && origin.x.isFinite && origin.y.isFinite
            && size.width.isFinite && size.height.isFinite
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

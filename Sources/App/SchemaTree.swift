import SwiftUI

/// The middle pane: catalog → schema → table/view → column, as a **flat list of visible
/// rows** with custom chevrons (no DisclosureGroup — that trips a SwiftUI OutlineList crash
/// and is slow). Clicking a name selects it and toggles its collapse, animated.
struct SchemaTree: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelLabel("Schema")
            List {
                ForEach(model.visibleSchemaRows) { row in
                    SchemaRow(row: row)
                        .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 24)
        }
        .background(Palette.surface)
    }
}

private struct SchemaRow: View {
    @Environment(AppModel.self) private var model
    let row: SchemaRowItem

    private var node: CatalogNode { row.node }
    private var isBranch: Bool { !(node.children ?? []).isEmpty }
    private var isExpanded: Bool { model.isExpanded(node.id) }
    private var isSelected: Bool { model.selectedNodeID == node.id }

    var body: some View {
        HStack(spacing: 4) {
            Color.clear.frame(width: CGFloat(row.depth) * 13, height: 1)
            chevron
            Image(systemName: node.symbol)
                .font(.system(size: 11))
                .foregroundStyle(node.isGeometry ? Palette.geometry : Palette.textTertiary)
                .frame(width: 16)
            Text(node.name)
                .font(node.kind == .column ? .stratumMono(11) : .stratumUI(12, .semibold))
                .foregroundStyle(Palette.textPrimary).lineLimit(1)
            Spacer(minLength: 4)
            if let type = node.dataType {
                Text(type).font(.stratumMono(10)).foregroundStyle(typeColor(type)).lineLimit(1)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 5).fill(isSelected ? Palette.accentSoft : .clear))
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 1).fill(Palette.accent).frame(width: 2, height: 15)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            model.selectedNodeID = node.id
            if isBranch { toggle() }   // name click == arrow click
        }
        .contextMenu {
            if node.kind != .catalog && node.kind != .schema {
                Button("Add to query") { model.appendToQuery(node.name) }
            }
        }
    }

    @ViewBuilder private var chevron: some View {
        if isBranch {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 12)
                .contentShape(Rectangle())
                .onTapGesture { toggle() }
        } else {
            Color.clear.frame(width: 12, height: 1)
        }
    }

    private func toggle() {
        withAnimation(.easeInOut(duration: 0.18)) { model.toggleExpanded(node.id) }
    }
}

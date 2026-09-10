import SwiftUI

/// The middle pane: catalog → schema → table/view → column. Clicking a row's name toggles
/// its collapse (same as the disclosure arrow) and selects it, driving the detail pane.
struct SchemaTree: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelLabel("Schema")
            List {
                ForEach(model.schemaRoots) { node in
                    SchemaNode(node: node)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .background(Palette.surface)
    }
}

private struct SchemaNode: View {
    @Environment(AppModel.self) private var model
    let node: CatalogNode

    private var isBranch: Bool { !(node.children ?? []).isEmpty }

    var body: some View {
        if isBranch {
            DisclosureGroup(isExpanded: expanded) {
                ForEach(node.children ?? []) { SchemaNode(node: $0) }
            } label: {
                NodeRow(node: node, selected: model.selectedNodeID == node.id)
                    .onTapGesture {
                        model.selectedNodeID = node.id
                        model.toggleExpanded(node.id)   // name click == arrow click
                    }
            }
        } else {
            NodeRow(node: node, selected: model.selectedNodeID == node.id)
                .onTapGesture { model.selectedNodeID = node.id }
        }
    }

    private var expanded: Binding<Bool> {
        Binding(get: { model.isExpanded(node.id) }, set: { model.setExpanded(node.id, $0) })
    }
}

/// One tree row; columns carry a type label (brass, teal for geometry/boolean) and the
/// geometry ⌖ marker. Selected rows get the accent-soft fill + a short accent rail.
private struct NodeRow: View {
    let node: CatalogNode
    let selected: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: node.symbol)
                .font(.system(size: 11))
                .foregroundStyle(node.isGeometry ? Palette.geometry : Palette.textTertiary)
                .frame(width: 16)
            Text(node.name)
                .font(node.kind == .column ? .stratumMono(11) : .stratumUI(12, .semibold))
                .foregroundStyle(Palette.textPrimary)
            Spacer(minLength: 4)
            if let type = node.dataType {
                Text(type).font(.stratumMono(10)).foregroundStyle(typeColor(type))
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 5).fill(selected ? Palette.accentSoft : .clear))
        .overlay(alignment: .leading) {
            if selected {
                RoundedRectangle(cornerRadius: 1).fill(Palette.accent).frame(width: 2, height: 15)
            }
        }
        .contentShape(Rectangle())
    }
}

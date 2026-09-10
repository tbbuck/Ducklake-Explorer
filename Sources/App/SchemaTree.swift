import SwiftUI

/// The middle pane: catalog → schema → table/view → column, driving the detail pane.
struct SchemaTree: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            PanelLabel("Schema")
            List(selection: $model.selectedNodeID) {
                OutlineGroup(model.schemaRoots, children: \.children) { node in
                    NodeRow(node: node).tag(node.id)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .background(Palette.surface)
    }
}

/// One tree row; columns carry a type badge and a geometry marker.
private struct NodeRow: View {
    let node: CatalogNode

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: node.symbol)
                .font(.system(size: 11))
                .foregroundStyle(node.isGeometry ? Palette.geometry : Palette.textTertiary)
                .frame(width: 16)
            Text(node.name)
                .font(node.kind == .column ? .stratumMono(11) : .stratumUI(12, .medium))
                .foregroundStyle(Palette.textPrimary)
            Spacer(minLength: 4)
            if let type = node.dataType {
                Text(type)
                    .font(.stratumMono(9))
                    .foregroundStyle(Palette.textTertiary)
                if !node.nullable {
                    Text("•").foregroundStyle(Palette.accent).font(.system(size: 8))
                }
            }
        }
        .padding(.vertical, 1)
    }
}

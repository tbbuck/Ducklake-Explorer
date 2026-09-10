import SwiftUI

/// The right pane: the table inspector when a table/view is selected, else an empty state.
struct DetailPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.detailMode == .query {
                WorkbenchView()
            } else if model.detailMode == .diff {
                SnapshotDiffView()
            } else if model.detailMode == .map {
                MapPane()
            } else if model.detailMode == .metadata {
                MetadataBrowser()
            } else if let node = model.selectedNode, node.kind == .table || node.kind == .view {
                TableInspector(node: node)
            } else {
                EmptyState()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.base)
    }
}

private struct EmptyState: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 32)).foregroundStyle(Palette.textTertiary)
            Text("Select a table to inspect it")
                .font(.stratumUI(13)).foregroundStyle(Palette.textSecondary)
        }
    }
}

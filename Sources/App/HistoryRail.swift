import SwiftUI

/// The leftmost pane: snapshot history as a stratigraphic log, newest at the top, with the
/// continuous teal `CoreSpine` running down its leading edge.
struct HistoryRail: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelLabel("History")
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    CoreSpine()
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.snapshots) { snapshot in
                            SnapshotLamina(
                                snapshot: snapshot,
                                isActive: snapshot.id == model.activeSnapshot?.id
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { model.activate(snapshot) }
                            Divider().overlay(Palette.hairline)
                        }
                    }
                }
            }
        }
        .background(Palette.surface)
    }
}

/// The depth gradient behind the laminae — "you are here in time".
private struct CoreSpine: View {
    var body: some View {
        Palette.coreSpine
            .frame(width: 7)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .padding(.leading, 6).padding(.vertical, 4)
    }
}

/// One snapshot, collapsed: version, relative time, change tag, and message/summary.
struct SnapshotLamina: View {
    let snapshot: Snapshot
    let isActive: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            marker
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(verbatim: "v\(snapshot.id)")
                        .font(.stratumMono(12, .semibold))
                        .foregroundStyle(isActive ? Palette.accent : Palette.textPrimary)
                    Badge(text: snapshot.changeTag, color: tagColor)
                    Spacer(minLength: 0)
                }
                Text(snapshot.commitMessage ?? summary)
                    .font(.stratumUI(11))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(2)
                Text(snapshot.time)
                    .font(.stratumMono(9))
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .padding(.vertical, 9).padding(.leading, 10).padding(.trailing, 12)
        .background(isActive ? Palette.accentSoft : .clear)
        .overlay(alignment: .leading) {
            if isActive { Rectangle().fill(Palette.accent).frame(width: 2) }
        }
    }

    private var marker: some View {
        Circle()
            .fill(isActive ? Palette.accent : Palette.accentDim)
            .frame(width: 7, height: 7)
            .padding(.top, 4)
            .overlay {
                if isActive {
                    Circle().stroke(Palette.accent.opacity(0.35), lineWidth: 4).frame(width: 13, height: 13)
                }
            }
    }

    /// Strips the DuckLake `changes` map to a compact human summary.
    private var summary: String {
        snapshot.changes
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
            .replacingOccurrences(of: "=", with: " ")
    }

    private var tagColor: Color {
        switch snapshot.changeTag {
        case "delete", "schema": return Palette.accent2   // tokens: deletes/alters use accent-2
        default: return Palette.accent
        }
    }
}

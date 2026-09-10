import SwiftUI

/// Small type/state label (backend, read-only, change kind).
struct Badge: View {
    let text: String
    var color: Color = Palette.accent
    var body: some View {
        Text(text.uppercased())
            .font(.stratumMono(9, .medium))
            .tracking(0.4)
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
    }
}

/// The mono section eyebrow with a hairline rule — Stratum's `PanelLabel`.
struct PanelLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack(spacing: 8) {
            Text(text.uppercased())
                .font(.stratumMono(10, .medium))
                .tracking(1.2)
                .foregroundStyle(Palette.textTertiary)
            Rectangle().fill(Palette.hairline).frame(height: 1)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

/// The "as of vN" pill showing the active time context.
struct SnapshotChip: View {
    let snapshot: Snapshot?
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "clock.arrow.circlepath").font(.system(size: 10))
            Text(verbatim: snapshot.map { "as of v\($0.id)" } ?? "latest").font(.stratumMono(11, .medium))
        }
        .foregroundStyle(Palette.onCool)
        .padding(.horizontal, 11).padding(.vertical, 5)
        .background(Palette.accent, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Sun/moon control that drives `AppModel.appearanceOverride` (defaults to system).
struct ThemeToggle: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Button {
            switch model.appearanceOverride {
            case .none:       model.appearanceOverride = .dark
            case .some(.dark): model.appearanceOverride = .light
            default:          model.appearanceOverride = nil
            }
        } label: {
            Image(systemName: symbol).font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.textSecondary)
        .help("Appearance: \(label)")
    }
    private var symbol: String {
        switch model.appearanceOverride {
        case .some(.dark): return "moon.fill"
        case .some(.light): return "sun.max.fill"
        default: return "circle.lefthalf.filled"
        }
    }
    private var label: String {
        switch model.appearanceOverride {
        case .some(.dark): return "night"
        case .some(.light): return "day"
        default: return "system"
        }
    }
}

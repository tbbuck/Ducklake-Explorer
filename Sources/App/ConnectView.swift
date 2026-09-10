import SwiftUI
import Foundation

/// The pre-open screen: recent lakes on the left, an open panel (local file / remote URL)
/// on the right. Replaces the DEBUG auto-open as the real entry point.
struct ConnectView: View {
    @Environment(AppModel.self) private var model
    let openLocal: () -> Void
    @State private var remoteURL = ""

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Image(systemName: "cylinder.split.1x2").font(.system(size: 34)).foregroundStyle(Palette.accent)
                Text("DuckLake Explorer").font(.stratumDisplay(24)).foregroundStyle(Palette.textPrimary)
                Text("Open a lake to explore its schema, snapshots, files, and data — read-only.")
                    .font(.stratumUI(12)).foregroundStyle(Palette.textSecondary)
            }
            .padding(.top, 44).padding(.bottom, 26)

            HStack(alignment: .top, spacing: 24) {
                recents
                openPanel
            }
            .frame(maxWidth: 860)
            .padding(.horizontal, 24)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.base)
    }

    private var recents: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelLabel("Recent lakes")
            if model.recents.isEmpty {
                Text("No lakes yet — open one on the right.")
                    .font(.stratumUI(12)).foregroundStyle(Palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(model.recents) { recent in
                            RecentLakeCard(recent: recent) { Task { await model.open(path: recent.path) } }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: 340)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var openPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelLabel("Open a lake")
            VStack(alignment: .leading, spacing: 12) {
                Button(action: openLocal) {
                    Label("Choose a .ducklake / .sqlite file…", systemImage: "folder")
                        .font(.stratumUI(13, .medium)).frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent).tint(Palette.accent)

                Text("OR A REMOTE CATALOG").font(.stratumMono(9, .medium)).tracking(0.8)
                    .foregroundStyle(Palette.textTertiary).padding(.top, 4)
                HStack(spacing: 8) {
                    TextField("s3://… or https://…", text: $remoteURL)
                        .textFieldStyle(.roundedBorder).font(.stratumMono(11))
                    Button("Open") {
                        let url = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !url.isEmpty else { return }
                        Task { await model.open(path: url) }
                    }
                    .disabled(remoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Label("Read-only. Remote data uses your existing DuckDB secrets — no credentials are entered or stored here.",
                      systemImage: "lock.shield")
                    .font(.stratumUI(10)).foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.hairline))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One remembered lake — click to reopen. Never shows credentials.
struct RecentLakeCard: View {
    let recent: RecentConnection
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: recent.kind == "sqlite" ? "cylinder" : "cylinder.split.1x2")
                    .font(.system(size: 18)).foregroundStyle(Palette.accent).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(recent.name).font(.stratumUI(14, .semibold)).foregroundStyle(Palette.textPrimary)
                    Text(recent.path).font(.stratumMono(9)).foregroundStyle(Palette.textTertiary)
                        .lineLimit(1).truncationMode(.middle)
                    Text("\(recent.snapshotCount) snapshots · \(Self.relative.localizedString(for: recent.lastOpened, relativeTo: Date()))")
                        .font(.stratumMono(9)).foregroundStyle(Palette.textSecondary)
                }
                Spacer(minLength: 8)
                Badge(text: recent.kind)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.hairline))
        }
        .buttonStyle(.plain)
    }

    private static let relative = RelativeDateTimeFormatter()
}

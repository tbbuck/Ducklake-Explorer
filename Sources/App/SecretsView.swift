import SwiftUI
import DuckDBKit

/// One `duckdb_secrets()` row — what the app knows about a secret (never the credentials).
struct SecretInfo: Identifiable, Sendable {
    let name: String
    let type: String
    let provider: String
    let persistent: Bool
    let scope: String
    var id: String { "\(type)/\(name)" }
}

/// The secrets-view page (a sheet): a read-only list of the DuckDB secrets on this machine.
/// It's informational — DuckDB picks the matching secret by scope; the app never enters,
/// stores, or lets you hand-pick credentials.
struct SecretsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var secrets: [SecretInfo] = []
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("DuckDB secrets").font(.stratumDisplay(18)).foregroundStyle(Palette.textPrimary)
                Spacer()
                Button("Done") { dismiss() }.pointerStyle(.link)
            }
            .padding(16)
            Divider().overlay(Palette.hairline)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Matched to remote paths by scope automatically — you don't pick one. The app never enters or stores credentials.",
                          systemImage: "lock.shield")
                        .font(.stratumUI(11)).foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !loaded {
                        ProgressView().controlSize(.small).padding(.vertical, 10)
                    } else if secrets.isEmpty {
                        Text("No DuckDB secrets found. Create one with a CREATE PERSISTENT SECRET… statement (e.g. TYPE s3, SCOPE 's3://your-bucket/') to reach remote catalogs.")
                            .font(.stratumMono(10)).foregroundStyle(Palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true).padding(.vertical, 6)
                    } else {
                        ForEach(secrets) { SecretRow(secret: $0) }
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 540, height: 460)
        .background(Palette.base)
        .task {
            secrets = await model.fetchSecrets()
            loaded = true
        }
    }
}

/// One secret at a glance — name, type, persistence, scope, provider. No credentials.
struct SecretRow: View {
    let secret: SecretInfo

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "key.horizontal")
                .font(.system(size: 15)).foregroundStyle(Palette.accent).frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(secret.name.isEmpty ? "(unnamed)" : secret.name)
                        .font(.stratumUI(13, .semibold)).foregroundStyle(Palette.textPrimary)
                    Badge(text: secret.type)
                    if secret.persistent { Badge(text: "persistent", color: Palette.accentDim) }
                }
                Text(secret.scope.isEmpty ? "no scope — applies to all paths of its type" : secret.scope)
                    .font(.stratumMono(9)).foregroundStyle(Palette.textTertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if !secret.provider.isEmpty {
                Text(secret.provider).font(.stratumMono(9)).foregroundStyle(Palette.textTertiary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.hairline))
    }
}

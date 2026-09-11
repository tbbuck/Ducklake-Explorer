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
                    Label("DuckDB matches a secret to a remote path by scope automatically — you don't pick one. Add a secret below to reach a remote catalog; persistent ones are stored by DuckDB under ~/.duckdb.",
                          systemImage: "lock.shield")
                        .font(.stratumUI(11)).foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !loaded {
                        ProgressView().controlSize(.small).padding(.vertical, 10)
                    } else if secrets.isEmpty {
                        Text("No DuckDB secrets yet. Add one below to reach a remote (S3) catalog.")
                            .font(.stratumMono(10)).foregroundStyle(Palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true).padding(.vertical, 6)
                    } else {
                        ForEach(secrets) { SecretRow(secret: $0) }
                    }

                    Divider().overlay(Palette.hairline).padding(.top, 4)
                    NewSecretForm(onCreated: { Task { secrets = await model.fetchSecrets() } })
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

/// Collapsible form to create a new S3-family DuckDB secret, so a user with no DuckDB install
/// can still reach remote catalogs. Persistent secrets are written to `~/.duckdb` (survive
/// restarts, visible to the CLI); otherwise the secret lasts only for this run. The secret key
/// is entered in a `SecureField` and never echoed back.
private struct NewSecretForm: View {
    @Environment(AppModel.self) private var model
    var onCreated: () -> Void

    @State private var expanded = false
    @State private var name = ""
    @State private var type = "s3"
    @State private var keyID = ""
    @State private var secret = ""
    @State private var endpoint = ""
    @State private var region = ""
    @State private var urlStyle = "path"
    @State private var scope = ""
    @State private var persist = true
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) {
                row("Name", "optional", $name)
                row("Type", "s3", $type)
                row("Key ID", "", $keyID)
                row("Secret", "", $secret, secure: true)
                row("Endpoint", "optional — for S3-compatible stores", $endpoint)
                row("Region", "optional", $region)
                HStack(spacing: 8) {
                    Text("URL style").font(.stratumUI(11)).foregroundStyle(Palette.textSecondary)
                        .frame(width: 96, alignment: .leading)
                    Picker("", selection: $urlStyle) {
                        Text("path").tag("path"); Text("vhost").tag("vhost")
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 180)
                    Spacer()
                }
                row("Scope", "e.g. s3://bucket/ — comma-separate several", $scope)
                Toggle(isOn: $persist) {
                    Text("Keep after quitting (persistent)")
                        .font(.stratumUI(11)).foregroundStyle(Palette.textSecondary)
                }
                .toggleStyle(.switch).controlSize(.mini)

                if let error {
                    Text(error).font(.stratumMono(10)).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    Text(persist ? "Written to ~/.duckdb — survives restarts; the duckdb CLI sees it too."
                                 : "Kept in memory for this run only.")
                        .font(.stratumMono(9)).foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button(busy ? "Creating…" : "Create secret") { create() }
                        .disabled(busy || keyID.isEmpty || secret.isEmpty)
                        .pointerStyle(.link)
                }
            }
            .padding(.top, 8)
        } label: {
            Label("New secret", systemImage: "plus.circle")
                .font(.stratumUI(13, .semibold)).foregroundStyle(Palette.textPrimary)
                .pointerStyle(.link)
        }
        .tint(Palette.accent)
    }

    @ViewBuilder
    private func row(_ label: String, _ placeholder: String, _ text: Binding<String>,
                     secure: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.stratumUI(11)).foregroundStyle(Palette.textSecondary)
                .frame(width: 96, alignment: .leading)
            Group {
                if secure { SecureField(placeholder, text: text) }
                else { TextField(placeholder, text: text) }
            }
            .textFieldStyle(.roundedBorder).font(.stratumMono(11))
        }
    }

    private func create() {
        busy = true
        error = nil
        let spec = DuckDBSecret(name: name, type: type, keyID: keyID, secret: secret,
                                endpoint: endpoint, region: region, urlStyle: urlStyle, scope: scope)
        let wantsPersistent = persist
        Task {
            let failure = await model.createSecret(spec, persistent: wantsPersistent)
            busy = false
            if let failure {
                error = failure
            } else {
                name = ""; keyID = ""; secret = ""; endpoint = ""; region = ""; scope = ""
                expanded = false
                onCreated()
            }
        }
    }
}

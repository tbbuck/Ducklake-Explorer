import Foundation

/// An S3-family DuckDB secret the app can create for the user, and the `CREATE SECRET`
/// statement it maps to. Only non-empty fields are emitted; string values are single-quote
/// escaped and the optional name is a quoted identifier, so user input can't break the SQL.
public struct DuckDBSecret: Sendable, Equatable {
    public var name: String
    public var type: String        // a bareword, e.g. "s3"
    public var keyID: String
    public var secret: String
    public var endpoint: String
    public var region: String
    public var urlStyle: String    // "path" | "vhost" | ""
    public var scope: String       // one scope, or several separated by commas/newlines

    public init(name: String = "", type: String = "s3", keyID: String = "", secret: String = "",
                endpoint: String = "", region: String = "", urlStyle: String = "", scope: String = "") {
        self.name = name; self.type = type; self.keyID = keyID; self.secret = secret
        self.endpoint = endpoint; self.region = region; self.urlStyle = urlStyle; self.scope = scope
    }

    /// `CREATE [PERSISTENT] SECRET [name] (TYPE …, KEY_ID '…', …)`. Persistent secrets are
    /// written by DuckDB to `~/.duckdb/stored_secrets` (unencrypted) and survive restarts;
    /// non-persistent ones live only for the connection they're created on.
    public func statement(persistent: Bool) -> String {
        func lit(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "''") + "'" }
        func ident(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }

        let safeType = type.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" }
        var params = ["TYPE \(safeType.isEmpty ? "s3" : safeType)"]
        func add(_ key: String, _ value: String) {
            let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !v.isEmpty { params.append("\(key) \(lit(v))") }
        }
        add("KEY_ID", keyID)
        add("SECRET", secret)
        add("ENDPOINT", endpoint)
        add("REGION", region)
        add("URL_STYLE", urlStyle)

        let scopes = scope.split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if scopes.count == 1 {
            params.append("SCOPE \(lit(scopes[0]))")
        } else if scopes.count > 1 {
            params.append("SCOPE (\(scopes.map(lit).joined(separator: ", ")))")
        }

        let kind = persistent ? "PERSISTENT SECRET" : "SECRET"
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let named = trimmedName.isEmpty ? "" : " \(ident(trimmedName))"
        return "CREATE \(kind)\(named) (\(params.joined(separator: ", ")));"
    }
}

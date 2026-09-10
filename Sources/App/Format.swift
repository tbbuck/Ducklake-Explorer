import Foundation

/// Small display formatters for the inspector metrics.
enum Format {
    static func count(_ n: Int64) -> String {
        countFormatter.string(from: NSNumber(value: n)) ?? String(n)
    }

    static func bytes(_ n: Int64) -> String {
        guard n > 0 else { return "0 B" }
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var value = Double(n)
        var unit = 0
        while value >= 1024, unit < units.count - 1 { value /= 1024; unit += 1 }
        return unit == 0 ? "\(n) B" : String(format: "%.1f %@", value, units[unit])
    }

    private static let countFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()
}

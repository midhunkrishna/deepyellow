import Foundation

/// Human-readable formatting. Sizes use base 1000 so they match Finder.
public enum Format {
    /// Formats bytes with three significant figures, such as `4.21 GB`.
    public static func bytes(_ value: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var amount = Double(value)
        var unit = 0
        while amount >= 999.5, unit < units.count - 1 {
            amount /= 1000
            unit += 1
        }
        if unit == 0 { return "\(value) B" }
        let decimals = amount >= 100 ? 0 : (amount >= 10 ? 1 : 2)
        return String(format: "%.\(decimals)f %@", amount, units[unit])
    }

    /// Formats a count with grouping separators, such as `1,204,311`.
    public static func count<T: BinaryInteger>(_ value: T) -> String {
        Int(value).formatted(.number.grouping(.automatic).locale(Locale(identifier: "en_US")))
    }

    /// Formats a count compactly, such as `1.2M` or `38K`.
    public static func compactCount<T: BinaryInteger>(_ value: T) -> String {
        let amount = Double(value)
        switch amount {
        case ..<1_000: return "\(Int(value))"
        case ..<10_000: return String(format: "%.1fK", amount / 1_000)
        case ..<1_000_000: return String(format: "%.0fK", amount / 1_000)
        case ..<10_000_000: return String(format: "%.1fM", amount / 1_000_000)
        default: return String(format: "%.0fM", amount / 1_000_000)
        }
    }

    /// Formats elapsed time compactly, such as `3 days ago` or `2 yr ago`. Returns `unknown` for a non-positive time.
    public static func age(_ timestamp: Int32, now: Int32 = Int32(Date().timeIntervalSince1970)) -> String {
        guard timestamp > 0 else { return "unknown" }
        let seconds = Int(now) - Int(timestamp)
        switch seconds {
        case ..<60: return "just now"
        case ..<3_600: return "\(seconds / 60) min ago"
        case ..<86_400: return "\(seconds / 3_600) hr ago"
        case ..<(86_400 * 30): return plural(seconds / 86_400, "day")
        case ..<(86_400 * 365): return plural(seconds / (86_400 * 30), "month")
        default: return "\(seconds / (86_400 * 365)) yr ago"
        }
    }

    /// Formats a fraction as a percentage. Non-zero values never display as `0%`.
    public static func percent(_ part: UInt64, of whole: UInt64) -> String {
        guard whole > 0, part > 0 else { return "0%" }
        let value = Double(part) / Double(whole) * 100
        if value < 0.1 { return "<0.1%" }
        return value < 10 ? String(format: "%.1f%%", value) : String(format: "%.0f%%", value)
    }

    private static func plural(_ value: Int, _ unit: String) -> String {
        "\(value) \(unit)\(value == 1 ? "" : "s") ago"
    }
}

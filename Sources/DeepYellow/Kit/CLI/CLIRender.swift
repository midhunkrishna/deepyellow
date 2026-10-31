import DYCore
import Foundation

/// Whether output carries colour.
public struct OutputStyle: Equatable {
    public var color: Bool
    /// Plain output.
    public static let plain = OutputStyle(color: false)
    /// Truecolor output.
    public static let colored = OutputStyle(color: true)

    /// Colour only on a terminal, and never when `NO_COLOR` is set to anything non-empty.
    public static func detect(isTTY: Bool, environment: [String: String]) -> OutputStyle {
        let noColor = !(environment["NO_COLOR"] ?? "").isEmpty
        return OutputStyle(color: isTTY && !noColor)
    }
}

/// Draws horizontal bars with eighth-block precision.
public enum BarRenderer {
    private static let partial: [Character] = [" ", "▏", "▎", "▍", "▌", "▋", "▊", "▉"]

    /// A bar `width` cells wide filled to `fraction`. Coloured bars use the accent gold on a dim track.
    public static func bar(fraction: Double, width: Int, style: OutputStyle) -> String {
        let clamped = max(0, min(1, fraction.isFinite ? fraction : 0))
        let eighths = Int((clamped * Double(width) * 8).rounded())
        let full = eighths / 8
        var text = String(repeating: "█", count: full)
        if full < width, eighths % 8 > 0 { text.append(partial[eighths % 8]) }
        let pad = String(repeating: " ", count: max(0, width - text.count))
        guard style.color else { return text + pad }
        let track = String(repeating: "·", count: pad.count)
        return "\u{1B}[38;2;255;184;0m\(text)\u{1B}[38;2;75;70;63m\(track)\u{1B}[0m"
    }
}

/// Turns analysis summaries into terminal text and JSON.
public enum CLIRender {
    /// Left-pads `text` to `width`.
    static func right(_ text: String, _ width: Int) -> String { String(repeating: " ", count: max(0, width - text.count)) + text }

    /// Dim text for secondary columns on a colour terminal.
    static func dim(_ text: String, _ style: OutputStyle) -> String { style.color ? "\u{1B}[38;2;125;120;110m\(text)\u{1B}[0m" : text }

    /// A path relative to `root`, or "." for the root itself.
    static func relative(_ path: String, to root: String) -> String {
        if path == root { return "." }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }

    /// The `things` table.
    public static func things(_ report: ThingsReport, style: OutputStyle) -> String {
        var lines = ["Things under \(report.path)  ·  \(Format.bytes(report.total)) total  ·  cut at \(Format.bytes(report.thresholdBytes))  ·  \(report.rows.count) rows", ""]
        let biggest = Double(report.rows.map(\.bytes).max() ?? 1)
        for row in report.rows {
            let label = row.kind == "rest"
                ? "\(Format.count(row.items ?? 0)) smaller items in \(relative(row.path, to: report.path))"
                : relative(row.path, to: report.path)
            let share = Format.percent(row.bytes, of: report.total)
            let bar = BarRenderer.bar(fraction: Double(row.bytes) / biggest, width: 20, style: style)
            lines.append("  \(bar)  \(right(Format.bytes(row.bytes), 9))  \(right(share, 6))  \(row.kind == "rest" ? dim(label, style) : label)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The `things` JSON.
    public static func thingsJSON(_ report: ThingsReport) -> String {
        json(["path": report.path, "total": report.total, "thresholdBytes": report.thresholdBytes,
              "things": report.rows.map { row -> [String: Any] in
                  var item: [String: Any] = ["path": row.path, "name": row.name, "bytes": row.bytes, "files": row.files, "kind": row.kind]
                  if let items = row.items { item["items"] = items }
                  return item
              }])
    }

    /// The `reclaim` report.
    public static func reclaim(_ summary: ReclaimSummary, style: OutputStyle) -> String {
        var lines = ["Reclaim under \(summary.path)  ·  \(Format.bytes(summary.total)) scanned", "", "Safety groups"]
        if summary.groups.isEmpty { lines.append("  none of the built-in rules match here") }
        let biggest = Double(summary.groups.map(\.bytes).max() ?? 1)
        for group in summary.groups {
            let bar = BarRenderer.bar(fraction: Double(group.bytes) / biggest, width: 14, style: style)
            lines.append("  \(bar)  \(right(Format.bytes(group.bytes), 9))  \(group.tier.padding(toLength: 8, withPad: " ", startingAt: 0))  \(group.title)  \(dim("(\(Format.count(group.items)) items)", style))")
            if let command = group.cleanupCommand { lines.append("      \(dim("official cleanup, not run: \(command)", style))") }
        }
        lines.append(contentsOf: ["", "Worklists"])
        for list in summary.worklists {
            lines.append("  \(list.title): \(Format.bytes(list.bytes)) in \(Format.count(list.items)) items")
            lines.append("      \(dim(list.why, style))")
            for entry in list.top { lines.append("      \(right(Format.bytes(entry.bytes), 9))  \(relative(entry.path, to: summary.path))") }
        }
        lines.append("  Duplicates: not read here. Run `deepyellow dupes <path>`.")
        return lines.joined(separator: "\n") + "\n"
    }

    /// The `reclaim` JSON.
    public static func reclaimJSON(_ summary: ReclaimSummary) -> String {
        json(["path": summary.path, "total": summary.total,
              "groups": summary.groups.map { g -> [String: Any] in
                  ["id": g.id, "title": g.title, "tier": g.tier, "bytes": g.bytes, "reclaimableBytes": g.reclaimable, "files": g.files,
                   "items": g.items, "cleanupCommand": g.cleanupCommand ?? NSNull()]
              },
              "worklists": summary.worklists.map { l -> [String: Any] in
                  ["kind": l.kind, "title": l.title, "why": l.why, "bytes": l.bytes, "files": l.files, "items": l.items,
                   "top": l.top.map { ["path": $0.path, "bytes": $0.bytes] as [String: Any] }]
              }])
    }

    /// The `spectrum` histogram: one bar per size range for bytes, with the file count beside it.
    public static func spectrum(_ summary: SpectrumSummary, style: OutputStyle) -> String {
        var lines = ["Spectrum of \(summary.path)  ·  \(Format.count(summary.totalFiles)) files  ·  \(Format.bytes(summary.totalBytes))", ""]
        lines.append("  \("size range".padding(toLength: 22, withPad: " ", startingAt: 0))  \(right("files", 11))   bytes")
        let biggest = Double(summary.bins.map(\.bytes).max() ?? 1)
        for bin in summary.bins where bin.files > 0 {
            let range = "\(Format.bytes(bin.lower)) to \(Format.bytes(bin.upper))"
            let bar = BarRenderer.bar(fraction: Double(bin.bytes) / max(biggest, 1), width: 24, style: style)
            lines.append("  \(range.padding(toLength: 22, withPad: " ", startingAt: 0))  \(right(Format.count(bin.files), 11))   \(bar) \(Format.bytes(bin.bytes))")
        }
        lines.append("")
        lines.append("The \(Format.count(summary.filesHolding80PercentOfBytes)) largest files hold 80% of the bytes.")
        return lines.joined(separator: "\n") + "\n"
    }

    /// The `spectrum` JSON.
    public static func spectrumJSON(_ summary: SpectrumSummary) -> String {
        json(["path": summary.path, "totalFiles": summary.totalFiles, "totalBytes": summary.totalBytes,
              "filesHolding80PercentOfBytes": summary.filesHolding80PercentOfBytes,
              "bins": summary.bins.map { ["lower": $0.lower, "upper": $0.upper, "files": $0.files, "bytes": $0.bytes] as [String: Any] }])
    }

    /// The `dupes` report, biggest waste first.
    public static func dupes(_ summary: DuplicateSummary, style: OutputStyle) -> String {
        var lines = ["Duplicates under \(summary.path)  ·  \(Format.bytes(summary.wasted)) wasted in \(Format.count(summary.sets.count)) sets  ·  \(Format.bytes(summary.bytesHashed)) read", ""]
        if summary.sets.isEmpty { lines.append("  no exact duplicates at this size") }
        let biggest = Double(summary.sets.map(\.wasted).max() ?? 1)
        for set in summary.sets.prefix(50) {
            let bar = BarRenderer.bar(fraction: Double(set.wasted) / biggest, width: 14, style: style)
            lines.append("  \(bar)  \(right(Format.bytes(set.wasted), 9)) wasted  \(set.paths.count) copies of \(Format.bytes(set.size))")
            for path in set.paths { lines.append("      \(relative(path, to: summary.path))") }
        }
        if summary.sets.count > 50 { lines.append("  … \(summary.sets.count - 50) more sets (use --json for all)") }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The `dupes` JSON.
    public static func dupesJSON(_ summary: DuplicateSummary) -> String {
        json(["path": summary.path, "bytesHashed": summary.bytesHashed, "wastedBytes": summary.wasted,
              "sets": summary.sets.map { ["size": $0.size, "copies": $0.paths.count, "wastedBytes": $0.wasted, "paths": $0.paths] as [String: Any] }])
    }

    /// Stable JSON: sorted keys, two-space indent, no escaped slashes, trailing newline.
    static func json(_ object: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self) + "\n"
    }
}

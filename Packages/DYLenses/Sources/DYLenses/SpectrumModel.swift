import DYAnalysis
import DYCore
import Foundation

/// Pure helpers behind the Spectrum lens: labels, the headline and the query terms a column writes.
enum SpectrumModel {
    private static let units: [(name: String, scale: UInt64)] = [("tb", 1_000_000_000_000), ("gb", 1_000_000_000), ("mb", 1_000_000),
                                                                  ("kb", 1_000)]

    /// A size token for the query language, such as `20mb`. Bin edges are 1, 2 or 5 times a power of ten, so this is exact.
    static func sizeToken(_ bytes: UInt64) -> String {
        for unit in units where bytes >= unit.scale && bytes % unit.scale == 0 { return "\(bytes / unit.scale)\(unit.name)" }
        return "\(bytes)"
    }

    /// A short label for a bin edge, such as `20 MB`.
    static func edgeLabel(_ bytes: UInt64) -> String {
        if bytes == 0 { return "0" }
        for unit in units where bytes >= unit.scale { return "\(bytes / unit.scale) \(unit.name.uppercased())" }
        return "\(bytes) B"
    }

    /// The words under a column: the bin's lower edge, or "empty" for the zero-byte bin.
    static func columnLabel(_ bin: SpectrumBin) -> String { bin.upper == 1 ? "empty" : edgeLabel(bin.lower) }

    /// The full name of a bin's range, for accessibility and tooltips: "20 KB to 50 KB".
    static func rangeLabel(_ bin: SpectrumBin) -> String {
        if bin.upper == 1 { return "Empty files" }
        let upper = bin.upper == UInt64.max ? nil : edgeLabel(bin.upper)
        return upper.map { "\(edgeLabel(bin.lower)) to \($0)" } ?? "\(edgeLabel(bin.lower)) and up"
    }

    /// The `size>` and `size<` terms that select a bin.
    static func terms(for bin: SpectrumBin) -> [String] {
        var result: [String] = []
        if bin.lower > 0 { result.append("size>\(sizeToken(bin.lower))") }
        if bin.upper != UInt64.max { result.append("size<\(sizeToken(bin.upper))") }
        return result
    }

    /// Whether a query token is a size term.
    static func isSizeTerm(_ token: Substring) -> Bool { token.hasPrefix("size>") || token.hasPrefix("size<") }

    /// Whether the query already holds size terms.
    static func hasSizeTerms(_ query: String) -> Bool { query.split(separator: " ").contains(where: isSizeTerm) }

    /// The query after a click on `bin`. Existing size terms are replaced; clicking the same bin again clears them.
    static func query(_ query: String, selecting bin: SpectrumBin) -> String {
        let others = query.split(separator: " ").filter { !isSizeTerm($0) }.map(String.init)
        let current = query.split(separator: " ").filter(isSizeTerm).map(String.init)
        let wanted = terms(for: bin)
        return (current == wanted ? others : others + wanted).joined(separator: " ")
    }

    /// The query with its size terms removed.
    static func clearingSize(_ query: String) -> String {
        query.split(separator: " ").filter { !isSizeTerm($0) }.joined(separator: " ")
    }

    /// The headline, worked out from the data: how few bytes the small files take.
    static func headline(_ result: SpectrumResult) -> (title: String, subtitle: String) {
        guard result.totalFiles > 0 else { return ("No files here", "Nothing matches the current query.") }
        let small = result.bins.filter { $0.upper <= 1_000_000 }
        let smallFiles = small.reduce(UInt64(0)) { $0 + $1.count }
        let smallBytes = small.reduce(UInt64(0)) { $0 + $1.bytes }
        let title = "\(Format.percent(smallFiles, of: result.totalFiles)) of your files use only \(Format.percent(smallBytes, of: result.totalBytes)) of the space"
        let subtitle = "\(Format.count(smallFiles)) files are under 1 MB and total \(Format.bytes(smallBytes)). Click a column to add a size range to the query."
        return (title, subtitle)
    }

    /// The kinds that appear anywhere in the data, in legend order.
    static func presentKinds(_ result: SpectrumResult) -> [FileKind] {
        FileKind.allCases.filter { kind in result.bins.contains { $0.bytesByKind[Int(kind.rawValue)] > 0 || $0.countByKind[Int(kind.rawValue)] > 0 } }
    }

    /// Short count labels above columns: `1.2M`, `38K`, `412`.
    static func countLabel(_ value: UInt64) -> String { Format.compactCount(value) }
}

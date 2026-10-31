import Foundation

/// Reads the head of a text file.
public enum TextExtractor {
    public static let limit = 256 * 1024

    /// Returns the first 256 KB as text, or nil when the file is unreadable or looks binary.
    /// Opens the file read-only. Never call this for a dataless item.
    public static func head(of url: URL, limit: Int = TextExtractor.limit) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: limit) else { return nil }
        return decode(data)
    }

    /// Decodes bytes as UTF-8 (dropping a cut-off trailing sequence), falling back to Latin-1. Nil for binary data.
    static func decode(_ data: Data) -> String? {
        if data.contains(0) { return nil }
        for trim in 0...3 where data.count > trim {
            if let text = String(data: data.dropLast(trim), encoding: .utf8) { return text }
        }
        return String(data: data, encoding: .isoLatin1)
    }
}

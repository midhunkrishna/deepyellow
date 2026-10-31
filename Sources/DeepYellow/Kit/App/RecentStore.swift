import Foundation

/// The folders opened most recently, kept in a small JSON file inside the data directory.
public struct RecentStore {
    public let fileURL: URL
    public let limit = 6

    /// Creates a store inside `directory`.
    public init(directory: URL) { fileURL = directory.appendingPathComponent("recent-folders.json") }

    /// Recent folders, newest first. Missing or damaged files read as empty.
    public func load() -> [String] {
        guard let data = try? Data(contentsOf: fileURL), let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return list
    }

    /// Moves `path` to the front and saves. Returns the new list.
    @discardableResult
    public func record(_ path: String) -> [String] {
        let list = Array(([path] + load().filter { $0 != path }).prefix(limit))
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(list).write(to: fileURL, options: .atomic)
        return list
    }
}

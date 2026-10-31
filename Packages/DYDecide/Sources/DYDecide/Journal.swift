import Foundation

/// One item's progress through a move, saved so an undo survives a crash.
struct JournalEntry: Codable, Equatable {
    enum State: String, Codable { case moving, moved }
    var original: String
    var trashed: String?
    var state: State
    var bytes: UInt64
}

/// The moves of the most recent execution.
struct Journal: Codable, Equatable {
    var entries: [JournalEntry] = []
}

/// Reads and writes the journal file. With no file, the journal lives in memory only.
struct JournalFile {
    let url: URL?

    /// The saved journal, or an empty one when there is no file or it can't be read.
    func load() -> Journal {
        guard let url, let data = try? Data(contentsOf: url) else { return Journal() }
        return (try? JSONDecoder().decode(Journal.self, from: data)) ?? Journal()
    }

    /// Saves `journal` atomically. Returns false when the write failed.
    func save(_ journal: Journal) -> Bool {
        guard let url else { return true }
        guard let data = try? JSONEncoder().encode(journal) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}

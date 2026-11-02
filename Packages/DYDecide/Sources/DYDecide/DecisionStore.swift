import Foundation
import DYCore

/// Keeps the user's keep, remove and later verdicts, keyed by path with a fingerprint, with undo and redo.
///
/// Verdicts are staged only. Nothing here touches a file.
public final class DecisionStore: @unchecked Sendable {
    /// One path's change within an undo step.
    private struct Change {
        var path: String
        var before: DecisionEntry?
        var after: DecisionEntry?
    }

    /// The on-disk form.
    private struct Persisted: Codable {
        var format = 1
        var entries: [String: DecisionEntry]
    }

    private let fileURL: URL?
    private let lock = NSLock()
    private var entries: [String: DecisionEntry] = [:]
    private var undoStack: [[Change]] = []
    private var redoStack: [[Change]] = []
    private var counter = 0

    /// Opens the store at `fileURL`, or an in-memory store when nil. An unreadable file is set aside, not overwritten.
    public init(fileURL: URL?) {
        self.fileURL = fileURL
        if let fileURL { entries = Self.load(fileURL) }
    }

    /// Increases on every change, undo and redo, so callers can tell when to re-resolve.
    public var version: Int { lock.withLock { counter } }

    /// Records `decision` for `paths` as one undo step, fingerprinting each path from `tree`.
    ///
    /// `.none` clears a verdict. Paths missing from `tree` are skipped, because they can't be fingerprinted.
    /// A call that changes nothing adds no undo step.
    public func set(_ decision: Decision, paths: [String], tree: FileTree) {
        set(Dictionary(paths.map { ($0, decision) }, uniquingKeysWith: { first, _ in first }), tree: tree)
    }

    /// Records a decision per path as one undo step, with the same rules as `set(_:paths:tree:)`.
    public func set(_ decisions: [String: Decision], tree: FileTree) {
        lock.withLock {
            var changes: [Change] = []
            for (path, decision) in decisions {
                let before = entries[path]
                var after: DecisionEntry?
                if decision != .none {
                    guard let node = tree.find(path: path) else { continue }
                    after = DecisionEntry(decision: decision, fingerprint: Fingerprint(tree: tree, node: node))
                }
                if before != after { changes.append(Change(path: path, before: before, after: after)) }
            }
            guard !changes.isEmpty else { return }
            apply(changes, forward: true)
            undoStack.append(changes)
            redoStack.removeAll()
            commit()
        }
    }

    /// Reverses the last step. Returns false when there is nothing to undo.
    @discardableResult
    public func undo() -> Bool {
        lock.withLock {
            guard let changes = undoStack.popLast() else { return false }
            apply(changes, forward: false)
            redoStack.append(changes)
            commit()
            return true
        }
    }

    /// Re-applies the last undone step. Returns false when there is nothing to redo.
    @discardableResult
    public func redo() -> Bool {
        lock.withLock {
            guard let changes = redoStack.popLast() else { return false }
            apply(changes, forward: true)
            undoStack.append(changes)
            commit()
            return true
        }
    }

    /// Works out the effective decision for every node of `tree`.
    public func resolve(tree: FileTree) -> ResolvedDecisions {
        let snapshot = lock.withLock { entries }
        return DecisionResolver.resolve(entries: snapshot, tree: tree)
    }

    /// Writes either side of `changes` into `entries`. Caller holds the lock.
    private func apply(_ changes: [Change], forward: Bool) {
        for change in changes { entries[change.path] = forward ? change.after : change.before }
    }

    /// Bumps the version and saves. Caller holds the lock.
    private func commit() {
        counter += 1
        guard let fileURL, let data = try? JSONEncoder().encode(Persisted(entries: entries)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Reads stored verdicts, moving a file that can't be decoded out of the way.
    private static func load(_ url: URL) -> [String: DecisionEntry] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        if let stored = try? JSONDecoder().decode(Persisted.self, from: data) { return stored.entries }
        try? FileManager.default.moveItem(at: url, to: url.appendingPathExtension("unreadable"))
        return [:]
    }
}

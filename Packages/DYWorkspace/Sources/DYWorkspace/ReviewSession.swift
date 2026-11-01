import DYCore
import Foundation

/// One item in a review session.
public struct ReviewItem: Equatable, Sendable, Identifiable {
    public var id: String { path }
    public var path: String
    public var name: String
    public var bytes: UInt64
    public var kind: FileKind
    public var isDirectory: Bool
    /// True for a macOS package such as an .app, which stays one item.
    public var isPackage = false
    /// The item's node in the tree the session was started on. A new scan ends the session, so this stays valid.
    public var node: NodeID = -1

    /// Whether ⏎ can go into this item.
    public var canGoIn: Bool { isDirectory && !isPackage }
}

/// The running count shown while reviewing: "38 left · 214 GB decided".
public struct ReviewTally: Equatable, Sendable {
    public var kept = 0
    public var removed = 0
    public var later = 0
    /// Items with no verdict yet.
    public var left = 0
    /// Bytes of items marked remove.
    public var removedBytes: UInt64 = 0
    /// Bytes of items with any verdict.
    public var decidedBytes: UInt64 = 0
}

/// Culling through a set of items, one level at a time. A verdict stays on the current item, the arrows move along the
/// level, and going into a folder remembers the place to come back to.
public struct ReviewSession: Equatable, Sendable {
    /// A level waiting underneath the current one, with the position to return to.
    private struct Level: Equatable, Sendable {
        var title: String
        var items: [ReviewItem]
        var index: Int
    }

    /// One recorded verdict, kept so undo and redo can restore either side of it.
    private struct Step: Equatable, Sendable {
        var path: String
        var previous: Decision?
        var given: Decision
    }

    /// The name of the current level.
    public private(set) var title: String
    /// The items of the current level.
    public private(set) var items: [ReviewItem]
    /// The position of the item being looked at in the current level.
    public private(set) var index = 0
    /// Verdicts given in this session, by path.
    public private(set) var verdicts: [String: Decision] = [:]
    private var parents: [Level] = []
    private var steps: [Step] = []
    private var undone: [Step] = []

    /// Starts a session over `items`, which must not be empty.
    public init(title: String, items: [ReviewItem]) {
        self.title = title
        self.items = items
    }

    /// The item being looked at.
    public var current: ReviewItem? { items.indices.contains(index) ? items[index] : nil }

    /// How many levels below the start the session is.
    public var depth: Int { parents.count }

    /// The names of the levels from the start down to the current one.
    public var trail: [String] { parents.map(\.title) + [title] }

    /// True on the last item of the current level.
    public var isAtEnd: Bool { index >= items.count - 1 }

    /// The tally of the current level, given each item's decision.
    public func tally(decision: (ReviewItem) -> Decision) -> ReviewTally {
        var result = ReviewTally()
        for item in items {
            let verdict = decision(item)
            guard verdict != .none else { result.left += 1; continue }
            result.decidedBytes &+= item.bytes
            switch verdict {
            case .keep: result.kept += 1
            case .remove: result.removed += 1; result.removedBytes &+= item.bytes
            case .later: result.later += 1
            case .none: break
            }
        }
        return result
    }

    /// Records a verdict for the current item and stays on it. Returns the item's path, or nil when there is no item.
    @discardableResult
    public mutating func record(_ decision: Decision) -> String? {
        guard let item = current else { return nil }
        steps.append(Step(path: item.path, previous: verdicts[item.path], given: decision))
        undone.removeAll()
        verdicts[item.path] = decision
        return item.path
    }

    /// Reverses the last verdict, moving to its item when that is in the current level. Returns its path, or nil when there is nothing to undo.
    @discardableResult
    public mutating func stepBack() -> String? {
        guard let step = steps.popLast() else { return nil }
        undone.append(step)
        verdicts[step.path] = step.previous
        moveToItem(step.path)
        return step.path
    }

    /// Gives back the last undone verdict, moving to its item when that is in the current level. Returns its path, or nil when there is nothing to redo.
    @discardableResult
    public mutating func stepForward() -> String? {
        guard let step = undone.popLast() else { return nil }
        steps.append(step)
        verdicts[step.path] = step.given
        moveToItem(step.path)
        return step.path
    }

    /// Moves to the item at `position` without giving a verdict. Positions outside the level are ignored.
    public mutating func go(to position: Int) {
        if items.indices.contains(position) { index = position }
    }

    /// Goes into a level holding `items`, starting at its first item. An empty level is ignored.
    public mutating func enter(title: String, items: [ReviewItem]) {
        guard !items.isEmpty else { return }
        parents.append(Level(title: self.title, items: self.items, index: index))
        self.title = title
        self.items = items
        index = 0
    }

    /// Returns to the level above, at the item it was left on. Returns false at the starting level.
    @discardableResult
    public mutating func leave() -> Bool {
        guard let level = parents.popLast() else { return false }
        title = level.title
        items = level.items
        index = level.index
        return true
    }

    /// Moves to the item with `path` when the current level has it.
    private mutating func moveToItem(_ path: String) {
        if let position = items.firstIndex(where: { $0.path == path }) { index = position }
    }
}

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

/// Culling over a fixed set of items: a verdict advances to the next, and undo steps back.
public struct ReviewSession: Equatable, Sendable {
    /// One recorded verdict, kept so undo can restore what was there before.
    private struct Step: Equatable, Sendable {
        var index: Int
        var previous: Decision?
    }

    public let title: String
    public let items: [ReviewItem]
    /// The item being looked at. Equals `items.count` once every item has been passed.
    public private(set) var index = 0
    /// Verdicts given in this session, by path.
    public private(set) var verdicts: [String: Decision] = [:]
    private var steps: [Step] = []

    /// Starts a session over `items`.
    public init(title: String, items: [ReviewItem]) {
        self.title = title
        self.items = items
    }

    /// The item being looked at, or nil when finished.
    public var current: ReviewItem? { items.indices.contains(index) ? items[index] : nil }

    /// True once the last item has been passed.
    public var isFinished: Bool { index >= items.count }

    /// The tally of verdicts given so far.
    public var tally: ReviewTally {
        var result = ReviewTally()
        for item in items {
            guard let verdict = verdicts[item.path], verdict != .none else { result.left += 1; continue }
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

    /// Records a verdict for the current item and moves to the next. Returns the item's path, or nil when finished.
    @discardableResult
    public mutating func record(_ decision: Decision) -> String? {
        guard let item = current else { return nil }
        steps.append(Step(index: index, previous: verdicts[item.path]))
        verdicts[item.path] = decision
        index += 1
        return item.path
    }

    /// Reverses the last verdict and returns to that item. Returns the item's path, or nil when there is nothing to undo.
    @discardableResult
    public mutating func stepBack() -> String? {
        guard let step = steps.popLast() else { return nil }
        let path = items[step.index].path
        verdicts[path] = step.previous
        index = step.index
        return path
    }

    /// Moves to the item at `position` without giving a verdict. Positions outside the set are ignored.
    public mutating func go(to position: Int) {
        if position >= 0, position <= items.count { index = position }
    }
}

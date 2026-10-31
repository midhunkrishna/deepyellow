import Foundation

/// What an execution or an undo actually did. Every planned path appears in exactly one list.
public struct ExecutionReport: Sendable {
    /// Items that moved. For an undo, the items that were put back.
    public var moved: [(original: String, trashed: String)]
    /// Items left alone because they changed after the plan was made.
    public var skippedChanged: [String]
    /// Items that could not be moved, with the reason.
    public var failed: [(path: String, error: String)]
    /// Items never attempted because the run was cancelled.
    public var notAttempted: [String]
    public var bytesMoved: UInt64

    /// Creates a report. All lists default to empty.
    public init(moved: [(original: String, trashed: String)] = [], skippedChanged: [String] = [],
                failed: [(path: String, error: String)] = [], notAttempted: [String] = [], bytesMoved: UInt64 = 0) {
        self.moved = moved
        self.skippedChanged = skippedChanged
        self.failed = failed
        self.notAttempted = notAttempted
        self.bytesMoved = bytesMoved
    }
}

import DYCore
import Foundation

/// Everything a query can read, captured once so a run never touches live app state.
public struct SQLContext: @unchecked Sendable {
    /// The scanned tree.
    public var tree: FileTree
    /// The tree with ignore rules and Trash state applied and no query. Gives `size`, `files` and `visible`.
    public var lens: TreeLens
    /// Effective `Decision` raw value per node, or empty when decisions aren't available.
    public var decisions: [UInt8]
    /// `SafetyTier` raw value per node, or empty when the reclaim report isn't available.
    public var safety: [UInt8]
    /// Reference time for `age_days`, in seconds since 1970.
    public var now: Int32

    /// Creates a context.
    public init(tree: FileTree, lens: TreeLens, decisions: [UInt8] = [], safety: [UInt8] = [], now: Int32) {
        self.tree = tree
        self.lens = lens
        self.decisions = decisions
        self.safety = safety
        self.now = now
    }
}

/// One cell of a result.
public enum SQLValue: Equatable, Sendable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    /// A blob other than an `ids(...)` column. Only its length is kept.
    case blob(byteCount: Int)
}

/// How a result relates to the views.
public enum SQLResultShape: Equatable, Sendable {
    /// There is an `id` column: each row names one node.
    case nodes
    /// There is an `ids` column from the `ids(...)` aggregate: each row names a group of nodes.
    case groups
    /// Neither: the result is a table only and can't drive the views.
    case tableOnly
}

/// A finished query.
public struct SQLResult: @unchecked Sendable {
    /// The tree the node ids belong to.
    public var tree: FileTree
    /// Column names in order, without the `ids` column.
    public var columns: [String]
    /// Rows kept for display, at most the requested `rowLimit`. Cells line up with `columns`.
    public var rows: [[SQLValue]]
    /// Every row the query produced, including those past `rowLimit`.
    public var rowCount: Int
    public var shape: SQLResultShape
    /// Distinct nodes named by any row, ascending. Empty for `.tableOnly`.
    public var nodes: [NodeID]
    /// For `.nodes`: the node of each kept row, or nil where `id` wasn't a valid node. Lines up with `rows`.
    public var rowNode: [NodeID?]
    /// For `.groups`: the nodes of each kept row, ascending. Lines up with `rows`.
    public var rowGroup: [[NodeID]]
    /// Wall-clock time of the run, in seconds.
    public var elapsed: TimeInterval

    /// Creates a result.
    public init(tree: FileTree, columns: [String], rows: [[SQLValue]], rowCount: Int, shape: SQLResultShape, nodes: [NodeID],
                rowNode: [NodeID?], rowGroup: [[NodeID]], elapsed: TimeInterval) {
        self.tree = tree
        self.columns = columns
        self.rows = rows
        self.rowCount = rowCount
        self.shape = shape
        self.nodes = nodes
        self.rowNode = rowNode
        self.rowGroup = rowGroup
        self.elapsed = elapsed
    }
}

/// Why a query didn't produce a result. `message` is plain words, ready to show.
public enum SQLFailure: Error, Equatable, Sendable {
    /// A syntax error or an unknown table, column or function.
    case invalid(message: String)
    /// The statement would write or reach outside the scan, such as DELETE, ATTACH or PRAGMA.
    case refused(message: String)
    /// More than one statement was given.
    case multipleStatements(message: String)
    /// The query needed more memory than the limit.
    case tooLarge(message: String)
    /// `isCancelled` became true.
    case cancelled
}

/// One ready-made query, shared by the app's menu, the docs and the tests.
public struct SQLExample: Equatable, Sendable {
    public var title: String
    public var sql: String

    /// Creates an example.
    public init(title: String, sql: String) {
        self.title = title
        self.sql = sql
    }
}

/// One documented column, shared by the app's schema list, `--help` and the docs.
public struct SQLColumnDoc: Equatable, Sendable {
    public var name: String
    public var type: String
    public var meaning: String

    /// Creates a column description.
    public init(name: String, type: String, meaning: String) {
        self.name = name
        self.type = type
        self.meaning = meaning
    }
}

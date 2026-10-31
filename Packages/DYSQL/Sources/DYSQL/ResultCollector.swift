import DYCore
import Foundation
import SQLite3

/// Reads a statement's rows into an `SQLResult`, streaming each row to the caller and keeping a bounded number for display.
struct ResultCollector {
    private let tree: FileTree
    private let rowLimit: Int
    private let onRow: (([SQLValue]) -> Void)?
    private let idColumn: Int?
    private var idsColumn: Int?
    private let names: [String]
    private var rows: [[SQLValue]] = []
    private var rowNode: [NodeID?] = []
    private var rowGroup: [[NodeID]] = []
    private var seen: [Bool] = []
    private var rowCount = 0
    private var groupsConfirmed = false

    /// Prepares to collect the rows of `statement`.
    init(statement: OpaquePointer, tree: FileTree, rowLimit: Int, onRow: (([SQLValue]) -> Void)?) {
        self.tree = tree
        self.rowLimit = max(0, rowLimit)
        self.onRow = onRow
        names = (0..<sqlite3_column_count(statement)).map { String(cString: sqlite3_column_name(statement, $0)) }
        idColumn = names.firstIndex(of: "id")
        idsColumn = idColumn == nil ? names.firstIndex(of: "ids") : nil
        if idColumn != nil || idsColumn != nil { seen = [Bool](repeating: false, count: tree.count) }
    }

    /// Column names as a caller sees them: `ids` is dropped when it carries groups.
    func visibleColumns() -> [String] {
        names.enumerated().filter { $0.offset != idsColumn }.map(\.element)
    }

    /// Records the statement's current row.
    mutating func collect(_ statement: OpaquePointer) {
        if rowCount == 0, let column = idsColumn, sqlite3_column_type(statement, Int32(column)) != SQLITE_BLOB {
            idsColumn = nil
            seen = []
        }
        rowCount += 1
        let group = idsColumn.map { decodeGroup(statement, column: $0) }
        let node = idColumn.map { nodeID(statement, column: $0) }
        if node != nil || group != nil { mark(node ?? nil, group) }
        guard onRow != nil || rows.count < rowLimit else { return }
        let cells = (0..<names.count).filter { $0 != idsColumn }.map { value(statement, column: Int32($0)) }
        onRow?(cells)
        if rows.count < rowLimit {
            rows.append(cells)
            if idColumn != nil { rowNode.append(node ?? nil) }
            if let group { rowGroup.append(group) }
        }
    }

    /// The finished result.
    func finish(elapsed: TimeInterval) -> SQLResult {
        let shape: SQLResultShape = idColumn != nil ? .nodes : (idsColumn != nil ? .groups : .tableOnly)
        var nodes: [NodeID] = []
        if shape != .tableOnly {
            nodes.reserveCapacity(rowCount)
            for index in 0..<seen.count where seen[index] { nodes.append(NodeID(index)) }
        }
        return SQLResult(tree: tree, columns: visibleColumns(), rows: rows, rowCount: rowCount, shape: shape, nodes: nodes,
                         rowNode: rowNode, rowGroup: rowGroup, elapsed: elapsed)
    }

    /// The node an `id` cell names, or nil when it isn't an integer inside the tree.
    private func nodeID(_ statement: OpaquePointer, column: Int) -> NodeID? {
        guard sqlite3_column_type(statement, Int32(column)) == SQLITE_INTEGER else { return nil }
        let value = sqlite3_column_int64(statement, Int32(column))
        return value >= 0 && value < Int64(tree.count) ? NodeID(value) : nil
    }

    /// The valid, ascending nodes of an `ids(...)` cell.
    private func decodeGroup(_ statement: OpaquePointer, column: Int) -> [NodeID] {
        guard sqlite3_column_type(statement, Int32(column)) == SQLITE_BLOB else { return [] }
        let count = Int(sqlite3_column_bytes(statement, Int32(column)))
        guard count > 0, let bytes = sqlite3_column_blob(statement, Int32(column)) else { return [] }
        return SQLFunctions.decode(UnsafeRawBufferPointer(start: bytes, count: count), treeCount: tree.count)
    }

    /// Adds a row's nodes to the distinct set.
    private mutating func mark(_ node: NodeID?, _ group: [NodeID]?) {
        if let node { seen[Int(node)] = true }
        for member in group ?? [] { seen[Int(member)] = true }
    }

    /// One cell as a value.
    private func value(_ statement: OpaquePointer, column: Int32) -> SQLValue {
        switch sqlite3_column_type(statement, column) {
        case SQLITE_INTEGER: return .integer(sqlite3_column_int64(statement, column))
        case SQLITE_FLOAT: return .real(sqlite3_column_double(statement, column))
        case SQLITE_TEXT: return .text(String(cString: sqlite3_column_text(statement, column)))
        case SQLITE_BLOB: return .blob(byteCount: Int(sqlite3_column_bytes(statement, column)))
        default: return .null
        }
    }
}

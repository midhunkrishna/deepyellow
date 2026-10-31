import DYCore
import Foundation
import SQLite3

/// A read-only SQLite engine over a scanned tree. Every run uses its own in-memory connection.
public enum SQLEngine {
    /// Runs one read-only statement on a fresh in-memory connection. Blocks; call off the main thread.
    ///
    /// `rowLimit` caps `SQLResult.rows`; `rowCount` and `nodes` still cover every row. `onRow`, when given, receives every row
    /// (without the `ids` column) as it is produced, for streaming. `isCancelled` is polled through the progress handler.
    public static func run(_ sql: String, context: SQLContext, rowLimit: Int = 5_000, onRow: (([SQLValue]) -> Void)? = nil,
                           isCancelled: @escaping () -> Bool = { false }) throws -> SQLResult {
        let started = Date()
        let connection = try SQLConnection(context: context, isCancelled: isCancelled)
        let statement = try connection.prepare(sql)
        defer { sqlite3_finalize(statement) }
        var collector = ResultCollector(statement: statement, tree: context.tree, rowLimit: rowLimit, onRow: onRow)
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_ROW {
                collector.collect(statement)
            } else if status == SQLITE_DONE {
                break
            } else {
                throw connection.failure(status)
            }
            if isCancelled() { throw SQLFailure.cancelled }
        }
        return collector.finish(elapsed: Date().timeIntervalSince(started))
    }

    /// Column names of a statement without running it, or a failure. For showing errors early.
    public static func validate(_ sql: String, context: SQLContext) throws -> [String] {
        let connection = try SQLConnection(context: context, isCancelled: { false })
        let statement = try connection.prepare(sql)
        defer { sqlite3_finalize(statement) }
        let names = (0..<sqlite3_column_count(statement)).map { String(cString: sqlite3_column_name(statement, $0)) }
        return names.contains("id") ? names : names.filter { $0 != "ids" }
    }

    /// Ready-made queries. Each one runs on any scan and, unless its title says otherwise, drives the views.
    public static let examples: [SQLExample] = SQLDocs.examples

    /// Every column of `nodes`.
    public static let schema: [SQLColumnDoc] = NodeColumn.allCases.map {
        SQLColumnDoc(name: $0.sqlName, type: $0.sqlType, meaning: $0.meaning)
    }

    /// The functions DeepYellow adds, with their signature in `type`.
    public static let functions: [SQLColumnDoc] = SQLDocs.functions
}

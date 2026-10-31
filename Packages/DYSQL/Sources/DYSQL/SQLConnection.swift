import DYCore
import Foundation
import SQLite3

/// One in-memory SQLite connection exposing a captured scan. Created per run and closed when released.
final class SQLConnection {
    /// The raw handle.
    let db: OpaquePointer
    /// Callback state; kept alive for as long as the connection can call back.
    let state: RunState
    private let source: NodeSource

    /// Opcodes between cancellation checks.
    private static let progressInterval: Int32 = 2_000

    /// Opens and locks down a connection. Throws `.invalid` if SQLite can't be set up.
    init(context: SQLContext, isCancelled: @escaping () -> Bool) throws {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(":memory:", &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_MEMORY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let handle else {
            sqlite3_close(handle)
            throw SQLFailure.invalid(message: "SQL couldn't start.")
        }
        db = handle
        state = RunState(isCancelled: isCancelled)
        source = NodeSource(context)
        do { try configure() } catch { sqlite3_close_v2(handle); throw error }
    }

    deinit { sqlite3_close_v2(db) }

    /// Installs the table, functions and views, then the limits and the authorizer, in that order.
    private func configure() throws {
        guard NodeTable.register(on: db, source: source) == SQLITE_OK else { throw SQLFailure.invalid(message: "SQL couldn't start.") }
        SQLFunctions.register(on: db, source: source)
        for statement in [
            "PRAGMA temp_store = MEMORY",
            "CREATE VIEW files AS SELECT * FROM nodes WHERE is_dir = 0 AND visible = 1",
            "CREATE VIEW dirs AS SELECT * FROM nodes WHERE is_dir = 1 AND visible = 1",
        ] where sqlite3_exec(db, statement, nil, nil, nil) != SQLITE_OK {
            throw SQLFailure.invalid(message: "SQL couldn't start.")
        }
        sqlite3_limit(db, SQLITE_LIMIT_ATTACHED, 0)
        let user = Unmanaged.passUnretained(state).toOpaque()
        sqlite3_progress_handler(db, Self.progressInterval, { user in
            guard let user else { return 0 }
            let state = Unmanaged<RunState>.fromOpaque(user).takeUnretainedValue()
            return state.isCancelled() || state.memory.isOverBudget() ? 1 : 0
        }, user)
        guard sqlite3_set_authorizer(db, SQLGuard.authorizer, user) == SQLITE_OK else {
            throw SQLFailure.invalid(message: "SQL couldn't start.")
        }
    }

    /// Prepares exactly one read-only statement.
    func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        var tail: UnsafePointer<CChar>?
        let status = sql.withCString { text -> Int32 in
            let status = sqlite3_prepare_v2(db, text, -1, &statement, &tail)
            if status == SQLITE_OK, SQLGuard.hasAnotherStatement(tail: tail) {
                sqlite3_finalize(statement)
                statement = nil
                return -1
            }
            return status
        }
        if status == -1 {
            throw SQLFailure.multipleStatements(message: "Run one statement at a time. Remove everything after the first semicolon.")
        }
        if let denied = state.refused { sqlite3_finalize(statement); throw SQLGuard.refusal(SQLGuard.leadingKeyword(of: sql) ?? denied) }
        guard status == SQLITE_OK else { throw failure(status, sql: sql) }
        guard let statement else { throw SQLFailure.invalid(message: "Type a SELECT statement to run.") }
        guard sqlite3_stmt_readonly(statement) != 0 else {
            sqlite3_finalize(statement)
            throw SQLGuard.refusal(SQLGuard.leadingKeyword(of: sql) ?? "that statement")
        }
        return statement
    }

    private var tooLarge: SQLFailure {
        .tooLarge(message: "That query needed more than \(MemoryGuard.budget >> 30) GB of memory. Add a WHERE or LIMIT, or group the result.")
    }

    /// Translates a SQLite status into a failure with plain words.
    func failure(_ status: Int32, sql: String = "") -> SQLFailure {
        if let denied = state.refused { return SQLGuard.refusal(denied) }
        if state.memory.exceeded || status & 0xFF == SQLITE_NOMEM { return tooLarge }
        if let refusal = SQLGuard.refusalFromMessage(String(cString: sqlite3_errmsg(db)), sql: sql) { return refusal }
        switch status & 0xFF {
        case SQLITE_INTERRUPT: return .cancelled
        case SQLITE_FULL, SQLITE_TOOBIG: return tooLarge
        default:
            let text = String(cString: sqlite3_errmsg(db))
            return .invalid(message: text.prefix(1).uppercased() + text.dropFirst())
        }
    }
}

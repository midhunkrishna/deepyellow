import Foundation
import SQLite3

/// Per-run state shared with SQLite's callbacks: the cancel flag and the first thing the authorizer refused.
final class RunState {
    let isCancelled: () -> Bool
    /// The statement keyword or function that was refused, in upper case for statements.
    var refused: String?
    /// Watches the footprint during the run.
    var memory = MemoryGuard()

    /// Creates run state.
    init(isCancelled: @escaping () -> Bool) { self.isCancelled = isCancelled }
}

/// Keeps SQL read-only: the authorizer, the refusal wording and the multiple-statement check.
enum SQLGuard {
    /// Functions that reach outside the scan.
    private static let deniedFunctions: Set<String> = ["load_extension", "readfile", "writefile", "edit", "fts3_tokenizer"]

    /// Statement keywords worth naming in a refusal, in the order a user would write them.
    private static let statementKeywords: Set<String> = [
        "DELETE", "UPDATE", "INSERT", "REPLACE", "DROP", "CREATE", "ALTER", "ATTACH", "DETACH", "VACUUM", "PRAGMA", "BEGIN",
        "COMMIT", "END", "ROLLBACK", "SAVEPOINT", "RELEASE", "REINDEX", "ANALYZE",
    ]

    /// Allows only SELECT, READ, FUNCTION (apart from those that reach outside) and RECURSIVE; denies and records everything else.
    static let authorizer: @convention(c) (UnsafeMutableRawPointer?, Int32, UnsafePointer<CChar>?, UnsafePointer<CChar>?,
                                           UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Int32 = { user, action, first, second, _, _ in
        switch action {
        case SQLITE_SELECT, SQLITE_READ, SQLITE_RECURSIVE:
            return SQLITE_OK
        case SQLITE_FUNCTION:
            let name = second.map { String(cString: $0).lowercased() } ?? ""
            guard deniedFunctions.contains(name) else { return SQLITE_OK }
            record(name, user)
            return SQLITE_DENY
        default:
            record(actionName(action, first), user)
            return SQLITE_DENY
        }
    }

    /// Remembers the first refusal of a run.
    private static func record(_ name: String, _ user: UnsafeMutableRawPointer?) {
        guard let user else { return }
        let state = Unmanaged<RunState>.fromOpaque(user).takeUnretainedValue()
        if state.refused == nil { state.refused = name }
    }

    /// The statement an authorizer action code belongs to.
    private static func actionName(_ action: Int32, _ detail: UnsafePointer<CChar>?) -> String {
        switch action {
        case SQLITE_DELETE: return "DELETE"
        case SQLITE_UPDATE: return "UPDATE"
        case SQLITE_INSERT: return "INSERT"
        case SQLITE_ATTACH: return "ATTACH"
        case SQLITE_DETACH: return "DETACH"
        case SQLITE_PRAGMA: return "PRAGMA"
        case SQLITE_ALTER_TABLE: return "ALTER"
        case SQLITE_REINDEX: return "REINDEX"
        case SQLITE_ANALYZE: return "ANALYZE"
        case SQLITE_SAVEPOINT, SQLITE_TRANSACTION: return "BEGIN, COMMIT or SAVEPOINT"
        case SQLITE_CREATE_INDEX, SQLITE_CREATE_TABLE, SQLITE_CREATE_TEMP_INDEX, SQLITE_CREATE_TEMP_TABLE,
             SQLITE_CREATE_TEMP_TRIGGER, SQLITE_CREATE_TEMP_VIEW, SQLITE_CREATE_TRIGGER, SQLITE_CREATE_VIEW, SQLITE_CREATE_VTABLE:
            return "CREATE"
        case SQLITE_DROP_INDEX, SQLITE_DROP_TABLE, SQLITE_DROP_TEMP_INDEX, SQLITE_DROP_TEMP_TABLE, SQLITE_DROP_TEMP_TRIGGER,
             SQLITE_DROP_TEMP_VIEW, SQLITE_DROP_TRIGGER, SQLITE_DROP_VIEW, SQLITE_DROP_VTABLE:
            return "DROP"
        default: return "that statement"
        }
    }

    /// The first word of the statement if it is a keyword worth naming, which beats the authorizer's guess for VACUUM INTO.
    static func leadingKeyword(of sql: String) -> String? {
        let word = sql.drop { $0.isWhitespace || $0 == ";" }.prefix { $0.isLetter }.uppercased()
        return statementKeywords.contains(word) ? word : nil
    }

    /// The plain-words refusal for `what`.
    static func refusal(_ what: String) -> SQLFailure {
        var message = "DeepYellow's SQL is read-only, so \(what) isn't allowed."
        if what == "DELETE" || what == "DROP" { message += " To remove something, select it and press x." }
        return .refused(message: message)
    }

    /// A refusal for errors SQLite raises before the authorizer is consulted: writing to a table without a write path, and
    /// calling a function this build doesn't have but the guard would have denied anyway. Nil for any other message.
    static func refusalFromMessage(_ message: String, sql: String) -> SQLFailure? {
        let lower = message.lowercased()
        if lower.contains("may not be altered") { return refusal("ALTER") }
        if lower.contains("may not be modified") {
            let written = ["DELETE", "UPDATE", "INSERT", "REPLACE"]
            let words = sql.split { !$0.isLetter }.map { $0.uppercased() }
            return refusal(words.first { written.contains($0) } ?? "that statement")
        }
        if let name = deniedFunctions.first(where: { lower.contains("no such function: \($0)") }) { return refusal(name) }
        return nil
    }

    /// Whether anything but whitespace, semicolons and comments follows the first statement.
    static func hasAnotherStatement(tail: UnsafePointer<CChar>?) -> Bool {
        guard let tail else { return false }
        let bytes = Array(UnsafeBufferPointer(start: UnsafeRawPointer(tail).assumingMemoryBound(to: UInt8.self), count: strlen(tail)))
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D || byte == UInt8(ascii: ";") {
                index += 1
            } else if byte == UInt8(ascii: "-"), index + 1 < bytes.count, bytes[index + 1] == UInt8(ascii: "-") {
                while index < bytes.count, bytes[index] != 0x0A { index += 1 }
            } else if byte == UInt8(ascii: "/"), index + 1 < bytes.count, bytes[index + 1] == UInt8(ascii: "*") {
                index += 2
                while index + 1 < bytes.count, !(bytes[index] == UInt8(ascii: "*") && bytes[index + 1] == UInt8(ascii: "/")) { index += 1 }
                index += 2
            } else {
                return true
            }
        }
        return false
    }
}

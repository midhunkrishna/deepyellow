import DYCore
import Foundation
import SQLite3

/// The scalar functions and the `ids` aggregate that DeepYellow adds to SQLite.
enum SQLFunctions {
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private static let flags = SQLITE_UTF8 | SQLITE_DETERMINISTIC

    /// Registers every function on `db`. `source` supplies `now` for `age_days`.
    static func register(on db: OpaquePointer, source: NodeSource) {
        for (name, factor) in [("kb", 1_000.0), ("mb", 1_000_000.0), ("gb", 1_000_000_000.0), ("tb", 1_000_000_000_000.0)] {
            let box = UnsafeMutablePointer<Double>.allocate(capacity: 1)
            box.initialize(to: factor)
            sqlite3_create_function_v2(db, name, 1, flags, box, unit, nil, nil) { $0?.assumingMemoryBound(to: Double.self).deallocate() }
        }
        sqlite3_create_function_v2(db, "human", 1, flags, nil, human, nil, nil, nil)
        sqlite3_create_function_v2(db, "age_days", 1, flags, Unmanaged.passUnretained(source).toOpaque(), ageDays, nil, nil, nil)
        sqlite3_create_function_v2(db, "ids", 1, SQLITE_UTF8, nil, nil, idsStep, idsFinal, nil)
    }

    /// `kb(n)` and friends: `n` times a decimal unit, an integer when `n` is one.
    private static let unit: @convention(c) (OpaquePointer?, Int32, UnsafeMutablePointer<OpaquePointer?>?) -> Void = { context, _, argv in
        guard let argument = argv?[0], sqlite3_value_type(argument) != SQLITE_NULL,
              let factor = sqlite3_user_data(context)?.assumingMemoryBound(to: Double.self).pointee else { return sqlite3_result_null(context) }
        if sqlite3_value_type(argument) == SQLITE_INTEGER {
            let (product, overflow) = sqlite3_value_int64(argument).multipliedReportingOverflow(by: Int64(factor))
            if !overflow { return sqlite3_result_int64(context, product) }
        }
        sqlite3_result_double(context, sqlite3_value_double(argument) * factor)
    }

    /// `human(bytes)`: the same text `Format.bytes` gives.
    private static let human: @convention(c) (OpaquePointer?, Int32, UnsafeMutablePointer<OpaquePointer?>?) -> Void = { context, _, argv in
        guard let argument = argv?[0], sqlite3_value_type(argument) != SQLITE_NULL else { return sqlite3_result_null(context) }
        let bytes = UInt64(clamping: max(0, sqlite3_value_int64(argument)))
        sqlite3_result_text(context, Format.bytes(bytes), -1, transient)
    }

    /// `age_days(seconds)`: whole days between that time and the context's `now`.
    private static let ageDays: @convention(c) (OpaquePointer?, Int32, UnsafeMutablePointer<OpaquePointer?>?) -> Void = { context, _, argv in
        guard let argument = argv?[0], sqlite3_value_type(argument) != SQLITE_NULL,
              let raw = sqlite3_user_data(context) else { return sqlite3_result_null(context) }
        let now = Unmanaged<NodeSource>.fromOpaque(raw)._withUnsafeGuaranteedRef { Int64($0.now) }
        sqlite3_result_int64(context, (now - sqlite3_value_int64(argument)) / 86_400)
    }

    /// The growing list of ids an `ids(...)` call has seen.
    private struct IDList {
        var base: UnsafeMutablePointer<Int32>?
        var count = 0
        var capacity = 0
    }

    /// Adds one id to the group's list. Non-integer and out-of-`Int32` values are skipped.
    private static let idsStep: @convention(c) (OpaquePointer?, Int32, UnsafeMutablePointer<OpaquePointer?>?) -> Void = { context, _, argv in
        guard let argument = argv?[0], sqlite3_value_type(argument) == SQLITE_INTEGER,
              let list = sqlite3_aggregate_context(context, Int32(MemoryLayout<IDList>.size))?.assumingMemoryBound(to: IDList.self) else { return }
        let value = sqlite3_value_int64(argument)
        guard value >= 0, value <= Int64(Int32.max) else { return }
        if list.pointee.count == list.pointee.capacity {
            let capacity = max(8, list.pointee.capacity * 2)
            let grown = UnsafeMutablePointer<Int32>.allocate(capacity: capacity)
            if let old = list.pointee.base {
                grown.moveInitialize(from: old, count: list.pointee.count)
                old.deallocate()
            }
            list.pointee.base = grown
            list.pointee.capacity = capacity
        }
        list.pointee.base?[list.pointee.count] = Int32(value)
        list.pointee.count += 1
    }

    /// Returns the list as a blob of little-endian `Int32`s and frees it. A group with no ids gives an empty blob.
    private static let idsFinal: @convention(c) (OpaquePointer?) -> Void = { context in
        guard let list = sqlite3_aggregate_context(context, 0)?.assumingMemoryBound(to: IDList.self), let base = list.pointee.base else {
            return sqlite3_result_zeroblob(context, 0)
        }
        sqlite3_result_blob(context, base, Int32(list.pointee.count * 4), transient)
        base.deallocate()
        list.pointee.base = nil
    }

    /// Decodes an `ids(...)` blob into ascending, distinct ids that exist in a tree of `count` nodes.
    static func decode(_ bytes: UnsafeRawBufferPointer, treeCount: Int) -> [NodeID] {
        guard bytes.count % 4 == 0 else { return [] }
        var ids = [NodeID]()
        ids.reserveCapacity(bytes.count / 4)
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            let value = bytes.loadUnaligned(fromByteOffset: offset, as: Int32.self)
            if value >= 0, Int(value) < treeCount { ids.append(value) }
        }
        ids.sort()
        var distinct = [NodeID]()
        for id in ids where distinct.last != id { distinct.append(id) }
        return distinct
    }
}

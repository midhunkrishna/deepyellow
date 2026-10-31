import DYCore
import Foundation
import SQLite3

/// The virtual table behind `nodes`: read-only, eponymous, and reading the tree in place.
enum NodeTable {
    /// How a scan is driven, chosen by `xBestIndex` and carried in `idxNum`.
    private enum Plan: Int32 {
        case all = 0, oneID = 1, children = 2
    }

    /// The SQLite table object, with the source it reads.
    private struct VTab {
        var base = sqlite3_vtab()
        var source: Unmanaged<NodeSource>
    }

    /// A scan position over node ids, `row` up to but not including `end`.
    private struct Cursor {
        var base = sqlite3_vtab_cursor()
        var row: Int32 = 0
        var end: Int32 = 0
    }

    /// The module definition. It has no `xCreate`, which makes the table eponymous, and no `xUpdate`, so it can't be written.
    nonisolated(unsafe) static var module: sqlite3_module = {
        var module = sqlite3_module()
        module.iVersion = 0
        module.xConnect = connect
        module.xBestIndex = bestIndex
        module.xDisconnect = disconnect
        module.xOpen = open
        module.xClose = close
        module.xFilter = filter
        module.xNext = next
        module.xEof = eof
        module.xColumn = column
        module.xRowid = rowid
        return module
    }()

    /// Registers the table on `db`, reading `source`. The source is retained until the connection closes.
    static func register(on db: OpaquePointer, source: NodeSource) -> Int32 {
        sqlite3_create_module_v2(db, "nodes", &module, Unmanaged.passRetained(source).toOpaque()) { pointer in
            if let pointer { Unmanaged<NodeSource>.fromOpaque(pointer).release() }
        }
    }

    // MARK: Lifecycle

    /// Declares the columns and allocates the table object.
    private static let connect: @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?, Int32,
                                                UnsafePointer<UnsafePointer<CChar>?>?, UnsafeMutablePointer<UnsafeMutablePointer<sqlite3_vtab>?>?,
                                                UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32 = { db, aux, _, _, out, _ in
        let status = sqlite3_declare_vtab(db, NodeColumn.declaration)
        guard status == SQLITE_OK, let aux else { return status == SQLITE_OK ? SQLITE_ERROR : status }
        let table = UnsafeMutablePointer<VTab>.allocate(capacity: 1)
        table.initialize(to: VTab(source: Unmanaged<NodeSource>.fromOpaque(aux)))
        out?.pointee = UnsafeMutableRawPointer(table).assumingMemoryBound(to: sqlite3_vtab.self)
        return SQLITE_OK
    }

    /// Frees the table object.
    private static let disconnect: @convention(c) (UnsafeMutablePointer<sqlite3_vtab>?) -> Int32 = { table in
        table.map { UnsafeMutableRawPointer($0).assumingMemoryBound(to: VTab.self).deallocate() }
        return SQLITE_OK
    }

    /// Allocates a cursor.
    private static let open: @convention(c) (UnsafeMutablePointer<sqlite3_vtab>?,
                                             UnsafeMutablePointer<UnsafeMutablePointer<sqlite3_vtab_cursor>?>?) -> Int32 = { _, out in
        let cursor = UnsafeMutablePointer<Cursor>.allocate(capacity: 1)
        cursor.initialize(to: Cursor())
        out?.pointee = UnsafeMutableRawPointer(cursor).assumingMemoryBound(to: sqlite3_vtab_cursor.self)
        return SQLITE_OK
    }

    /// Frees a cursor.
    private static let close: @convention(c) (UnsafeMutablePointer<sqlite3_vtab_cursor>?) -> Int32 = { cursor in
        cursor.map { UnsafeMutableRawPointer($0).assumingMemoryBound(to: Cursor.self).deallocate() }
        return SQLITE_OK
    }

    // MARK: Planning and scanning

    /// Pushes `id = ?` down to one row and `parent = ?` down to a child range. Everything else is a full scan.
    ///
    /// The constraint is not omitted, so SQLite re-checks it; the scan only has to return a superset.
    private static let bestIndex: @convention(c) (UnsafeMutablePointer<sqlite3_vtab>?,
                                                  UnsafeMutablePointer<sqlite3_index_info>?) -> Int32 = { raw, info in
        guard let raw, let info else { return SQLITE_ERROR }
        let source = UnsafeMutableRawPointer(raw).assumingMemoryBound(to: VTab.self).pointee.source._withUnsafeGuaranteedRef { $0.count }
        var chosen: (index: Int, plan: Plan)?
        for index in 0..<Int(info.pointee.nConstraint) {
            let constraint = info.pointee.aConstraint[index]
            guard constraint.usable != 0, constraint.op == UInt8(SQLITE_INDEX_CONSTRAINT_EQ) else { continue }
            if constraint.iColumn == NodeColumn.id.rawValue || constraint.iColumn == -1 { chosen = (index, .oneID); break }
            if constraint.iColumn == NodeColumn.parent.rawValue, chosen == nil { chosen = (index, .children) }
        }
        guard let chosen else {
            info.pointee.idxNum = Plan.all.rawValue
            info.pointee.estimatedCost = Double(source) * 2
            info.pointee.estimatedRows = Int64(source)
            return SQLITE_OK
        }
        info.pointee.aConstraintUsage[chosen.index].argvIndex = 1
        info.pointee.idxNum = chosen.plan.rawValue
        if chosen.plan == .oneID {
            info.pointee.estimatedCost = 1
            info.pointee.estimatedRows = 1
            info.pointee.idxFlags = SQLITE_INDEX_SCAN_UNIQUE
        } else {
            info.pointee.estimatedCost = 20
            info.pointee.estimatedRows = 8
        }
        return SQLITE_OK
    }

    /// Positions the cursor for the plan. A NULL argument matches nothing; an argument that isn't an integer scans everything.
    private static let filter: @convention(c) (UnsafeMutablePointer<sqlite3_vtab_cursor>?, Int32, UnsafePointer<CChar>?, Int32,
                                               UnsafeMutablePointer<OpaquePointer?>?) -> Int32 = { raw, plan, _, _, argv in
        guard let raw else { return SQLITE_ERROR }
        let cursor = UnsafeMutableRawPointer(raw).assumingMemoryBound(to: Cursor.self)
        let source = UnsafeMutableRawPointer(raw.pointee.pVtab).assumingMemoryBound(to: VTab.self).pointee.source
        let count = source._withUnsafeGuaranteedRef { $0.count }
        var range = 0..<count
        if plan != Plan.all.rawValue, let argument = argv?[0] {
            switch sqlite3_value_type(argument) {
            case SQLITE_INTEGER:
                let value = sqlite3_value_int64(argument)
                let inside = value >= 0 && value < Int64(count)
                if plan == Plan.oneID.rawValue {
                    range = inside ? Int(value)..<(Int(value) + 1) : 0..<0
                } else {
                    range = inside ? source._withUnsafeGuaranteedRef { $0.childRange(of: Int(value)) } : 0..<0
                }
            case SQLITE_NULL: range = 0..<0
            default: break
            }
        }
        cursor.pointee.row = Int32(range.lowerBound)
        cursor.pointee.end = Int32(range.upperBound)
        return SQLITE_OK
    }

    /// Advances to the next row.
    private static let next: @convention(c) (UnsafeMutablePointer<sqlite3_vtab_cursor>?) -> Int32 = { raw in
        UnsafeMutableRawPointer(raw!).assumingMemoryBound(to: Cursor.self).pointee.row += 1
        return SQLITE_OK
    }

    /// Whether the scan is finished.
    private static let eof: @convention(c) (UnsafeMutablePointer<sqlite3_vtab_cursor>?) -> Int32 = { raw in
        let cursor = UnsafeMutableRawPointer(raw!).assumingMemoryBound(to: Cursor.self)
        return cursor.pointee.row >= cursor.pointee.end ? 1 : 0
    }

    /// A node's rowid is its id.
    private static let rowid: @convention(c) (UnsafeMutablePointer<sqlite3_vtab_cursor>?, UnsafeMutablePointer<sqlite3_int64>?) -> Int32 = { raw, out in
        out?.pointee = Int64(UnsafeMutableRawPointer(raw!).assumingMemoryBound(to: Cursor.self).pointee.row)
        return SQLITE_OK
    }

    /// Reports one column of the cursor's node.
    private static let column: @convention(c) (UnsafeMutablePointer<sqlite3_vtab_cursor>?, OpaquePointer?, Int32) -> Int32 = { raw, context, index in
        let cursor = UnsafeMutableRawPointer(raw!).assumingMemoryBound(to: Cursor.self)
        let node = Int(cursor.pointee.row)
        UnsafeMutableRawPointer(raw!.pointee.pVtab).assumingMemoryBound(to: VTab.self).pointee.source._withUnsafeGuaranteedRef {
            report(NodeColumn(rawValue: index)!, node: node, source: $0, context: context)
        }
        return SQLITE_OK
    }

    /// Sets the result of `column` for `node`.
    private static func report(_ column: NodeColumn, node: Int, source: NodeSource, context: OpaquePointer?) {
        switch column {
        case .id: sqlite3_result_int64(context, Int64(node))
        case .parent: node == 0 ? sqlite3_result_null(context) : sqlite3_result_int64(context, Int64(source.tree.columns.parent[node]))
        case .name: reportName(node, source, context)
        case .ext: reportExtension(node, source, context)
        case .path: sqlite3_result_text(context, source.tree.path(NodeID(node)), -1, transient)
        case .depth: sqlite3_result_int64(context, source.depth(node))
        case .size: sqlite3_result_int64(context, source.size(node))
        case .logical: sqlite3_result_int64(context, Int64(bitPattern: source.tree.columns.logical[node]))
        case .fileCount: sqlite3_result_int64(context, source.fileCount(node))
        case .modified: sqlite3_result_int64(context, Int64(source.tree.columns.modified[node]))
        case .accessed: sqlite3_result_int64(context, Int64(source.tree.columns.accessed[node]))
        case .kind: reportStatic(StaticText.kinds, Int(source.tree.columns.kind[node]), context)
        case .isDir: sqlite3_result_int(context, source.has(.directory, node) ? 1 : 0)
        case .isPackage: sqlite3_result_int(context, source.has(.package, node) ? 1 : 0)
        case .isSymlink: sqlite3_result_int(context, source.has(.symlink, node) ? 1 : 0)
        case .isClone: sqlite3_result_int(context, source.has(.cloneDuplicate, node) ? 1 : 0)
        case .isHardlink: sqlite3_result_int(context, source.has(.hardlinkDuplicate, node) ? 1 : 0)
        case .isDataless: sqlite3_result_int(context, source.has(.dataless, node) ? 1 : 0)
        case .visible: sqlite3_result_int(context, source.lens.included[node] ? 1 : 0)
        case .mark: reportOptionalStatic(StaticText.marks, Int(source.decision(node)), context)
        case .safety: reportOptionalStatic(StaticText.tiers, Int(source.tier(node)), context)
        }
    }

    /// SQLite copies the text before the call returns.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// Reports a fixed string without copying; out-of-range values report `other`-like NULL.
    private static func reportStatic(_ table: [StaticText.Entry], _ index: Int, _ context: OpaquePointer?) {
        guard index < table.count else { return sqlite3_result_null(context) }
        sqlite3_result_text(context, table[index].pointer, table[index].length, nil)
    }

    /// Reports a fixed string, or NULL for index 0 or beyond the table.
    private static func reportOptionalStatic(_ table: [StaticText.Entry], _ index: Int, _ context: OpaquePointer?) {
        guard index > 0 else { return sqlite3_result_null(context) }
        reportStatic(table, index, context)
    }

    /// Reports the name straight from the tree's name bytes.
    private static func reportName(_ node: Int, _ source: NodeSource, _ context: OpaquePointer?) {
        source.tree.withName(NodeID(node)) {
            sqlite3_result_text(context, UnsafeRawPointer($0.baseAddress)?.assumingMemoryBound(to: CChar.self), Int32($0.count), transient)
        }
    }

    /// Reports the lower-case extension, or NULL for folders and names without one.
    private static func reportExtension(_ node: Int, _ source: NodeSource, _ context: OpaquePointer?) {
        guard !source.has(.directory, node) else { return sqlite3_result_null(context) }
        let found: Int? = source.tree.withName(NodeID(node)) { name in
            guard let dot = name.lastIndex(of: UInt8(ascii: ".")), dot > 0, dot < name.count - 1,
                  name.count - dot - 1 <= source.extensionScratch.count else { return nil }
            var length = 0
            for byte in name[(dot + 1)...] {
                source.extensionScratch[length] = (byte >= 65 && byte <= 90) ? byte + 32 : byte
                length += 1
            }
            return length
        }
        guard let found else { return sqlite3_result_null(context) }
        source.extensionScratch.withUnsafeBufferPointer {
            sqlite3_result_text(context, UnsafeRawPointer($0.baseAddress)?.assumingMemoryBound(to: CChar.self), Int32(found), transient)
        }
    }
}

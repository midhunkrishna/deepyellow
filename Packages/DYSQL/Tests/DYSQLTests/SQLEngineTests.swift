import DYCore
import XCTest
@testable import DYSQL

final class SQLEngineTests: XCTestCase {
    private static let tree = SyntheticTree.make(scale: 0.1)
    private var tree: FileTree { Self.tree }

    private func context(hidden: [Bool]? = nil, decisions: [UInt8] = [], safety: [UInt8] = []) -> SQLContext {
        SQLContext(tree: tree, lens: TreeLens(tree: tree, hidden: hidden), decisions: decisions, safety: safety, now: SyntheticTree.referenceNow)
    }

    private func run(_ sql: String, _ context: SQLContext? = nil, limit: Int = 5_000) throws -> SQLResult {
        try SQLEngine.run(sql, context: context ?? self.context(), rowLimit: limit)
    }

    private func int(_ value: SQLValue) -> Int64? { if case .integer(let number) = value { return number }; return nil }
    private func text(_ value: SQLValue) -> String? { if case .text(let string) = value { return string }; return nil }

    // MARK: Columns

    /// Every column agrees with the tree for a sample of nodes spread over the whole id range.
    func testEveryColumnMatchesTheTree() throws {
        let hidden = (0..<tree.count).map { $0 % 97 == 5 }
        let decisions = (0..<tree.count).map { UInt8($0 % 4) }
        let safety = (0..<tree.count).map { UInt8($0 % 5) }
        let ctx = context(hidden: hidden, decisions: decisions, safety: safety)
        let result = try run("SELECT * FROM nodes WHERE id % 37 = 0", ctx)
        XCTAssertEqual(result.columns, NodeColumn.allCases.map(\.sqlName))
        XCTAssertGreaterThan(result.rows.count, 100)
        let kinds = ["video", "image", "audio", "document", "code", "application", "archive", "other"]
        for row in result.rows {
            let id = NodeID(try XCTUnwrap(int(row[0])))
            let flags = tree.flags(id)
            XCTAssertEqual(int(row[1]), id == 0 ? nil : Int64(tree.parent(id)))
            if id == 0 { XCTAssertEqual(row[1], .null) }
            XCTAssertEqual(text(row[2]), tree.name(id))
            let name = tree.name(id)
            if tree.isDirectory(id) { XCTAssertEqual(row[3], .null) } else if let dot = name.lastIndex(of: "."), dot != name.startIndex, name.index(after: dot) != name.endIndex {
                XCTAssertEqual(text(row[3]), String(name[name.index(after: dot)...]).lowercased())
            } else { XCTAssertEqual(row[3], .null) }
            XCTAssertEqual(text(row[4]), tree.path(id))
            XCTAssertEqual(int(row[5]), Int64(tree.depth(id)))
            let included = ctx.lens.included[Int(id)]
            XCTAssertEqual(int(row[6]), Int64(included ? ctx.lens.size[Int(id)] : tree.allocated(id)))
            XCTAssertEqual(int(row[7]), Int64(tree.logical(id)))
            XCTAssertEqual(int(row[8]), Int64(included ? UInt64(ctx.lens.files[Int(id)]) : UInt64(tree.fileCount(id))))
            XCTAssertEqual(int(row[9]), Int64(tree.modified(id)))
            XCTAssertEqual(int(row[10]), Int64(tree.accessed(id)))
            XCTAssertEqual(text(row[11]), kinds[Int(tree.kind(id).rawValue)])
            XCTAssertEqual(int(row[12]), flags.contains(.directory) ? 1 : 0)
            XCTAssertEqual(int(row[13]), flags.contains(.package) ? 1 : 0)
            XCTAssertEqual(int(row[14]), flags.contains(.symlink) ? 1 : 0)
            XCTAssertEqual(int(row[15]), flags.contains(.cloneDuplicate) ? 1 : 0)
            XCTAssertEqual(int(row[16]), flags.contains(.hardlinkDuplicate) ? 1 : 0)
            XCTAssertEqual(int(row[17]), flags.contains(.dataless) ? 1 : 0)
            XCTAssertEqual(int(row[18]), included ? 1 : 0)
            let mark = decisions[Int(id)], tier = safety[Int(id)]
            XCTAssertEqual(row[19], mark == 0 ? .null : .text(["", "keep", "remove", "later"][Int(mark)]))
            XCTAssertEqual(row[20], tier == 0 ? .null : .text(["", "safe", "rebuild", "review", "never"][Int(tier)]))
        }
    }

    /// Without decisions or advice, `mark` and `safety` are NULL.
    func testMarkAndSafetyAreNullWhenUnavailable() throws {
        let result = try run("SELECT COUNT(mark), COUNT(safety), COUNT(*) FROM nodes")
        XCTAssertEqual(result.rows[0][0], .integer(0))
        XCTAssertEqual(result.rows[0][1], .integer(0))
        XCTAssertEqual(result.rows[0][2], .integer(Int64(tree.count)))
    }

    /// File sizes plus each folder's own bytes add up to the root, and the views' figures match the lens.
    func testSizesReconcileWithTheLens() throws {
        let hidden = (0..<tree.count).map { $0 % 211 == 7 }
        let ctx = context(hidden: hidden)
        let result = try run("""
            SELECT SUM(CASE WHEN d.is_dir = 0 THEN d.size ELSE d.size - (SELECT COALESCE(SUM(c.size), 0) FROM nodes c WHERE c.parent = d.id AND c.visible = 1) END)
            FROM nodes d WHERE d.visible = 1
            """, ctx)
        XCTAssertEqual(result.rows[0][0], .integer(Int64(ctx.lens.size[0])))
        let files = try run("SELECT COUNT(*) FROM files", ctx)
        let expectedFiles = (0..<tree.count).filter { ctx.lens.included[$0] && !tree.isDirectory(NodeID($0)) }.count
        XCTAssertEqual(files.rows[0][0], .integer(Int64(expectedFiles)))
        let root = try run("SELECT size, file_count FROM nodes WHERE id = 0", ctx)
        XCTAssertEqual(root.rows[0], [.integer(Int64(ctx.lens.size[0])), .integer(Int64(ctx.lens.files[0]))])
    }

    /// `files` and `dirs` hold exactly the visible nodes of each type.
    func testViews() throws {
        let hidden = (0..<tree.count).map { $0 % 53 == 3 }
        let ctx = context(hidden: hidden)
        let dirs = try run("SELECT COUNT(*) FROM dirs", ctx)
        XCTAssertEqual(dirs.rows[0][0], .integer(Int64((0..<tree.count).filter { ctx.lens.included[$0] && tree.isDirectory(NodeID($0)) }.count)))
    }

    /// Equality on `id` and `parent` returns the right rows, whatever the value's type.
    func testPushdownEquality() throws {
        let someDir = try XCTUnwrap((0..<tree.count).first { tree.columns.childCount[$0] > 2 && $0 > 0 })
        let children = try run("SELECT id FROM nodes WHERE parent = \(someDir) ORDER BY id")
        XCTAssertEqual(children.nodes, Array(tree.children(NodeID(someDir))))
        XCTAssertEqual(try run("SELECT id FROM nodes WHERE id = '\(someDir)'").rowCount, 1)
        XCTAssertEqual(try run("SELECT id FROM nodes WHERE parent IS NULL").nodes, [0])
        XCTAssertEqual(try run("SELECT id FROM nodes WHERE id = \(tree.count + 5)").rowCount, 0)
        XCTAssertEqual(try run("SELECT id FROM nodes WHERE id = -1").rowCount, 0)
        XCTAssertEqual(try run("SELECT id FROM nodes WHERE id = NULL").rowCount, 0)
    }

    // MARK: Functions

    /// Size helpers are decimal and match `Format.bytes`; `age_days` counts from the context's `now`.
    func testFunctions() throws {
        let result = try run("SELECT kb(2), mb(3), gb(1), tb(1), human(1500000000), age_days(\(SyntheticTree.referenceNow) - 86400 * 10), gb(1.5), kb(NULL)")
        XCTAssertEqual(result.rows[0], [.integer(2_000), .integer(3_000_000), .integer(1_000_000_000), .integer(1_000_000_000_000),
                                        .text(Format.bytes(1_500_000_000)), .integer(10), .real(1_500_000_000), .null])
    }

    // MARK: Shapes

    /// An `id` column makes `.nodes`; rows line up with `rowNode`; out-of-range ids are ignored.
    func testNodesShape() throws {
        let result = try run("SELECT id, name FROM files ORDER BY size DESC LIMIT 10")
        XCTAssertEqual(result.shape, .nodes)
        XCTAssertEqual(result.columns, ["id", "name"])
        XCTAssertEqual(result.rowNode.count, 10)
        XCTAssertEqual(result.rowNode.compactMap { $0 }.sorted(), result.nodes)
        let stray = try run("SELECT 5 AS id UNION ALL SELECT 999999999 UNION ALL SELECT -3 UNION ALL SELECT 'x' UNION ALL SELECT NULL")
        XCTAssertEqual(stray.shape, .nodes)
        XCTAssertEqual(stray.nodes, [5])
        XCTAssertEqual(stray.rowCount, 5)
        XCTAssertEqual(stray.rowNode, [5, nil, nil, nil, nil])
    }

    /// `ids(...)` columns make `.groups`, are removed from `columns`, and out-of-range ids are dropped.
    func testGroupsShape() throws {
        let result = try run("SELECT kind, ids(id) AS ids, COUNT(*) AS n FROM files GROUP BY kind ORDER BY kind")
        XCTAssertEqual(result.shape, .groups)
        XCTAssertEqual(result.columns, ["kind", "n"])
        XCTAssertEqual(result.rows.count, result.rowGroup.count)
        for (row, group) in zip(result.rows, result.rowGroup) {
            XCTAssertEqual(int(row[1]), Int64(group.count))
            XCTAssertEqual(group, group.sorted())
        }
        XCTAssertEqual(Set(result.nodes), Set(result.rowGroup.flatMap { $0 }))
        let direct = try run("SELECT ids(column1) AS ids FROM (VALUES (1), (2), (999999999), (2))")
        XCTAssertEqual(direct.rowGroup, [[1, 2]])
        XCTAssertEqual(try SQLEngine.validate("SELECT kind, ids(id) AS ids FROM files GROUP BY kind", context: context()), ["kind"])
    }

    /// Anything else is a table only, and an `ids` column that isn't from `ids(...)` stays a column.
    func testTableOnlyShape() throws {
        let result = try run("SELECT kind, COUNT(*) FROM files GROUP BY kind")
        XCTAssertEqual(result.shape, .tableOnly)
        XCTAssertTrue(result.nodes.isEmpty)
        let fake = try run("SELECT 7 AS ids")
        XCTAssertEqual(fake.shape, .tableOnly)
        XCTAssertEqual(fake.columns, ["ids"])
    }

    // MARK: Limits and streaming

    /// `rowLimit` caps `rows`, not `rowCount` or `nodes`; `onRow` sees every row.
    func testRowLimitAndStreaming() throws {
        var streamed = 0
        var firstWidth = 0
        let result = try SQLEngine.run("SELECT id, name FROM files", context: context(), rowLimit: 7, onRow: { row in
            streamed += 1
            firstWidth = row.count
        })
        let files = (0..<tree.count).filter { !tree.isDirectory(NodeID($0)) }.count
        XCTAssertEqual(result.rows.count, 7)
        XCTAssertEqual(result.rowNode.count, 7)
        XCTAssertEqual(result.rowCount, files)
        XCTAssertEqual(result.nodes.count, files)
        XCTAssertEqual(streamed, files)
        XCTAssertEqual(firstWidth, 2)
        let groups = try SQLEngine.run("SELECT kind, ids(id) AS ids FROM files GROUP BY kind", context: context(), rowLimit: 2, onRow: { XCTAssertEqual($0.count, 1) })
        XCTAssertEqual(groups.rows.count, 2)
        XCTAssertEqual(groups.nodes.count, files)
    }

    /// A run can be cancelled while SQLite is working, before any row is produced.
    func testCancellation() {
        XCTAssertThrowsError(try SQLEngine.run("SELECT COUNT(*) FROM nodes a, nodes b, nodes c", context: context(), isCancelled: { true })) {
            XCTAssertEqual($0 as? SQLFailure, .cancelled)
        }
    }

    // MARK: Refusals

    /// Every way of changing something is refused in plain words and creates no file.
    func testWritesAreRefusedAndCreateNoFile() throws {
        let directory = NSTemporaryDirectory() + "dysql-probe-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let target = directory + "/probe.db"
        let statements: [(String, String)] = [
            ("DELETE", "DELETE FROM nodes"), ("UPDATE", "UPDATE nodes SET size = 0"), ("INSERT", "INSERT INTO nodes(id) VALUES (1)"),
            ("DROP", "DROP TABLE nodes"), ("DROP", "DROP VIEW files"), ("CREATE", "CREATE TABLE t(a)"), ("CREATE", "CREATE TEMP TABLE t(a)"),
            ("ATTACH", "ATTACH '\(target)' AS x"), ("DETACH", "DETACH DATABASE main"), ("VACUUM", "VACUUM INTO '\(target)'"),
            ("PRAGMA", "PRAGMA writable_schema = 1"), ("PRAGMA", "PRAGMA journal_mode = DELETE"),
            ("load_extension", "SELECT load_extension('\(directory)/x')"), ("DELETE", "WITH x AS (SELECT 1) DELETE FROM nodes"),
            ("BEGIN", "BEGIN"), ("SAVEPOINT", "SAVEPOINT a"), ("ALTER", "ALTER TABLE nodes RENAME TO y"),
        ]
        for (word, sql) in statements {
            XCTAssertThrowsError(try run(sql), sql) { error in
                guard case .refused(let message) = error as? SQLFailure else { return XCTFail("\(sql) gave \(error)") }
                XCTAssertTrue(message.hasPrefix("DeepYellow's SQL is read-only, so \(word) isn't allowed."), "\(sql): \(message)")
            }
            XCTAssertThrowsError(try SQLEngine.validate(sql, context: context()), sql)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory), [])
        guard case .refused(let message) = tryFailure("DELETE FROM nodes") else { return XCTFail() }
        XCTAssertEqual(message, "DeepYellow's SQL is read-only, so DELETE isn't allowed. To remove something, select it and press x.")
    }

    private func tryFailure(_ sql: String) -> SQLFailure {
        do { _ = try run(sql); return .cancelled } catch { return error as? SQLFailure ?? .cancelled }
    }

    /// Two statements are rejected, but a trailing semicolon or comment is fine.
    func testMultipleStatements() throws {
        guard case .multipleStatements = tryFailure("SELECT 1; SELECT 2") else { return XCTFail("two statements") }
        guard case .multipleStatements = tryFailure("SELECT 1; -- note\n SELECT 2") else { return XCTFail("two statements after a comment") }
        XCTAssertEqual(try run("SELECT 1;  ").rowCount, 1)
        XCTAssertEqual(try run("SELECT 1 -- done").rowCount, 1)
        XCTAssertEqual(try run("SELECT 1; /* done */").rowCount, 1)
    }

    /// Bad SQL, an empty string and a missing function give plain `.invalid` messages.
    func testInvalid() {
        for sql in ["SELEC 1", "SELECT nope FROM nodes", "SELECT nofunc(1)", "SELECT * FROM missing", "", "  -- nothing"] {
            guard case .invalid(let message) = tryFailure(sql) else { return XCTFail("\(sql)") }
            XCTAssertFalse(message.isEmpty)
        }
    }

    /// A query that goes past the heap limit stops with `.tooLarge`. The limit is lowered for the test so little is allocated.
    func testMemoryLimit() {
        let normal = MemoryGuard.budget
        MemoryGuard.budget = 100 << 20
        defer { MemoryGuard.budget = normal; _ = try? run("SELECT 1") }
        let sql = "WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM n WHERE x < 1500) SELECT randomblob(200000) AS b FROM n ORDER BY randomblob(4)"
        guard case .tooLarge = tryFailure(sql) else { return XCTFail("expected tooLarge, got \(tryFailure(sql))") }
    }

    // MARK: SQL features and examples

    /// A recursive CTE, a window function and a join all work.
    func testSQLFeatures() throws {
        let ancestors = try run("""
            WITH RECURSIVE up(id, parent) AS (SELECT id, parent FROM nodes WHERE id = \(tree.count - 1)
                UNION ALL SELECT n.id, n.parent FROM nodes n JOIN up ON n.id = up.parent) SELECT id FROM up
            """)
        XCTAssertEqual(ancestors.nodes, tree.ancestry(NodeID(tree.count - 1)).sorted())
        let window = try run("SELECT id, SUM(size) OVER (ORDER BY size DESC, id) AS running FROM (SELECT id, size FROM files ORDER BY size DESC, id LIMIT 5)")
        XCTAssertEqual(window.rowCount, 5)
        let join = try run("SELECT f.id, p.name FROM files f JOIN dirs p ON p.id = f.parent LIMIT 20")
        XCTAssertEqual(join.rowCount, 20)
        XCTAssertEqual(try run("SELECT 1 WHERE EXISTS (SELECT 1 FROM sqlite_master WHERE name = 'files')").rowCount, 1)
    }

    /// Every example runs, and each has the shape its title promises.
    func testExamplesRun() throws {
        XCTAssertFalse(SQLEngine.examples.isEmpty)
        let ctx = context(decisions: (0..<tree.count).map { UInt8($0 % 4) }, safety: (0..<tree.count).map { UInt8($0 % 5) })
        for example in SQLEngine.examples {
            let result = try SQLEngine.run(example.sql, context: ctx)
            if example.title.contains("table only") {
                XCTAssertEqual(result.shape, .tableOnly, example.title)
            } else {
                XCTAssertNotEqual(result.shape, .tableOnly, example.title)
            }
            XCTAssertEqual(try SQLEngine.validate(example.sql, context: ctx), result.columns, example.title)
        }
        XCTAssertEqual(try run(SQLEngine.examples[0].sql).rowCount, 100)
    }

    /// The documented schema and functions cover every column and function the engine defines.
    func testDocs() {
        XCTAssertEqual(SQLEngine.schema.map(\.name), NodeColumn.allCases.map(\.sqlName))
        XCTAssertEqual(Set(SQLEngine.functions.map(\.name)), ["kb", "mb", "gb", "tb", "human", "age_days", "ids"])
        XCTAssertTrue(SQLEngine.schema.allSatisfy { !$0.meaning.isEmpty })
    }
}

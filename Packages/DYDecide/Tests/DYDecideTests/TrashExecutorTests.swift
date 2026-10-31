import XCTest
import DYCore
@testable import DYDecide

final class TrashExecutorTests: XCTestCase {
    private var box: Sandbox!
    private var trash: FakeTrash!

    override func setUpWithError() throws {
        box = try Sandbox()
        trash = try FakeTrash(sandbox: box)
    }

    override func tearDown() { box.tearDown() }

    /// Marks `relative` paths for removal, resolves against a mirror of the sandbox and plans.
    private func plan(remove: [String], keep: [String] = []) throws -> (RemovalPlan, FileTree) {
        let tree = try mirrorTree(of: box.root.path)
        let store = DecisionStore(fileURL: nil)
        store.set(.remove, paths: remove.map(box.path), tree: tree)
        store.set(.keep, paths: keep.map(box.path), tree: tree)
        let plan = RemovalPlanner.plan(tree: tree, resolved: store.resolve(tree: tree), nodeTier: [], home: "/Users/nobody")
        return (plan, tree)
    }

    private func run(_ executor: TrashExecutor, _ plan: RemovalPlan, cancelAfter: Int? = nil) async -> ExecutionReport {
        let handled = Counter()
        return await executor.execute(plan, progress: { _ in handled.bump() }, isCancelled: {
            if let cancelAfter { return handled.value >= cancelAfter }
            return false
        })
    }

    func testIntegrationMovesATempFileAndUndoRestoresIt() async throws {
        try box.file("work/junk.txt", "junk")
        try box.file("work/keep.txt", "keep")
        let (plan, _) = try plan(remove: ["work/junk.txt"])
        XCTAssertEqual(plan.items.map(\.id), [box.path("work/junk.txt")])
        let executor = TrashExecutor(mover: trash, journalURL: nil)
        let report = await run(executor, plan)
        XCTAssertEqual(report.moved.count, 1)
        XCTAssertEqual(report.bytesMoved, 4)
        XCTAssertTrue(report.failed.isEmpty && report.skippedChanged.isEmpty && report.notAttempted.isEmpty)
        XCTAssertFalse(box.exists("work/junk.txt"))
        XCTAssertEqual(box.read("work/keep.txt"), "keep")
        XCTAssertTrue(executor.canUndo)

        let undo = await executor.undoLast()
        XCTAssertEqual(undo?.moved.count, 1)
        XCTAssertEqual(box.read("work/junk.txt"), "junk")
        XCTAssertFalse(executor.canUndo)
        let none = await executor.undoLast()
        XCTAssertNil(none)
    }

    func testKeepInsideRemoveLeavesTheKeptFileAndItsParentsInPlace() async throws {
        try box.file("proj/src/a.swift", "A")
        try box.file("proj/src/deep/z.swift", "Z")
        try box.file("proj/src/deep/w.swift", "W")
        try box.file("proj/build/o", "O")
        let (plan, _) = try plan(remove: ["proj"], keep: ["proj/src/deep/z.swift"])
        let report = await run(TrashExecutor(mover: trash, journalURL: nil), plan)
        XCTAssertEqual(report.moved.count, 3)
        XCTAssertEqual(box.read("proj/src/deep/z.swift"), "Z")
        XCTAssertFalse(box.exists("proj/build"))
        XCTAssertFalse(box.exists("proj/src/a.swift"))
        XCTAssertFalse(box.exists("proj/src/deep/w.swift"))
        XCTAssertTrue(box.exists("proj/src/deep"))
        XCTAssertFalse(trash.moveCalls.contains(box.path("proj")))
        XCTAssertFalse(trash.moveCalls.contains(box.path("proj/src")))
    }

    func testMarkedSymlinkMovesTheLinkAndNeverItsTarget() async throws {
        try box.file("elsewhere/precious.txt", "precious")
        try box.directory("links")
        try FileManager.default.createSymbolicLink(atPath: box.path("links/to-file"), withDestinationPath: box.path("elsewhere/precious.txt"))
        try FileManager.default.createSymbolicLink(atPath: box.path("links/to-dir"), withDestinationPath: box.path("elsewhere"))
        let (plan, _) = try plan(remove: ["links/to-file", "links/to-dir"])
        XCTAssertEqual(plan.items.count, 2)
        let report = await run(TrashExecutor(mover: trash, journalURL: nil), plan)
        XCTAssertEqual(report.moved.count, 2)
        XCTAssertFalse(box.exists("links/to-file"))
        XCTAssertFalse(box.exists("links/to-dir"))
        XCTAssertEqual(box.read("elsewhere/precious.txt"), "precious")
        for (_, trashed) in report.moved {
            var info = stat()
            XCTAssertEqual(lstat(trashed, &info), 0)
            XCTAssertEqual(info.st_mode & S_IFMT, S_IFLNK, "the trashed item is still a link")
        }
    }

    func testChangedSinceScanIsSkippedNotMoved() async throws {
        try box.file("a.txt", "one")
        try box.file("b.txt", "two")
        let (plan, _) = try plan(remove: ["a.txt", "b.txt"])
        try box.file("a.txt", "one but longer now")
        let report = await run(TrashExecutor(mover: trash, journalURL: nil), plan)
        XCTAssertEqual(report.skippedChanged, [box.path("a.txt")])
        XCTAssertEqual(report.moved.map(\.original), [box.path("b.txt")])
        XCTAssertEqual(box.read("a.txt"), "one but longer now")
    }

    func testVanishedAndRefusedMovesAreReportedAsFailed() async throws {
        try box.file("gone.txt")
        try box.file("locked.txt")
        try box.file("fine.txt")
        let (plan, _) = try plan(remove: ["gone.txt", "locked.txt", "fine.txt"])
        try FileManager.default.removeItem(atPath: box.path("gone.txt"))
        trash.failPaths = [box.path("locked.txt")]
        let report = await run(TrashExecutor(mover: trash, journalURL: nil), plan)
        XCTAssertEqual(Set(report.failed.map(\.path)), [box.path("gone.txt"), box.path("locked.txt")])
        XCTAssertEqual(report.moved.map(\.original), [box.path("fine.txt")])
        XCTAssertTrue(box.exists("locked.txt"))
    }

    func testCancellationMidwayLeavesAnAccurateReport() async throws {
        let names = (1...5).map { "f\($0).txt" }
        for name in names { try box.file(name, name) }
        let (plan, _) = try plan(remove: names)
        let executor = TrashExecutor(mover: trash, journalURL: nil)
        let report = await run(executor, plan, cancelAfter: 2)
        XCTAssertEqual(report.moved.count, 2)
        XCTAssertEqual(report.notAttempted.count, 3)
        XCTAssertTrue(report.failed.isEmpty)
        let movedOriginals = Set(report.moved.map(\.original))
        for item in plan.items {
            let onDisk = PathProbe.exists(item.id)
            XCTAssertEqual(onDisk, !movedOriginals.contains(item.id), item.id)
            XCTAssertEqual(report.notAttempted.contains(item.id), onDisk)
        }
        XCTAssertEqual(report.bytesMoved, plan.items.filter { movedOriginals.contains($0.id) }.reduce(0) { $0 + $1.bytes })
        let undo = await executor.undoLast()
        XCTAssertEqual(undo?.moved.count, 2, "undo covers exactly what moved")
        for name in names { XCTAssertTrue(box.exists(name)) }
    }

    func testUndoNeverOverwritesAndReportsTheCollision() async throws {
        try box.file("a.txt", "original a")
        try box.file("b.txt", "original b")
        let (plan, _) = try plan(remove: ["a.txt", "b.txt"])
        let executor = TrashExecutor(mover: trash, journalURL: nil)
        _ = await run(executor, plan)
        try box.file("a.txt", "new file written meanwhile")
        let undo = await executor.undoLast()
        XCTAssertEqual(undo?.failed.map(\.path), [box.path("a.txt")])
        XCTAssertEqual(undo?.moved.map(\.original), [box.path("b.txt")])
        XCTAssertEqual(box.read("a.txt"), "new file written meanwhile")
        XCTAssertEqual(box.read("b.txt"), "original b")
        XCTAssertTrue(executor.canUndo, "the unrestored item stays undoable")
        let trashed = try FileManager.default.contentsOfDirectory(atPath: trash.trashDirectory)
        XCTAssertEqual(trashed.count, 1, "the original a.txt is still in the Trash")

        try FileManager.default.removeItem(atPath: box.path("a.txt"))
        let retry = await executor.undoLast()
        XCTAssertEqual(retry?.moved.count, 1)
        XCTAssertEqual(box.read("a.txt"), "original a")
        XCTAssertFalse(executor.canUndo)
    }

    func testJournalIsWrittenBeforeTheMoveAndSurvivesACrash() async throws {
        try box.file("a.txt", "A")
        let (plan, _) = try plan(remove: ["a.txt"])
        let journalURL = URL(fileURLWithPath: box.path("journal.json"))
        let seen = Box<String?>(nil)
        trash.beforeMove = { _ in seen.value = try? String(contentsOf: journalURL, encoding: .utf8) }
        let executor = TrashExecutor(mover: trash, journalURL: journalURL)
        _ = await run(executor, plan)
        XCTAssertTrue(seen.value?.contains("\"moving\"") == true, "the intent is on disk before the file moves")
        XCTAssertTrue(seen.value?.replacingOccurrences(of: "\\/", with: "/").contains(box.path("a.txt")) == true)

        let restarted = TrashExecutor(mover: trash, journalURL: journalURL)
        XCTAssertTrue(restarted.canUndo)
        let undo = await restarted.undoLast()
        XCTAssertEqual(undo?.moved.count, 1)
        XCTAssertEqual(box.read("a.txt"), "A")
    }

    func testAnInterruptedMoveIsReportedNotGuessedAt() async throws {
        let journalURL = URL(fileURLWithPath: box.path("journal.json"))
        let crashed = Journal(entries: [JournalEntry(original: box.path("a.txt"), trashed: nil, state: .moving, bytes: 1)])
        XCTAssertTrue(JournalFile(url: journalURL).save(crashed))
        let executor = TrashExecutor(mover: trash, journalURL: journalURL)
        let undo = await executor.undoLast()
        XCTAssertEqual(undo?.failed.count, 1)
        XCTAssertTrue(undo?.moved.isEmpty == true)
        XCTAssertFalse(executor.canUndo)
    }

    func testHandBuiltPlanCannotMoveRootRelativeOrNestedPaths() async {
        let mover = RecordingMover()
        let print = Fingerprint(size: 0, modified: 0, inode: 1)
        func item(_ path: String) -> PlanItem {
            mover.fingerprints[path] = print
            return PlanItem(id: path, node: 1, bytes: 1, reclaimable: 1, fingerprint: print, reclaimIsLowerBound: false)
        }
        let plan = RemovalPlan(items: [item("/"), item("relative/path"), item("/a/../b"), item("/p"), item("/p/child"), item("/ok"), item("/ok")])
        let report = await TrashExecutor(mover: mover, journalURL: nil).execute(plan, progress: { _ in }, isCancelled: { false })
        XCTAssertEqual(mover.moved.sorted(), ["/ok", "/p"])
        XCTAssertEqual(report.failed.count, 5)
    }

    func testSystemTrashCompilesAndIsNeverCalled() {
        let mover: TrashMoving = SystemTrash()
        XCTAssertNotNil(mover)
    }
}

/// A counter safe to touch from `@Sendable` closures.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func bump() { lock.withLock { count += 1 } }
}

/// A mutable cell safe to touch from `@Sendable` closures.
final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

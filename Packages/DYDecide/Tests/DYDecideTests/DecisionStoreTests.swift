import XCTest
import DYCore
@testable import DYDecide

final class DecisionStoreTests: XCTestCase {
    private let tree = makeTree([
        ("/h/dev/proj/src/a.swift", file(100)), ("/h/dev/proj/src/b.swift", file(200)),
        ("/h/dev/proj/build/o.bin", file(1_000)), ("/h/dev/notes.txt", file(10)),
        ("/h/other/x.txt", file(5)),
    ])

    private func effective(_ resolved: ResolvedDecisions, _ path: String) -> Decision {
        Decision(rawValue: resolved.effective[Int(tree.find(path: path)!)])!
    }

    func testDecisionInheritsDownAndDeepestWins() {
        let store = DecisionStore(fileURL: nil)
        store.set(.remove, paths: ["/h/dev"], tree: tree)
        store.set(.keep, paths: ["/h/dev/proj/src"], tree: tree)
        store.set(.later, paths: ["/h/dev/proj/src/b.swift"], tree: tree)
        let resolved = store.resolve(tree: tree)
        XCTAssertEqual(effective(resolved, "/h/dev/proj/build/o.bin"), .remove)
        XCTAssertEqual(effective(resolved, "/h/dev/proj/src/a.swift"), .keep)
        XCTAssertEqual(effective(resolved, "/h/dev/proj/src/b.swift"), .later)
        XCTAssertEqual(effective(resolved, "/h/other/x.txt"), .none)
    }

    func testPartialMarksOnlyRemoveDirectoriesThatHoldSomethingElse() {
        let store = DecisionStore(fileURL: nil)
        store.set(.remove, paths: ["/h/dev"], tree: tree)
        store.set(.keep, paths: ["/h/dev/proj/src/a.swift"], tree: tree)
        let resolved = store.resolve(tree: tree)
        func partial(_ p: String) -> Bool { resolved.partial[Int(tree.find(path: p)!)] }
        XCTAssertTrue(partial("/h/dev"))
        XCTAssertTrue(partial("/h/dev/proj"))
        XCTAssertTrue(partial("/h/dev/proj/src"))
        XCTAssertFalse(partial("/h/dev/proj/build"))
        XCTAssertFalse(partial("/h/other"))
    }

    func testTotalsCountEachByteOnceAndRespectKeepInsideRemove() {
        let store = DecisionStore(fileURL: nil)
        store.set(.remove, paths: ["/h/dev"], tree: tree)
        store.set(.keep, paths: ["/h/dev/proj/src/a.swift"], tree: tree)
        let resolved = store.resolve(tree: tree)
        XCTAssertEqual(resolved.keepBytes, 100)
        XCTAssertEqual(resolved.removeBytes, 200 + 1_000 + 10)
        XCTAssertEqual(resolved.removeRoots, 3)  // b.swift, build, notes.txt
        XCTAssertEqual(resolved.undecided, 1)  // other/x.txt
    }

    func testUndoRedoAndVersion() {
        let store = DecisionStore(fileURL: nil)
        let start = store.version
        store.set(.remove, paths: ["/h/dev/notes.txt", "/h/other/x.txt"], tree: tree)
        XCTAssertGreaterThan(store.version, start)
        XCTAssertEqual(store.resolve(tree: tree).removeRoots, 2)
        XCTAssertTrue(store.undo())
        XCTAssertEqual(store.resolve(tree: tree).removeRoots, 0, "one set call is one undo step")
        XCTAssertFalse(store.undo())
        XCTAssertTrue(store.redo())
        XCTAssertEqual(store.resolve(tree: tree).removeRoots, 2)
        XCTAssertFalse(store.redo())
    }

    func testNewSetClearsRedoAndNoOpAddsNoStep() {
        let store = DecisionStore(fileURL: nil)
        store.set(.keep, paths: ["/h/other"], tree: tree)
        store.undo()
        store.set(.remove, paths: ["/h/other"], tree: tree)
        XCTAssertFalse(store.redo())
        let version = store.version
        store.set(.remove, paths: ["/h/other"], tree: tree)
        XCTAssertEqual(store.version, version)
        store.set(.remove, paths: ["/h/not/in/tree"], tree: tree)
        XCTAssertEqual(store.version, version)
    }

    func testClearingWithNoneRemovesTheVerdict() {
        let store = DecisionStore(fileURL: nil)
        store.set(.remove, paths: ["/h/other"], tree: tree)
        store.set(.none, paths: ["/h/other"], tree: tree)
        XCTAssertEqual(store.resolve(tree: tree).removeRoots, 0)
    }

    func testDecisionsPersistAcrossInstances() throws {
        let box = try Sandbox()
        defer { box.tearDown() }
        let url = URL(fileURLWithPath: box.path("decisions.json"))
        DecisionStore(fileURL: url).set(.remove, paths: ["/h/other"], tree: tree)
        let reopened = DecisionStore(fileURL: url)
        XCTAssertEqual(reopened.resolve(tree: tree).removeRoots, 1)
    }

    func testCorruptFileIsSetAsideNotCrashed() throws {
        let box = try Sandbox()
        defer { box.tearDown() }
        try box.file("decisions.json", "{not json")
        let store = DecisionStore(fileURL: URL(fileURLWithPath: box.path("decisions.json")))
        XCTAssertEqual(store.resolve(tree: tree).removeRoots, 0)
        XCTAssertTrue(box.exists("decisions.json.unreadable"))
    }

    func testChangedFileIsStaleAndStaleRemoveIsNotApplied() {
        let store = DecisionStore(fileURL: nil)
        store.set(.remove, paths: ["/h/dev/notes.txt"], tree: tree)
        let changed = makeTree([
            ("/h/dev/proj/src/a.swift", file(100)), ("/h/dev/proj/src/b.swift", file(200)),
            ("/h/dev/proj/build/o.bin", file(1_000)), ("/h/dev/notes.txt", file(10, modified: 999)),
            ("/h/other/x.txt", file(5)),
        ])
        let resolved = store.resolve(tree: changed)
        XCTAssertEqual(resolved.stalePaths, ["/h/dev/notes.txt"])
        XCTAssertEqual(resolved.removeRoots, 0)
        XCTAssertEqual(resolved.removeBytes, 0)
    }

    func testStaleKeepStillProtects() {
        let store = DecisionStore(fileURL: nil)
        store.set(.remove, paths: ["/h/dev"], tree: tree)
        store.set(.keep, paths: ["/h/dev/notes.txt"], tree: tree)
        let changed = makeTree([
            ("/h/dev/proj/src/a.swift", file(100)), ("/h/dev/proj/src/b.swift", file(200)),
            ("/h/dev/proj/build/o.bin", file(1_000)), ("/h/dev/notes.txt", file(99, modified: 999)),
            ("/h/other/x.txt", file(5)),
        ])
        let resolved = store.resolve(tree: changed)
        XCTAssertEqual(resolved.stalePaths, ["/h/dev/notes.txt"])
        XCTAssertEqual(Decision(rawValue: resolved.effective[Int(changed.find(path: "/h/dev/notes.txt")!)]), .keep)
    }

    func testVerdictsForPathsAbsentFromAScanAreKeptButIgnored() {
        let store = DecisionStore(fileURL: nil)
        store.set(.remove, paths: ["/h/other/x.txt"], tree: tree)
        let smaller = makeTree([("/h/dev/notes.txt", file(10))])
        let resolved = store.resolve(tree: smaller)
        XCTAssertEqual(resolved.removeRoots, 0)
        XCTAssertTrue(resolved.stalePaths.isEmpty)
        XCTAssertEqual(store.resolve(tree: tree).removeRoots, 1)
    }
}

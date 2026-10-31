import XCTest
import DYCore
@testable import DYDecide

final class RemovalPlannerTests: XCTestCase {
    private let home = "/Users/me"

    private func fixture(extra: [(String, Spec)] = []) -> FileTree {
        makeTree([
            ("/Users/me/Documents/a.txt", file()), ("/Users/me/Desktop/b.txt", file()),
            ("/Users/me/Downloads/old.zip", file(5_000)), ("/Users/me/Downloads/big/x.bin", file(7_000)),
            ("/Users/me/Library/Caches/com.example/c1", file(9_000)), ("/Users/me/Library/Preferences/p.plist", file()),
            ("/Users/me/Pictures/Photos Library.photoslibrary/originals/p1.heic", file(6_000)),
            ("/Users/me/Pictures/trip/img.jpg", file(2_000)),
            ("/Users/me/dev/proj/src/a.swift", file()), ("/Users/me/dev/proj/src/b.swift", file()),
            ("/Users/me/dev/proj/src/deep/z.swift", file()), ("/Users/me/dev/proj/src/deep/w.swift", file()),
            ("/Users/me/dev/proj/build/o1", file(4_000)),
            ("/Applications/App.app/bin", file()), ("/System/x", file()), ("/usr/bin/tool", file()),
            ("/Volumes/Mac/f", file()), ("/tmp/scratch/s.txt", file()),
        ] + extra)
    }

    /// Plans with decisions applied through a real in-memory store.
    private func plan(_ tree: FileTree, remove: [String] = [], keep: [String] = [], later: [String] = [],
                      tier: [UInt8] = []) -> RemovalPlan {
        let store = DecisionStore(fileURL: nil)
        store.set(.remove, paths: remove, tree: tree)
        store.set(.keep, paths: keep, tree: tree)
        store.set(.later, paths: later, tree: tree)
        return RemovalPlanner.plan(tree: tree, resolved: store.resolve(tree: tree), nodeTier: tier, home: home)
    }

    private func ids(_ plan: RemovalPlan) -> [String] { plan.items.map(\.id).sorted() }
    private func blockedPaths(_ plan: RemovalPlan) -> [String] { plan.blocked.map(\.path) }

    // MARK: - Guards on the node itself

    func testMarkingTheScanRootPlansNothing() {
        let tree = fixture()
        let result = plan(tree, remove: ["/"])
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(blockedPaths(result), ["/"])
    }

    func testEveryNodeMarkedRemovePlansNothing() {
        let tree = fixture()
        let everything = ResolvedDecisions(effective: [UInt8](repeating: Decision.remove.rawValue, count: tree.count))
        let result = RemovalPlanner.plan(tree: tree, resolved: everything, nodeTier: [], home: home)
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(blockedPaths(result), ["/"])
    }

    func testHomeAndAncestorsOfHomeAreBlocked() {
        let tree = fixture()
        for path in ["/Users/me", "/Users"] {
            let result = plan(tree, remove: [path])
            XCTAssertTrue(result.items.isEmpty, path)
            XCTAssertEqual(blockedPaths(result), [path])
        }
    }

    func testHomeBlockedWhenTheTreeRootIsHomeItself() {
        let tree = makeTree(root: "/Users/me", [("/Users/me/dev/a", file()), ("/Users/me/b", file())])
        let result = plan(tree, remove: ["/Users/me"])
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(blockedPaths(result), ["/Users/me"])
    }

    func testSystemFoldersAndTopLevelFoldersAreBlocked() {
        let tree = fixture()
        for path in ["/System", "/Applications", "/usr", "/Volumes", "/tmp"] {
            let result = plan(tree, remove: [path])
            XCTAssertTrue(result.items.isEmpty, path)
            XCTAssertEqual(blockedPaths(result), [path])
        }
    }

    func testStandardUserFoldersThemselvesAreBlockedButTheirContentsAreNot() {
        let tree = fixture()
        for folder in ["Library", "Documents", "Desktop", "Pictures", "Downloads"] {
            let result = plan(tree, remove: ["/Users/me/" + folder])
            XCTAssertTrue(result.items.isEmpty, folder)
            XCTAssertEqual(blockedPaths(result), ["/Users/me/" + folder])
        }
        let inside = plan(tree, remove: ["/Users/me/Downloads/old.zip", "/Users/me/Library/Caches/com.example"])
        XCTAssertEqual(ids(inside), ["/Users/me/Downloads/old.zip", "/Users/me/Library/Caches/com.example"])
        XCTAssertTrue(inside.blocked.isEmpty)
    }

    func testGuardsMatchWithoutRegardToCase() {
        let tree = makeTree([("/users/ME/documents/a", file()), ("/Users/me/x", file())])
        let result = plan(tree, remove: ["/users/ME/documents"])
        XCTAssertTrue(result.items.isEmpty)
    }

    func testRestrictedMountBoundaryAndUnreadableNodesAreBlocked() {
        let tree = fixture(extra: [
            ("/Users/me/dev/sip", dir(.restricted)), ("/Users/me/dev/mnt", dir(.mountBoundary)),
            ("/Users/me/dev/locked", dir(.unreadable)),
        ])
        for name in ["sip", "mnt", "locked"] {
            let path = "/Users/me/dev/" + name
            let result = plan(tree, remove: [path])
            XCTAssertTrue(result.items.isEmpty, name)
            XCTAssertEqual(blockedPaths(result), [path])
        }
    }

    func testTierNeverIsBlocked() {
        let tree = fixture()
        var tier = [UInt8](repeating: 0, count: tree.count)
        tier[Int(tree.find(path: "/Users/me/dev/proj/build")!)] = SafetyTier.never.rawValue
        let result = plan(tree, remove: ["/Users/me/dev/proj/build"], tier: tier)
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(blockedPaths(result), ["/Users/me/dev/proj/build"])
    }

    func testMismatchedInputPlansNothing() {
        let tree = fixture()
        let short = ResolvedDecisions(effective: [2, 2])
        XCTAssertTrue(RemovalPlanner.plan(tree: tree, resolved: short, nodeTier: [], home: home).items.isEmpty)
        let ok = ResolvedDecisions(effective: [UInt8](repeating: 0, count: tree.count))
        XCTAssertTrue(RemovalPlanner.plan(tree: tree, resolved: ok, nodeTier: [1, 2], home: home).items.isEmpty)
    }

    // MARK: - Guards on what a directory holds

    func testDirectoryHoldingGuardedNodesIsSplitNotMoved() {
        let tree = fixture(extra: [
            ("/Users/me/dev/proj/mnt", dir(.mountBoundary)), ("/Users/me/dev/proj/sip", dir(.restricted)),
        ])
        let result = plan(tree, remove: ["/Users/me/dev/proj"])
        XCTAssertFalse(ids(result).contains("/Users/me/dev/proj"))
        XCTAssertEqual(ids(result), ["/Users/me/dev/proj/build", "/Users/me/dev/proj/src"])
        XCTAssertEqual(Set(blockedPaths(result)), ["/Users/me/dev/proj/mnt", "/Users/me/dev/proj/sip"])
    }

    func testPhotosLibraryItselfAndAnythingInsideIsBlocked() {
        let tree = fixture()
        let library = "/Users/me/Pictures/Photos Library.photoslibrary"
        for path in [library, library + "/originals", library + "/originals/p1.heic"] {
            let result = plan(tree, remove: [path])
            XCTAssertTrue(result.items.isEmpty, path)
            XCTAssertEqual(blockedPaths(result), [path])
        }
    }

    func testDirectoryHoldingAPhotosLibraryIsSplitAroundIt() {
        let tree = makeTree([
            ("/Users/me/stuff/Old.photoslibrary/m/p", file()), ("/Users/me/stuff/keepme/k", file()),
            ("/Users/me/stuff/junk/j", file()), ("/Users/me/other", file()),
        ])
        let result = plan(tree, remove: ["/Users/me/stuff"])
        XCTAssertEqual(ids(result), ["/Users/me/stuff/junk", "/Users/me/stuff/keepme"])
        XCTAssertEqual(blockedPaths(result), ["/Users/me/stuff/Old.photoslibrary"])
    }

    func testTierNeverInsideADirectorySplitsIt() {
        let tree = fixture()
        var tier = [UInt8](repeating: 0, count: tree.count)
        tier[Int(tree.find(path: "/Users/me/dev/proj/src/deep")!)] = SafetyTier.never.rawValue
        let result = plan(tree, remove: ["/Users/me/dev/proj"], tier: tier)
        XCTAssertEqual(ids(result), ["/Users/me/dev/proj/build", "/Users/me/dev/proj/src/a.swift", "/Users/me/dev/proj/src/b.swift"])
        XCTAssertEqual(blockedPaths(result), ["/Users/me/dev/proj/src/deep"])
    }

    // MARK: - Minimal roots and keep inside remove

    func testAncestorAndChildBothMarkedPlansOnlyTheAncestor() {
        let tree = fixture()
        let result = plan(tree, remove: ["/Users/me/dev/proj/src/deep/z.swift", "/Users/me/dev/proj/src", "/Users/me/dev"])
        XCTAssertEqual(ids(result), ["/Users/me/dev"])
    }

    func testChildMarkedBeforeAncestorGivesTheSameResult() {
        let tree = fixture()
        let result = plan(tree, remove: ["/Users/me/dev"])
        let again = plan(tree, remove: ["/Users/me/dev/proj", "/Users/me/dev"])
        XCTAssertEqual(ids(result), ids(again))
    }

    func testKeepInsideRemoveAtSeveralDepthsSplitsTheDirectory() {
        let tree = fixture()
        let cases: [(keep: String, expected: [String])] = [
            ("/Users/me/dev/proj/build", ["/Users/me/dev/proj/src"]),
            ("/Users/me/dev/proj/src/a.swift",
             ["/Users/me/dev/proj/build", "/Users/me/dev/proj/src/b.swift", "/Users/me/dev/proj/src/deep"]),
            ("/Users/me/dev/proj/src/deep/z.swift",
             ["/Users/me/dev/proj/build", "/Users/me/dev/proj/src/a.swift", "/Users/me/dev/proj/src/b.swift",
              "/Users/me/dev/proj/src/deep/w.swift"]),
        ]
        for (keep, expectedSiblings) in cases {
            let result = plan(tree, remove: ["/Users/me/dev/proj"], keep: [keep])
            XCTAssertEqual(ids(result), expectedSiblings.sorted(), keep)
            XCTAssertEqual(result.protected, [keep])
            for item in result.items {
                XCTAssertFalse(keep.hasPrefix(item.id + "/") || keep == item.id, "\(item.id) would take \(keep) with it")
            }
        }
    }

    func testLaterBehavesLikeKeep() {
        let tree = fixture()
        let result = plan(tree, remove: ["/Users/me/dev/proj"], later: ["/Users/me/dev/proj/build/o1"])
        XCTAssertFalse(ids(result).contains("/Users/me/dev/proj/build"))
        XCTAssertEqual(result.protected, ["/Users/me/dev/proj/build/o1"])
    }

    func testRemoveInsideAKeptDirectoryIsItsOwnRoot() {
        let tree = fixture()
        let result = plan(tree, remove: ["/Users/me/dev/proj/src/deep/z.swift"], keep: ["/Users/me/dev/proj"])
        XCTAssertEqual(ids(result), ["/Users/me/dev/proj/src/deep/z.swift"])
    }

    func testPlanTotalsAndOrder() {
        let tree = fixture()
        let result = plan(tree, remove: ["/Users/me/Downloads/old.zip", "/Users/me/Downloads/big", "/Users/me/dev/proj/build"])
        XCTAssertEqual(result.items.map(\.bytes), [7_000, 5_000, 4_000])
        XCTAssertEqual(result.totalBytes, 16_000)
        XCTAssertEqual(result.totalReclaimable, 16_000)
    }

    func testSharedBlocksMakeReclaimableALowerBound() {
        let tree = fixture(extra: [("/Users/me/dev/clone.bin", file(3_000, flags: .mayShareBlocks))])
        let result = plan(tree, remove: ["/Users/me/dev/clone.bin", "/Users/me/dev/proj/build"])
        let byPath = Dictionary(uniqueKeysWithValues: result.items.map { ($0.id, $0) })
        XCTAssertTrue(byPath["/Users/me/dev/clone.bin"]!.reclaimIsLowerBound)
        XCTAssertFalse(byPath["/Users/me/dev/proj/build"]!.reclaimIsLowerBound)
    }

    // MARK: - Symlinks and staleness

    func testSymlinkIsPlannedAsTheLinkItself() {
        let tree = fixture(extra: [("/Users/me/dev/link", file(40, flags: .symlink))])
        let result = plan(tree, remove: ["/Users/me/dev/link"])
        XCTAssertEqual(ids(result), ["/Users/me/dev/link"])
        XCTAssertEqual(result.items.first?.bytes, 40)
    }

    func testPathChangedSinceScanIsBlockedAndNeverPlanned() {
        let scanned = fixture()
        let store = DecisionStore(fileURL: nil)
        store.set(.remove, paths: ["/Users/me/dev/proj/build", "/Users/me/Downloads/old.zip"], tree: scanned)
        let rescanned = fixture()
        XCTAssertEqual(RemovalPlanner.plan(tree: rescanned, resolved: store.resolve(tree: rescanned), nodeTier: [], home: home).items.count, 2,
                       "an unchanged rescan keeps the verdicts valid")
        let changed = makeTree([
            ("/Users/me/dev/proj/build/o1", file(4_000, modified: 777)),
            ("/Users/me/Downloads/old.zip", file(5_001)),
        ])
        let result = RemovalPlanner.plan(tree: changed, resolved: store.resolve(tree: changed), nodeTier: [], home: home)
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(blockedPaths(result), ["/Users/me/Downloads/old.zip", "/Users/me/dev/proj/build"])
        XCTAssertEqual(Set(result.blocked.map(\.reason)), ["Changed since you marked it"])
    }

    func testStaleVerdictInsideRemovedDirectoryCarvesItOut() {
        let layout: (Int32) -> FileTree = { modified in
            makeTree([
                ("/Users/me/dev/proj/src/a.swift", file()), ("/Users/me/dev/proj/src/b.swift", file(modified: modified)),
                ("/Users/me/dev/proj/build/o1", file(4_000)),
            ])
        }
        let store = DecisionStore(fileURL: nil)
        let scanned = layout(100)
        store.set(.remove, paths: ["/Users/me/dev/proj", "/Users/me/dev/proj/src/b.swift"], tree: scanned)
        let rescanned = layout(555)
        let result = RemovalPlanner.plan(tree: rescanned, resolved: store.resolve(tree: rescanned), nodeTier: [], home: home)
        XCTAssertFalse(ids(result).contains("/Users/me/dev/proj"))
        XCTAssertFalse(ids(result).contains("/Users/me/dev/proj/src/b.swift"))
        XCTAssertEqual(ids(result), ["/Users/me/dev/proj/build", "/Users/me/dev/proj/src/a.swift"])
        XCTAssertEqual(blockedPaths(result), ["/Users/me/dev/proj/src/b.swift"])
    }

    // MARK: - Property: whatever is marked, the invariants hold

    func testRandomDecisionsAlwaysSatisfyTheInvariants() {
        let tree = SyntheticTree.make(seed: 7, scale: 0.05, rootPath: "/")
        var state: UInt64 = 0x9E3779B97F4A7C15
        func next() -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int(state >> 33)
        }
        for round in 0..<40 {
            var explicit = [UInt8](repeating: 0, count: tree.count)
            for _ in 0..<(1 + next() % 40) {
                explicit[next() % tree.count] = UInt8(1 + next() % 3)
            }
            explicit[0] = round % 10 == 0 ? Decision.remove.rawValue : 0
            let effective = DecisionResolver.inherit(explicit, tree: tree)
            let resolved = ResolvedDecisions(effective: effective)
            let result = RemovalPlanner.plan(tree: tree, resolved: resolved, nodeTier: [], home: "/Users/demo")
            assertInvariants(result, tree: tree, effective: effective)
        }
    }

    private func assertInvariants(_ plan: RemovalPlan, tree: FileTree, effective: [UInt8]) {
        let protectedNodes = (0..<tree.count).filter { effective[$0] != Decision.remove.rawValue }
        let forbidden = ["/", "/Users", "/Users/demo", "/System", "/Applications", "/Library", "/Users/demo/Library",
                         "/Users/demo/Documents", "/Users/demo/Pictures", "/Users/demo/Movies", "/Users/demo/Music"]
        for item in plan.items {
            XCTAssertEqual(effective[Int(item.node)], Decision.remove.rawValue)
            XCTAssertFalse(forbidden.contains(item.id), item.id)
            XCTAssertFalse(item.id.lowercased().contains(".photoslibrary"), item.id)
            XCTAssertNotEqual(item.node, 0)
            for other in plan.items where other.node != item.node {
                XCTAssertFalse(tree.isAncestor(item.node, of: other.node), "\(item.id) contains \(other.id)")
            }
            for node in protectedNodes where tree.isAncestor(item.node, of: NodeID(node)) {
                // A protected node under an item is only allowed if a deeper remove-effective chain doesn't apply: never.
                XCTFail("\(item.id) would take protected \(tree.path(NodeID(node))) with it")
                break
            }
        }
    }
}

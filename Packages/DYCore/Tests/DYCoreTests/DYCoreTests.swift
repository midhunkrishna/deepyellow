import XCTest
@testable import DYCore

final class FileTreeTests: XCTestCase {
    /// Builds `/a/{big.mov 300, small.txt 50}` and `/b/c/deep.zip 100` with zero-size directories.
    private func sampleTree() -> FileTree {
        let builder = TreeBuilder(rootPath: "/")
        let a = builder.add(parent: 0, name: "a", record: NodeRecord(flags: .directory))
        builder.add(parent: a, name: "big.mov", record: NodeRecord(allocated: 300, logical: 300, kind: .video))
        builder.add(parent: a, name: "small.txt", record: NodeRecord(allocated: 50, logical: 50, kind: .document))
        let b = builder.add(parent: 0, name: "b", record: NodeRecord(flags: .directory))
        let c = builder.add(parent: b, name: "c", record: NodeRecord(flags: .directory))
        builder.add(parent: c, name: "deep.zip", record: NodeRecord(allocated: 100, logical: 100, kind: .archive))
        return builder.freeze()
    }

    func testFreezeUpholdsLayoutInvariants() {
        let tree = SyntheticTree.make(scale: 0.05)
        for index in 1..<tree.count { XCTAssertLessThan(tree.columns.parent[index], Int32(index)) }
        for node in 0..<NodeID(tree.count) {
            let sizes = tree.children(node).map { tree.allocated($0) }
            XCTAssertEqual(sizes, sizes.sorted(by: >))
            for child in tree.children(node) { XCTAssertEqual(tree.parent(child), node) }
        }
    }

    func testRollupsAndPathsAreCorrect() throws {
        let tree = sampleTree()
        XCTAssertEqual(tree.allocated(0), 450)
        XCTAssertEqual(tree.fileCount(0), 3)
        let deep = try XCTUnwrap(tree.find(path: "/b/c/deep.zip"))
        XCTAssertEqual(tree.path(deep), "/b/c/deep.zip")
        XCTAssertEqual(tree.depth(deep), 3)
        XCTAssertEqual(tree.name(tree.parent(deep)), "c")
        XCTAssertTrue(tree.isAncestor(0, of: deep))
        XCTAssertNil(tree.find(path: "/nope"))
    }

    func testSyntheticTreeIsDeterministic() {
        let first = SyntheticTree.make(seed: 7, scale: 0.05), second = SyntheticTree.make(seed: 7, scale: 0.05)
        XCTAssertEqual(first.count, second.count)
        XCTAssertEqual(first.allocated(0), second.allocated(0))
        XCTAssertEqual(first.columns.nameBytes, second.columns.nameBytes)
    }

    func testSnapshotStaysWithinBudgetAndKeepsTotals() {
        let builder = TreeBuilder(rootPath: "/")
        for dirIndex in 0..<50 {
            let dir = builder.add(parent: 0, name: "d\(dirIndex)", record: NodeRecord(flags: .directory))
            for fileIndex in 0..<100 {
                builder.add(parent: dir, name: "f\(fileIndex)", record: NodeRecord(allocated: UInt64(dirIndex + 1) * 10, logical: 10))
            }
        }
        let snapshot = builder.snapshot(maxNodes: 1_000)
        XCTAssertLessThanOrEqual(snapshot.count, 1_200)
        XCTAssertEqual(snapshot.allocated(0), builder.totalAllocated)
        XCTAssertEqual(snapshot.name(snapshot.children(0).lowerBound), "d49")
        XCTAssertGreaterThan(snapshot.childCount(of: snapshot.children(0).lowerBound), 0)
    }
}

final class TreeLensTests: XCTestCase {
    private func sampleTree() -> FileTree {
        let builder = TreeBuilder(rootPath: "/")
        let a = builder.add(parent: 0, name: "a", record: NodeRecord(flags: .directory))
        builder.add(parent: a, name: "big.mov", record: NodeRecord(allocated: 300, logical: 300, kind: .video))
        builder.add(parent: a, name: "small.txt", record: NodeRecord(allocated: 50, logical: 50, kind: .document))
        let b = builder.add(parent: 0, name: "b", record: NodeRecord(flags: .directory))
        builder.add(parent: b, name: "deep.zip", record: NodeRecord(allocated: 100, logical: 100, kind: .archive))
        return builder.freeze()
    }

    func testPlainLensMatchesTree() {
        let tree = sampleTree()
        let lens = TreeLens(tree: tree)
        XCTAssertEqual(lens.size, tree.columns.allocated)
        XCTAssertEqual(lens.hiddenBytes, 0)
        XCTAssertEqual(lens.filteredBytes, 0)
    }

    func testHidingADirectoryAccountsForItsBytesOnce() throws {
        let tree = sampleTree()
        var hidden = [Bool](repeating: false, count: tree.count)
        hidden[Int(try XCTUnwrap(tree.find(path: "/a")))] = true
        let lens = TreeLens(tree: tree, hidden: hidden)
        XCTAssertEqual(lens.size[0], 100)
        XCTAssertEqual(lens.hiddenBytes, 350)
        XCTAssertEqual(lens.hiddenFiles, 2)
        XCTAssertEqual(lens.size[0] + lens.hiddenBytes, tree.allocated(0))
    }

    func testQueryKeepsOnlyMatchingFilesAndTheirAncestors() throws {
        let tree = sampleTree()
        let movie = try XCTUnwrap(tree.find(path: "/a/big.mov"))
        var matches = [Bool](repeating: false, count: tree.count)
        matches[Int(movie)] = true
        let lens = TreeLens(tree: tree, matches: matches)
        XCTAssertEqual(lens.size[0], 300)
        XCTAssertEqual(lens.files[0], 1)
        XCTAssertEqual(lens.filteredBytes, 150)
        XCTAssertFalse(lens.included[Int(try XCTUnwrap(tree.find(path: "/b")))])
        XCTAssertEqual(lens.visibleChildren(of: 0), [try XCTUnwrap(tree.find(path: "/a"))])
    }

    func testRemovedBytesAreNotReportedAsHidden() throws {
        let tree = sampleTree()
        var removed = [Bool](repeating: false, count: tree.count)
        removed[Int(try XCTUnwrap(tree.find(path: "/b")))] = true
        let lens = TreeLens(tree: tree, removed: removed)
        XCTAssertEqual(lens.removedBytes, 100)
        XCTAssertEqual(lens.hiddenBytes, 0)
        XCTAssertEqual(lens.filteredBytes, 0)
        XCTAssertEqual(lens.size[0], 350)
    }

    func testDominantKindFollowsBytes() throws {
        let tree = sampleTree()
        let kinds = TreeLens(tree: tree).dominantKinds()
        XCTAssertEqual(kinds[Int(try XCTUnwrap(tree.find(path: "/a")))], FileKind.video.rawValue)
        XCTAssertEqual(kinds[0], FileKind.video.rawValue)
    }

    func testMetricCanRankByFileCount() {
        let builder = TreeBuilder(rootPath: "/")
        let swarm = builder.add(parent: 0, name: "swarm", record: NodeRecord(flags: .directory))
        for index in 0..<10 { builder.add(parent: swarm, name: "f\(index)", record: NodeRecord(allocated: 1)) }
        builder.add(parent: 0, name: "giant", record: NodeRecord(allocated: 1_000))
        let tree = builder.freeze()
        let lens = TreeLens(tree: tree)
        XCTAssertEqual(tree.name(lens.visibleChildren(of: 0, metric: .bytes)[0]), "giant")
        XCTAssertEqual(tree.name(lens.visibleChildren(of: 0, metric: .files)[0]), "swarm")
    }
}

final class FormatTests: XCTestCase {
    func testBytesMatchFinderUnits() {
        XCTAssertEqual(Format.bytes(0), "0 B")
        XCTAssertEqual(Format.bytes(999), "999 B")
        XCTAssertEqual(Format.bytes(400_000_000), "400 MB")
        XCTAssertEqual(Format.bytes(4_210_000_000), "4.21 GB")
    }

    func testPercentNeverRoundsAwayANonZeroShare() {
        XCTAssertEqual(Format.percent(1, of: 1_000_000), "<0.1%")
        XCTAssertEqual(Format.percent(0, of: 10), "0%")
        XCTAssertEqual(Format.percent(1, of: 2), "50%")
    }
}

final class FileKindClassifierTests: XCTestCase {
    func testClassification() {
        XCTAssertEqual(FileKindClassifier.classify("Wedding.MOV"), .video)
        XCTAssertEqual(FileKindClassifier.classify("photo.heic"), .image)
        XCTAssertEqual(FileKindClassifier.classify("Xcode_15.2.xip"), .archive)
        XCTAssertEqual(FileKindClassifier.classify("index.ts"), .code)
        XCTAssertEqual(FileKindClassifier.classify(".DS_Store"), .other)
        XCTAssertEqual(FileKindClassifier.classify("noextension"), .other)
    }
}

private extension FileTree {
    func childCount(of id: NodeID) -> Int { children(id).count }
}

import DYCore
import DYScan
import Foundation
import XCTest

final class ScanCacheTests: XCTestCase {
    private var fixture: Fixture!

    override func setUpWithError() throws { fixture = try Fixture() }
    override func tearDown() { fixture.tearDown() }

    private func assertIdentical(_ lhs: FileTree, _ rhs: FileTree, file: StaticString = #filePath, line: UInt = #line) {
        let a = lhs.columns, b = rhs.columns
        XCTAssertEqual(lhs.meta, rhs.meta, file: file, line: line)
        XCTAssertEqual(a.parent, b.parent, file: file, line: line)
        XCTAssertEqual(a.firstChild, b.firstChild, file: file, line: line)
        XCTAssertEqual(a.childCount, b.childCount, file: file, line: line)
        XCTAssertEqual(a.allocated, b.allocated, file: file, line: line)
        XCTAssertEqual(a.logical, b.logical, file: file, line: line)
        XCTAssertEqual(a.privateBytes, b.privateBytes, file: file, line: line)
        XCTAssertEqual(a.fileCount, b.fileCount, file: file, line: line)
        XCTAssertEqual(a.modified, b.modified, file: file, line: line)
        XCTAssertEqual(a.accessed, b.accessed, file: file, line: line)
        XCTAssertEqual(a.flags, b.flags, file: file, line: line)
        XCTAssertEqual(a.kind, b.kind, file: file, line: line)
        XCTAssertEqual(a.inode, b.inode, file: file, line: line)
        XCTAssertEqual(a.nameOffset, b.nameOffset, file: file, line: line)
        XCTAssertEqual(a.nameLength, b.nameLength, file: file, line: line)
        XCTAssertEqual(a.nameBytes, b.nameBytes, file: file, line: line)
    }

    func testRoundTripsASyntheticTreeExactly() throws {
        let tree = SyntheticTree.make(scale: 0.05)
        let url = URL(fileURLWithPath: fixture.path("cache/tree.dyscan"))
        try ScanCache.save(tree, to: url)
        assertIdentical(tree, try ScanCache.load(from: url))
    }

    func testRoundTripsAScannedTreeIncludingMeta() async throws {
        try fixture.writeFile("a/b.txt", count: 100)
        let (tree, _) = await runScan(root: fixture.root)
        let url = URL(fileURLWithPath: fixture.path("out.dyscan"))
        try ScanCache.save(tree, to: url)
        assertIdentical(tree, try ScanCache.load(from: url))
    }

    func testRejectsGarbageAndTruncatedFiles() throws {
        let garbage = URL(fileURLWithPath: fixture.path("garbage"))
        try Data("not a cache".utf8).write(to: garbage)
        XCTAssertThrowsError(try ScanCache.load(from: garbage))
        let url = URL(fileURLWithPath: fixture.path("t.dyscan"))
        try ScanCache.save(SyntheticTree.make(scale: 0.02), to: url)
        let full = try Data(contentsOf: url)
        try full.prefix(full.count / 2).write(to: garbage)
        XCTAssertThrowsError(try ScanCache.load(from: garbage))
        XCTAssertThrowsError(try ScanCache.load(from: URL(fileURLWithPath: fixture.path("absent"))))
    }

    func testDefaultURLIsStablePerRootAndInApplicationSupport() {
        let a = ScanCache.defaultURL(forRoot: "/Users/someone")
        XCTAssertEqual(a, ScanCache.defaultURL(forRoot: "/Users/someone"))
        XCTAssertNotEqual(a, ScanCache.defaultURL(forRoot: "/Users/other"))
        XCTAssertTrue(a.path.contains("/Library/Application Support/DeepYellow/scans/"))
        XCTAssertEqual(ScanCache.defaultURL(forRoot: "/").deletingLastPathComponent(), a.deletingLastPathComponent())
    }
}

final class SystemInfoTests: XCTestCase {
    func testMountedVolumesIncludeTheBootVolume() throws {
        let volumes = VolumeInfo.mounted()
        let boot = try XCTUnwrap(volumes.first { $0.path == "/" })
        XCTAssertGreaterThan(boot.total, 0)
        XCTAssertLessThanOrEqual(boot.available, boot.total)
        XCTAssertTrue(boot.isInternal || !boot.isInternal)
        XCTAssertEqual(boot.id, boot.path)
        XCTAssertFalse(boot.name.isEmpty)
    }

    func testFullDiskAccessProbeAnswers() {
        let first = FullDiskAccess.probe()
        XCTAssertEqual(first, FullDiskAccess.probe())
    }
}

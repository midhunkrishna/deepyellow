import DYCore
import XCTest
@testable import DYAdvisor

final class DuplicateFinderTests: XCTestCase {
    private func run(_ tree: FileTree, _ reader: FakeReader, minimum: UInt64 = 1,
                     isCancelled: @escaping @Sendable () -> Bool = { false }) async -> DuplicateReport {
        await DuplicateFinder.find(lens: TreeLens(tree: tree), minimumSize: minimum, reader: reader,
                                   progress: { _ in }, isCancelled: isCancelled)
    }

    private func bytes(_ text: String, count: Int) -> Data { Data(repeating: text.utf8.first!, count: count) }

    func testFindsDuplicatesAndWastedBytes() async {
        let tree = makeTree([file("/a", 100), file("/b", 100), file("/c", 100), file("/d", 100)])
        let reader = FakeReader(["/a": bytes("x", count: 100), "/b": bytes("x", count: 100), "/c": bytes("x", count: 100), "/d": bytes("y", count: 100)])
        let report = await run(tree, reader)
        XCTAssertEqual(report.sets.count, 1)
        XCTAssertEqual(report.sets[0].nodes.count, 3)
        XCTAssertEqual(report.sets[0].wastedBytes, 200)
        XCTAssertEqual(report.sets[0].id.count, 64)
        XCTAssertGreaterThan(report.bytesHashed, 0)
    }

    func testSameSizeDifferentContentIsNotReported() async {
        let tree = makeTree([file("/a", 100), file("/b", 100)])
        var other = bytes("x", count: 100)
        other[50] = 0x7a
        let report = await run(tree, FakeReader(["/a": bytes("x", count: 100), "/b": other]))
        XCTAssertTrue(report.sets.isEmpty)
    }

    func testHeadAndTailMatchButMiddleDiffers() async {
        let size = 300_000
        let tree = makeTree([file("/a", UInt64(size)), file("/b", UInt64(size))])
        var different = bytes("x", count: size)
        different[150_000] = 0x01
        let report = await run(tree, FakeReader(["/a": bytes("x", count: size), "/b": different]))
        XCTAssertTrue(report.sets.isEmpty)
    }

    func testExcludesHardlinkCloneDatalessRestrictedPackageAndSymlinks() async {
        let tree = makeTree([
            file("/orig", 100), file("/hard", 100, .hardlinkDuplicate), file("/clone", 100, .cloneDuplicate),
            file("/cloud", 100, .dataless), file("/sip", 100, .restricted), file("/link", 100, .symlink),
            dir("/App.app", .package), file("/App.app/inner", 100),
        ])
        let content = bytes("x", count: 100)
        let reader = FakeReader(["/orig": content, "/hard": content, "/clone": content, "/cloud": content,
                                 "/sip": content, "/link": content, "/App.app/inner": content])
        let report = await run(tree, reader)
        XCTAssertTrue(report.sets.isEmpty)
        XCTAssertEqual(report.skippedDataless, 1)
        XCTAssertFalse(reader.reads.contains("/cloud"), "dataless files are never read")
        XCTAssertTrue(reader.reads.isEmpty, "nothing eligible shares a size")
    }

    func testTwoMembersOfOneCloneFamilyAreNotDuplicates() async {
        let tree = makeTree([file("/photo.png", 100, .mayShareBlocks), file("/photo copy.png", 100, .cloneDuplicate)])
        let content = bytes("x", count: 100)
        let report = await run(tree, FakeReader(["/photo.png": content, "/photo copy.png": content]))
        XCTAssertTrue(report.sets.isEmpty)
    }

    func testRespectsMinimumSizeAndSortsByWaste() async {
        let tree = makeTree([file("/s1", 10), file("/s2", 10), file("/b1", 5000), file("/b2", 5000), file("/m1", 800), file("/m2", 800), file("/m3", 800)])
        var contents: [String: Data] = [:]
        for (path, size, tag) in [("/s1", 10, "a"), ("/s2", 10, "a"), ("/b1", 5000, "b"), ("/b2", 5000, "b"), ("/m1", 800, "m"), ("/m2", 800, "m"), ("/m3", 800, "m")] {
            contents[path] = bytes(tag, count: size)
        }
        let report = await run(tree, FakeReader(contents), minimum: 100)
        XCTAssertEqual(report.sets.map(\.size), [5000, 800])
        XCTAssertEqual(report.sets.map(\.wastedBytes), [5000, 1600].sorted(by: >).map { $0 })
    }

    func testReadsAreBoundedToOneMebibyte() async {
        let size = 3 << 20
        let tree = makeTree([file("/a", UInt64(size)), file("/b", UInt64(size))])
        let reader = FakeReader(["/a": bytes("x", count: size), "/b": bytes("x", count: size)])
        let report = await run(tree, reader)
        XCTAssertEqual(report.sets.count, 1)
        XCTAssertLessThanOrEqual(reader.maxLength, 1 << 20)
    }

    func testUnreadableFileIsSkippedNotFatal() async {
        let tree = makeTree([file("/a", 100), file("/b", 100), file("/c", 100)])
        let content = bytes("x", count: 100)
        let report = await run(tree, FakeReader(["/a": content, "/c": content]))
        XCTAssertEqual(report.sets.count, 1)
        XCTAssertEqual(report.sets[0].nodes.count, 2)
    }

    func testCancellationStopsReadingAndReportsNothing() async {
        let tree = makeTree([file("/a", 100), file("/b", 100), file("/c", 100), file("/d", 100)])
        let content = bytes("x", count: 100)
        let reader = FakeReader(["/a": content, "/b": content, "/c": content, "/d": content])
        let counter = Counter()
        reader.onRead = { counter.bump() }
        let report = await run(tree, reader, isCancelled: { counter.value >= 2 })
        XCTAssertTrue(report.sets.isEmpty)
        XCTAssertLessThanOrEqual(reader.reads.count, 4)
    }

    func testCancelledBeforeStartReadsNothing() async {
        let tree = makeTree([file("/a", 100), file("/b", 100)])
        let reader = FakeReader(["/a": bytes("x", count: 100), "/b": bytes("x", count: 100)])
        let report = await run(tree, reader, isCancelled: { true })
        XCTAssertTrue(report.sets.isEmpty)
        XCTAssertTrue(reader.reads.isEmpty)
    }
}

/// A thread-safe counter for cancellation tests.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    /// Adds one.
    func bump() { lock.lock(); count += 1; lock.unlock() }
    /// The current count.
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

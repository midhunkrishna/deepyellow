import DYCore
import XCTest
@testable import DYAdvisor

final class KindRefinerTests: XCTestCase {
    private let mp4 = Data([0, 0, 0, 0x18] + Array("ftypmp42".utf8) + [UInt8](repeating: 0, count: 40))
    private let png = Data([0x89] + Array("PNG\r\n".utf8) + [UInt8](repeating: 0, count: 40))

    private func refine(_ tree: FileTree, reader: FileReading, minimum: UInt64 = 1_000, lens: TreeLens? = nil) async -> KindRefinement? {
        await KindRefiner.refine(lens: lens ?? TreeLens(tree: tree), reader: reader, minimumSize: minimum, isCancelled: { false })
    }

    /// Unnamed files are read once, only up to the header length, and take the kind of their signature.
    func testSniffsUnnamedFilesAndReadsOnlyTheHeader() async throws {
        let tree = makeTree([file("/d/clip", 5_000), file("/d/pic.zzqq", 6_000), file("/d/tiny", 10)])
        let reader = FakeReader(["/d/clip": mp4, "/d/pic.zzqq": png, "/d/tiny": mp4])
        let outcome = await refine(tree, reader: reader)
        let result = try XCTUnwrap(outcome)
        let kinds = result.kinds.map { FileKind(rawValue: $0)! }
        XCTAssertEqual(kinds[Int(tree.find(path: "/d/clip")!)], .video)
        XCTAssertEqual(kinds[Int(tree.find(path: "/d/pic.zzqq")!)], .image)
        XCTAssertEqual(kinds[Int(tree.find(path: "/d/tiny")!)], .other, "below the minimum size, so never read")
        XCTAssertEqual(result.refinedFiles, 2)
        XCTAssertEqual(result.refinedBytes, 11_000)
        XCTAssertEqual(Set(reader.reads), ["/d/clip", "/d/pic.zzqq"])
        XCTAssertLessThanOrEqual(reader.maxLength, SignatureSniffer.headerLength)
    }

    /// Placeholders and protected files are never read, and files the name already explains aren't either.
    func testSkipsDatalessRestrictedAndNamedFiles() async throws {
        let tree = makeTree([file("/d/cloud", 5_000, .dataless), file("/d/sip", 5_000, .restricted),
                             file("/d/known.mp4", 5_000), file("/d/plain", 5_000)])
        let reader = FakeReader(["/d/cloud": mp4, "/d/sip": mp4, "/d/known.mp4": mp4, "/d/plain": mp4])
        _ = await refine(tree, reader: reader)
        XCTAssertEqual(reader.reads, ["/d/plain"])
    }

    /// An extension the table lacks but the type database knows is resolved without reading anything.
    func testTypeDatabaseResolvesWithoutReading() async throws {
        let tree = makeTree([file("/d/a.3gpp", 5_000), file("/d/b.svgz", 5_000)])
        let reader = FakeReader([:])
        let outcome = await refine(tree, reader: reader)
        let result = try XCTUnwrap(outcome)
        XCTAssertEqual(FileKind(rawValue: result.kinds[Int(tree.find(path: "/d/a.3gpp")!)]), .video)
        XCTAssertEqual(FileKind(rawValue: result.kinds[Int(tree.find(path: "/d/b.svgz")!)]), .image)
        XCTAssertTrue(reader.reads.isEmpty)
        XCTAssertEqual(result.refinedFiles, 2)
    }

    /// A large `.raw` that an older scan called an image becomes an archive.
    func testLargeRawIsFixed() async throws {
        let builder = TreeBuilder(rootPath: "/")
        let dir = builder.add(parent: 0, name: "d", record: NodeRecord(flags: .directory))
        _ = builder.add(parent: dir, name: "disk.raw", record: NodeRecord(allocated: 3_000_000_000, logical: 3_000_000_000, kind: .image))
        _ = builder.add(parent: dir, name: "shot.raw", record: NodeRecord(allocated: 20_000_000, logical: 20_000_000, kind: .image))
        let tree = builder.freeze()
        let outcome = await refine(tree, reader: FakeReader([:]))
        let result = try XCTUnwrap(outcome)
        XCTAssertEqual(FileKind(rawValue: result.kinds[Int(tree.find(path: "/d/disk.raw")!)]), .archive)
        XCTAssertEqual(FileKind(rawValue: result.kinds[Int(tree.find(path: "/d/shot.raw")!)]), .image)
    }

    /// Unreadable files and unrecognised content are left as `other`; cancelling returns nil.
    func testFailuresAndCancellation() async throws {
        let tree = makeTree([file("/d/gone", 5_000), file("/d/noise", 5_000)])
        let reader = FakeReader(["/d/noise": Data([0x9C, 0x01, 0xA7, 0xFF, 0x00, 0x80, 0x81, 0x82, 0x83])])
        let outcome = await refine(tree, reader: reader)
        let result = try XCTUnwrap(outcome)
        XCTAssertEqual(result.refinedFiles, 0)
        XCTAssertEqual(result.kinds, tree.columns.kind)
        let cancelled = await KindRefiner.refine(lens: TreeLens(tree: tree), reader: reader, minimumSize: 1, isCancelled: { true })
        XCTAssertNil(cancelled)
    }

    /// Files hidden by the lens are not read.
    func testHiddenFilesAreNotRead() async throws {
        let tree = makeTree([file("/d/clip", 5_000), file("/e/clip2", 5_000)])
        var hidden = [Bool](repeating: false, count: tree.count)
        hidden[Int(tree.find(path: "/e")!)] = true
        let reader = FakeReader(["/d/clip": mp4, "/e/clip2": mp4])
        _ = await refine(tree, reader: reader, lens: TreeLens(tree: tree, hidden: hidden))
        XCTAssertEqual(reader.reads, ["/d/clip"])
    }
}

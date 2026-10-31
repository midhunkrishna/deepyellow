import Darwin
import DYCore
import DYScan
import Foundation
import XCTest

final class ScannerTests: XCTestCase {
    private var fixture: Fixture!

    override func setUpWithError() throws { fixture = try Fixture() }
    override func tearDown() { fixture.tearDown() }

    func testTotalsMatchTheFilesystem() async throws {
        try fixture.writeFile("a/one.bin", count: 10_000)
        try fixture.writeFile("a/b/two.txt", count: 3)
        try fixture.writeFile("c/three.mov", count: 1_048_576)
        let (tree, _) = await runScan(root: fixture.root)
        let expected = fixture.allocated("a/one.bin") + fixture.allocated("a/b/two.txt") + fixture.allocated("c/three.mov")
        XCTAssertEqual(tree.allocated(0), expected)
        XCTAssertEqual(tree.logical(0), 10_000 + 3 + 1_048_576)
        XCTAssertEqual(tree.fileCount(0), 3)
        XCTAssertEqual(tree.name(0), fixture.root)
        let one = tree.node("a/one.bin")
        XCTAssertEqual(tree.logical(one), 10_000)
        XCTAssertEqual(tree.kind(tree.node("c/three.mov")), .video)
        XCTAssertEqual(tree.path(one), fixture.path("a/one.bin"))
        XCTAssertTrue(tree.flags(tree.node("a")).contains(.directory))
        XCTAssertGreaterThan(tree.modified(one), 1_600_000_000)
    }

    func testRecordedIdentityMatchesLstat() async throws {
        let file = try fixture.writeFile("dir/identity.bin", count: 12_345)
        var info = stat()
        XCTAssertEqual(lstat(file, &info), 0)
        var directoryInfo = stat()
        XCTAssertEqual(lstat(fixture.path("dir"), &directoryInfo), 0)
        let (tree, _) = await runScan(root: fixture.root)
        let node = tree.node("dir/identity.bin")
        XCTAssertEqual(tree.logical(node), UInt64(info.st_size))
        XCTAssertEqual(tree.modified(node), Int32(info.st_mtimespec.tv_sec))
        XCTAssertEqual(tree.inode(node), UInt64(info.st_ino))
        let directory = tree.node("dir")
        XCTAssertEqual(tree.inode(directory), UInt64(directoryInfo.st_ino))
        XCTAssertEqual(tree.modified(directory), Int32(directoryInfo.st_mtimespec.tv_sec))
        XCTAssertEqual(tree.columns.logical[Int(directory)], tree.logical(node), "directory logical is the subtree total")
    }

    func testResourceForkIsIncludedInLogicalSizeButNotInStSize() async throws {
        let file = try fixture.writeFile("forked.bin", count: 1000)
        let fork = [UInt8](repeating: 7, count: 5000)
        guard setxattr(file, "com.apple.ResourceFork", fork, fork.count, 0, 0) == 0 else { throw XCTSkip("no resource fork support") }
        var info = stat()
        XCTAssertEqual(lstat(file, &info), 0)
        let (tree, _) = await runScan(root: fixture.root)
        let recorded = tree.logical(tree.node("forked.bin"))
        XCTAssertEqual(recorded, UInt64(info.st_size) + 5000, "TOTALSIZE spans all forks, so logical exceeds st_size")
    }

    func testHardLinksAreCountedOnce() async throws {
        let original = try fixture.writeFile("x/a.bin", count: 1_048_576)
        try fixture.makeDirectory("y")
        XCTAssertEqual(link(original, fixture.path("y/b.bin")), 0)
        XCTAssertEqual(link(original, fixture.path("x/c.bin")), 0)
        let (tree, _) = await runScan(root: fixture.root)
        XCTAssertEqual(tree.allocated(0), fixture.allocated("x/a.bin"))
        XCTAssertEqual(tree.fileCount(0), 3)
        let duplicates = ["x/a.bin", "y/b.bin", "x/c.bin"].filter { tree.flags(tree.node($0)).contains(.hardlinkDuplicate) }
        XCTAssertEqual(duplicates.count, 2)
        XCTAssertEqual(tree.meta.hardlinkBytesSaved, 2 * fixture.allocated("x/a.bin"))
        for name in duplicates { XCTAssertEqual(tree.allocated(tree.node(name)), 0) }
    }

    func testFullClonesAreCountedOnceAndPartialClonesFlagged() async throws {
        let original = try fixture.writeFile("a.bin", count: 1_048_576)
        guard clonefile(original, fixture.path("clone.bin"), 0) == 0 else { throw XCTSkip("filesystem has no clonefile") }
        XCTAssertEqual(clonefile(original, fixture.path("edited.bin"), 0), 0)
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: fixture.path("edited.bin")))
        try handle.write(contentsOf: Data([1, 2, 3, 4, 5, 6, 7, 8]))
        try handle.close()
        let (tree, _) = await runScan(root: fixture.root)
        let a = tree.node("a.bin"), clone = tree.node("clone.bin"), edited = tree.node("edited.bin")
        let duplicates = [a, clone].filter { tree.flags($0).contains(.cloneDuplicate) }
        XCTAssertEqual(duplicates.count, 1)
        XCTAssertEqual(tree.allocated(duplicates[0]), 0)
        XCTAssertEqual(tree.meta.cloneBytesSaved, 1_048_576)
        XCTAssertFalse(tree.flags(edited).contains(.cloneDuplicate))
        XCTAssertTrue(tree.flags(edited).contains(.mayShareBlocks))
        XCTAssertTrue(tree.flags(a).contains(.mayShareBlocks))
        XCTAssertEqual(tree.allocated(0), 2 * 1_048_576)
    }

    func testSparseFilesUseAllocatedNotLogicalSize() async throws {
        let path = fixture.path("sparse.img")
        let descriptor = open(path, O_CREAT | O_WRONLY, 0o644)
        XCTAssertEqual(ftruncate(descriptor, 100 << 20), 0)
        close(descriptor)
        let (tree, _) = await runScan(root: fixture.root)
        let node = tree.node("sparse.img")
        XCTAssertEqual(tree.logical(node), 100 << 20)
        XCTAssertEqual(tree.allocated(node), 0)
        XCTAssertTrue(tree.flags(node).contains(.sparse))
    }

    func testSymlinksAreNeverFollowed() async throws {
        try fixture.writeFile("real/big.bin", count: 500_000)
        XCTAssertEqual(symlink(fixture.path("real"), fixture.path("link-to-dir")), 0)
        XCTAssertEqual(symlink(fixture.path("real/big.bin"), fixture.path("link-to-file")), 0)
        XCTAssertEqual(symlink(fixture.root, fixture.path("real/loop")), 0)
        let (tree, _) = await runScan(root: fixture.root)
        XCTAssertEqual(tree.fileCount(0), 4, "big.bin plus three symlink entries")
        XCTAssertTrue(tree.flags(tree.node("link-to-dir")).contains(.symlink))
        XCTAssertFalse(tree.flags(tree.node("link-to-dir")).contains(.directory))
        XCTAssertEqual(tree.children(tree.node("link-to-dir")).count, 0)
        XCTAssertLessThan(tree.allocated(0), 2 * 500_000 + 3 * 8192)
    }

    func testUnreadableDirectoryIsFlaggedNotZeroed() async throws {
        try fixture.writeFile("ok/file.bin", count: 100)
        try fixture.writeFile("secret/hidden.bin", count: 10)
        fixture.lock("secret")
        let (tree, _) = await runScan(root: fixture.root)
        let secret = tree.node("secret")
        XCTAssertTrue(tree.flags(secret).contains(.unreadable))
        XCTAssertFalse(tree.flags(tree.node("ok")).contains(.unreadable))
        XCTAssertEqual(tree.meta.unreadableDirectories, 1)
        XCTAssertFalse(tree.meta.limitedByPermissions, "EACCES is ordinary denial, not a missing Full Disk Access grant")
        XCTAssertEqual(tree.fileCount(0), 1)
    }

    func testDeepNestingBeyondPathMax() async throws {
        var descriptor = open(fixture.root, O_RDONLY | O_DIRECTORY)
        let component = String(repeating: "d", count: 40)
        let depth = 40
        for _ in 0..<depth {
            XCTAssertEqual(mkdirat(descriptor, component, 0o755), 0)
            let next = openat(descriptor, component, O_RDONLY | O_DIRECTORY)
            close(descriptor)
            descriptor = next
        }
        let file = openat(descriptor, "leaf.bin", O_CREAT | O_WRONLY, 0o644)
        XCTAssertGreaterThan(write(file, "hello", 5), 0)
        close(file)
        close(descriptor)
        let (tree, _) = await runScan(root: fixture.root)
        XCTAssertEqual(tree.fileCount(0), 1)
        XCTAssertEqual(tree.logical(0), 5)
        XCTAssertEqual(tree.depth(NodeID(tree.count - 1)), depth + 1)
        XCTAssertGreaterThan(tree.path(NodeID(tree.count - 1)).utf8.count, 1024)
    }

    func testAwkwardFileNamesRoundTripByteForByte() async throws {
        let names = ["new\nline.txt", "tab\there", " leading space", "trailing space ", "emoji-\u{1F600}.png",
                     "e\u{301}.txt", String(repeating: "n", count: 255), "quote\"and'apostrophe", "back\\slash"]
        for name in names { try fixture.writeFile(name, count: 10) }
        let (tree, _) = await runScan(root: fixture.root)
        XCTAssertEqual(tree.fileCount(0), UInt32(names.count))
        let stored = Set(tree.children(0).map { tree.withName($0) { Array($0) } })
        for name in names { XCTAssertTrue(stored.contains(Array(name.utf8)), "missing \(name.debugDescription)") }
    }

    func testInvalidUTF8NamesAreKeptWhenTheFilesystemAllowsThem() async throws {
        let bytes: [UInt8] = Array("bad".utf8) + [0xFF, 0xFE] + Array(".txt".utf8) + [0]
        let descriptor = bytes.withUnsafeBufferPointer { buffer in
            buffer.baseAddress!.withMemoryRebound(to: CChar.self, capacity: bytes.count) {
                openat(open(fixture.root, O_RDONLY | O_DIRECTORY), $0, O_CREAT | O_WRONLY, 0o644)
            }
        }
        guard descriptor >= 0 else { throw XCTSkip("filesystem rejects invalid UTF-8 names") }
        close(descriptor)
        let (tree, _) = await runScan(root: fixture.root)
        XCTAssertEqual(tree.fileCount(0), 1)
    }

    func testPackagesAreDetectedByExtension() async throws {
        try fixture.writeFile("Thing.app/Contents/MacOS/thing", count: 100)
        try fixture.writeFile("Lib.framework/Versions/A/lib", count: 100)
        try fixture.writeFile("plain.d/file", count: 100)
        try fixture.writeFile("Photos Library.photoslibrary/database/x", count: 100)
        let (tree, _) = await runScan(root: fixture.root)
        XCTAssertTrue(tree.flags(tree.node("Thing.app")).contains(.package))
        XCTAssertTrue(tree.flags(tree.node("Photos Library.photoslibrary")).contains(.package))
        XCTAssertFalse(tree.flags(tree.node("Lib.framework")).contains(.package))
        XCTAssertFalse(tree.flags(tree.node("plain.d")).contains(.package))
        XCTAssertEqual(tree.allocated(tree.node("Thing.app")), fixture.allocated("Thing.app/Contents/MacOS/thing"))
    }

    func testManyDirectoriesAcrossWorkersAreAllCounted() async throws {
        var expectedFiles = 0
        for outer in 0..<20 {
            for inner in 0..<20 {
                for file in 0..<5 {
                    try fixture.writeFile("o\(outer)/i\(inner)/f\(file).dat", count: file + 1)
                    expectedFiles += 1
                }
            }
        }
        for workers in [1, 4, 10] {
            let (tree, _) = await runScan(root: fixture.root, workers: workers)
            XCTAssertEqual(Int(tree.fileCount(0)), expectedFiles, "workers=\(workers)")
            XCTAssertEqual(tree.logical(0), 6000)
        }
    }

    func testStreamEndsWithFinishedAndProgressIsMonotonic() async throws {
        for index in 0..<200 { try fixture.writeFile("d\(index % 10)/f\(index).bin", count: 2000) }
        let (tree, events) = await runScan(root: fixture.root, interval: 0.001)
        guard case .finished = events.last else { return XCTFail("last event must be finished") }
        let finishedCount = events.filter { if case .finished = $0 { true } else { false } }.count
        XCTAssertEqual(finishedCount, 1)
        var lastFiles = 0
        for case .progress(let progress) in events {
            XCTAssertGreaterThanOrEqual(progress.files, lastFiles)
            lastFiles = progress.files
        }
        XCTAssertLessThanOrEqual(lastFiles, 200)
        XCTAssertEqual(tree.fileCount(0), 200)
        XCTAssertEqual(tree.meta.rootPath, fixture.root)
        XCTAssertGreaterThan(tree.meta.duration, 0)
    }

    func testCancelBeforeStartEndsWithAnUnexpandedTree() async throws {
        for outer in 0..<10 { for inner in 0..<10 { try fixture.writeFile("o\(outer)/i\(inner)/f.bin", count: 10) } }
        let scanner = DiskScanner(options: ScanOptions(root: fixture.root))
        scanner.cancel()
        var finished: FileTree?
        for await event in scanner.start() { if case .finished(let tree) = event { finished = tree } }
        let tree = try XCTUnwrap(finished)
        XCTAssertEqual(tree.name(0), fixture.root)
        XCTAssertEqual(tree.fileCount(0), 0)
        XCTAssertTrue(tree.flags(0).contains(.unreadable), "an unscanned directory is unknown, not empty")
        XCTAssertTrue(scanner.wasCancelled)
    }

    func testCancelMidScanStillEndsWithFinished() async throws {
        for outer in 0..<30 { for inner in 0..<30 { try fixture.writeFile("o\(outer)/i\(inner)/f.bin", count: 10) } }
        var options = ScanOptions(root: fixture.root)
        options.snapshotInterval = 0
        let scanner = DiskScanner(options: options)
        var finished: FileTree?
        var sawFinished = 0
        for await event in scanner.start() {
            scanner.cancel()
            if case .finished(let tree) = event { finished = tree; sawFinished += 1 }
        }
        XCTAssertEqual(sawFinished, 1)
        XCTAssertLessThanOrEqual(try XCTUnwrap(finished).fileCount(0), 900)
    }

    func testSnapshotsAreBoundedAndConsistent() async throws {
        for index in 0..<3000 { try fixture.writeFile("d\(index % 50)/f\(index).bin", count: 1) }
        var options = ScanOptions(root: fixture.root)
        options.snapshotInterval = 0
        options.snapshotMaxNodes = 100
        var snapshots = 0
        for await event in DiskScanner(options: options).start() {
            if case .snapshot(let tree) = event {
                snapshots += 1
                XCTAssertLessThan(tree.count, 3300)
            }
        }
        XCTAssertGreaterThan(snapshots, 0)
    }

    func testScanningARootThatDoesNotExistStillFinishes() async {
        let (tree, _) = await runScan(root: fixture.path("missing"))
        XCTAssertTrue(tree.flags(0).contains(.unreadable))
        XCTAssertEqual(tree.count, 1)
    }

    func testRealHomeScanReportsConsistentTotals() async throws {
        let documents = NSHomeDirectory() + "/Library/Preferences"
        guard FileManager.default.isReadableFile(atPath: documents) else { throw XCTSkip("no preferences folder") }
        let (tree, _) = await runScan(root: documents)
        var summed: UInt64 = 0
        for node in 0..<NodeID(tree.count) where !tree.isDirectory(node) { summed += tree.allocated(node) }
        XCTAssertEqual(summed, tree.allocated(0))
        var files: UInt32 = 0
        for node in 0..<NodeID(tree.count) where !tree.isDirectory(node) { files += 1 }
        XCTAssertEqual(files, tree.fileCount(0))
    }

    func testWholeDiskScanSkipsPlumbingAndDoesNotDoubleCountData() async throws {
        let (tree, _) = await runScan(root: "/")
        XCTAssertEqual(tree.name(0), "/")
        XCTAssertNotNil(tree.find(path: "/Users"), "Data volume content must appear under its familiar path")
        XCTAssertNotNil(tree.find(path: "/System/Library"))
        XCTAssertNil(tree.find(path: "/System/Volumes"))
        XCTAssertNil(tree.find(path: "/System/Volumes/Data"))
        let users = try XCTUnwrap(tree.find(path: "/Users"))
        XCTAssertFalse(tree.flags(users).contains(.mountBoundary))
        var seen = Set<String>()
        for child in tree.children(0) { XCTAssertTrue(seen.insert(tree.name(child)).inserted, "duplicate top-level name \(tree.name(child))") }
        let volume = VolumeInfo.mounted().first { $0.path == "/" }
        if let volume { XCTAssertLessThan(tree.allocated(0), volume.total) }
    }
}

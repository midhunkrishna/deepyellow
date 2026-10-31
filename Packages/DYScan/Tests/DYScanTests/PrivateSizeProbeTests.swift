import Darwin
import DYCore
import DYScan
import Foundation
import XCTest

final class PrivateSizeProbeTests: XCTestCase {
    /// A folder's measured bytes equal what the scanner records as private size for it.
    func testMatchesScannerPrivateBytes() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        try fixture.writeFile("top/a.bin", count: 300_000)
        try fixture.writeFile("top/inner/deeper/b.bin", count: 123_456)
        try fixture.writeFile("top/inner/c.bin", count: 10)
        var options = ScanOptions(root: fixture.root)
        options.exactReclaimable = true
        var tree: FileTree?
        for await event in DiskScanner(options: options).start() { if case .finished(let done) = event { tree = done } }
        let top = try XCTUnwrap(tree?.find(path: fixture.path("top")))
        let measured = try XCTUnwrap(PrivateSizeProbe().privateBytes(path: fixture.path("top")))
        XCTAssertEqual(measured, tree?.privateBytes(top))
        XCTAssertGreaterThan(measured, 400_000)
    }

    /// A single file can be measured directly.
    func testSingleFile() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let path = try fixture.writeFile("one.bin", count: 50_000)
        let measured = try XCTUnwrap(PrivateSizeProbe().privateBytes(path: path))
        XCTAssertGreaterThanOrEqual(measured, 50_000)
    }

    /// A path that doesn't exist gives nil, not zero.
    func testMissingPathIsNil() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        XCTAssertNil(PrivateSizeProbe().privateBytes(path: fixture.path("absent")))
    }

    /// A hard link counts only when all links are inside the measured folder.
    func testHardLinkLeavingTheFolderFreesNothing() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let original = try fixture.writeFile("outside/big.bin", count: 200_000)
        try fixture.makeDirectory("inside")
        XCTAssertEqual(link(original, fixture.path("inside/link.bin")), 0)
        XCTAssertEqual(PrivateSizeProbe().privateBytes(path: fixture.path("inside")), 0)
        XCTAssertEqual(link(original, fixture.path("inside/link2.bin")), 0)
        let both = try fixture.writeFile("both/x.bin", count: 100_000)
        try fixture.makeDirectory("both2")
        XCTAssertEqual(link(both, fixture.path("both/y.bin")), 0)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(PrivateSizeProbe().privateBytes(path: fixture.path("both"))), 100_000)
    }

    /// An unreadable folder makes the whole measurement nil.
    func testUnreadableFolderIsNil() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        try fixture.writeFile("root/locked/a.bin", count: 1_000)
        fixture.lock("root/locked")
        XCTAssertNil(PrivateSizeProbe().privateBytes(path: fixture.path("root")))
    }
}

final class ScannerKindTests: XCTestCase {
    /// Docker's disk image is an archive even when tiny, and the new table entries reach the tree.
    func testScannerAppliesNameAndSizeKinds() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        try fixture.writeFile("Docker.raw", count: 10)
        try fixture.writeFile("model.gguf", count: 10)
        var tree: FileTree?
        for await event in DiskScanner(options: ScanOptions(root: fixture.root)).start() { if case .finished(let done) = event { tree = done } }
        XCTAssertEqual(tree?.kind(try XCTUnwrap(tree?.find(path: fixture.path("Docker.raw")))), .archive)
        XCTAssertEqual(tree?.kind(try XCTUnwrap(tree?.find(path: fixture.path("model.gguf")))), .code)
    }
}

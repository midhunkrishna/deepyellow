import Foundation
import XCTest
@testable import DYCore

final class KindResolutionTests: XCTestCase {
    /// `Docker.raw` and any `.raw` of 1 GB or more is a disk image, while a small `.raw` stays a camera file.
    func testRawIsArchiveWhenLargeOrDocker() {
        XCTAssertEqual(FileKindClassifier.classify("Docker.raw"), .archive)
        XCTAssertEqual(FileKindClassifier.classify("vm.raw", size: 2_000_000_000), .archive)
        XCTAssertEqual(FileKindClassifier.classify("IMG_1.raw", size: 30_000_000), .image)
        XCTAssertEqual(FileKindClassifier.classify("IMG_1.RAW"), .image)
    }

    /// The measured extensions that used to land in `other`.
    func testMeasuredExtensionsAreClassified() {
        for name in ["a.jsonl", "m.gguf", "m.safetensors", "w.weights", "x.dat", "x.pack", "x.litertlm"] {
            XCTAssertEqual(FileKindClassifier.classify(name), .code, name)
        }
        XCTAssertEqual(FileKindClassifier.classify("disk.img"), .archive)
    }

    /// The type system answers for types macOS itself declares and says nothing for made-up ones.
    /// Uses only system-declared types: `mkv`, for one, resolves only when an installed app registers it.
    func testTypeResolver() {
        XCTAssertEqual(TypeResolver.kind(forExtension: "MOV"), .video)
        XCTAssertEqual(TypeResolver.kind(forExtension: "heic"), .image)
        XCTAssertNil(TypeResolver.kind(forExtension: "xyzzyq1"))
        XCTAssertNil(TypeResolver.kind(forExtension: ""))
        XCTAssertEqual(TypeResolver.kind(forExtension: "mov"), TypeResolver.kind(forExtension: "mov"))
    }

    /// Formats that macOS doesn't declare still classify on a clean machine, because the table lists them.
    func testTableCoversTypesTheSystemMayNotDeclare() {
        XCTAssertEqual(FileKindClassifier.classify("film.mkv"), .video)
    }

    private func header(_ bytes: [UInt8], padTo length: Int = 64) -> Data {
        Data(bytes + [UInt8](repeating: 0, count: max(0, length - bytes.count)))
    }

    /// Common signatures map to their kind.
    func testSignatures() {
        let sniff = SignatureSniffer.kind(header:)
        XCTAssertEqual(sniff(header([0, 0, 0, 0x18] + Array("ftypmp42".utf8))), .video)
        XCTAssertEqual(sniff(header([0, 0, 0, 0x14] + Array("ftypheic".utf8))), .image)
        XCTAssertEqual(sniff(header([0, 0, 0, 0x14] + Array("ftypM4A ".utf8))), .audio)
        XCTAssertEqual(sniff(header([0x1A, 0x45, 0xDF, 0xA3])), .video)
        XCTAssertEqual(sniff(header([0xFF, 0xD8, 0xFF, 0xE0])), .image)
        XCTAssertEqual(sniff(header([0x89] + Array("PNG\r\n".utf8))), .image)
        XCTAssertEqual(sniff(header(Array("RIFF".utf8) + [0, 0, 0, 0] + Array("WAVEfmt ".utf8))), .audio)
        XCTAssertEqual(sniff(header(Array("RIFF".utf8) + [0, 0, 0, 0] + Array("WEBPVP8 ".utf8))), .image)
        XCTAssertEqual(sniff(header(Array("RIFF".utf8) + [0, 0, 0, 0] + Array("AVI LIST".utf8))), .video)
        XCTAssertEqual(sniff(header(Array("ID3".utf8) + [4, 0])), .audio)
        XCTAssertEqual(sniff(header(Array("fLaC".utf8))), .audio)
        XCTAssertEqual(sniff(header(Array("OggS".utf8))), .audio)
        XCTAssertEqual(sniff(header(Array("%PDF-1.7".utf8))), .document)
        XCTAssertEqual(sniff(header([0x50, 0x4B, 3, 4])), .archive)
        XCTAssertEqual(sniff(header([0x1F, 0x8B, 8])), .archive)
        XCTAssertEqual(sniff(header([0xFD, 0x37, 0x7A, 0x58, 0x5A, 0])), .archive)
        XCTAssertEqual(sniff(header(Array("SQLite format 3".utf8) + [0])), .code)
        XCTAssertEqual(sniff(header(Array("GGUF".utf8) + [3, 0, 0, 0])), .code)
        XCTAssertEqual(sniff(header([0xCF, 0xFA, 0xED, 0xFE, 7, 0, 0, 1])), .application)
        XCTAssertEqual(sniff(header([0xCA, 0xFE, 0xBA, 0xBE, 0, 0, 0, 2])), .application)
        XCTAssertEqual(sniff(header([0x7F] + Array("ELF".utf8))), .application)
    }

    /// A tar header, a GPT header and an APFS container are recognised past the first bytes.
    func testDeepSignatures() {
        var tar = [UInt8](repeating: 0, count: SignatureSniffer.headerLength)
        tar.replaceSubrange(257..<262, with: Array("ustar".utf8))
        XCTAssertEqual(SignatureSniffer.kind(header: Data(tar)), .archive)
        var gpt = [UInt8](repeating: 0, count: SignatureSniffer.headerLength)
        gpt.replaceSubrange(512..<520, with: Array("EFI PART".utf8))
        XCTAssertEqual(SignatureSniffer.kind(header: Data(gpt)), .archive)
        var apfs = [UInt8](repeating: 0, count: SignatureSniffer.headerLength)
        apfs.replaceSubrange(32..<36, with: Array("NXSB".utf8))
        XCTAssertEqual(SignatureSniffer.kind(header: Data(apfs)), .archive)
    }

    /// A Java class file shares the fat Mach-O magic but must not be called an application.
    func testJavaClassIsNotMachO() {
        XCTAssertEqual(SignatureSniffer.kind(header: header([0xCA, 0xFE, 0xBA, 0xBE, 0, 0, 0, 0x34])), .code)
    }

    /// Unknown binary data and an empty header give no answer, and plain text is a document.
    func testUnknownAndText() {
        XCTAssertNil(SignatureSniffer.kind(header: Data()))
        XCTAssertNil(SignatureSniffer.kind(header: header([0x9C, 0x01, 0x02, 0xA7, 0x00, 0xFF], padTo: 128)))
        XCTAssertEqual(SignatureSniffer.kind(header: Data("just some notes about my day, nothing else here".utf8)), .document)
        XCTAssertEqual(SignatureSniffer.kind(header: Data("#!/bin/sh\necho hi\n".utf8)), .code)
        XCTAssertEqual(SignatureSniffer.kind(header: Data("{\"a\": 1}".utf8)), .code)
    }

    /// Replacing kinds shares every other column and keeps ids.
    func testReplacingKinds() {
        let tree = SyntheticTree.make(scale: 0.05)
        var kinds = tree.columns.kind
        kinds[1] = FileKind.archive.rawValue
        let replaced = tree.replacingKinds(kinds)
        XCTAssertEqual(replaced.count, tree.count)
        XCTAssertEqual(replaced.kind(1), .archive)
        XCTAssertEqual(replaced.columns.allocated, tree.columns.allocated)
        XCTAssertEqual(replaced.name(1), tree.name(1))
        XCTAssertTrue(tree.replacingKinds([1, 2]) === tree, "a column of the wrong length changes nothing")
    }
}

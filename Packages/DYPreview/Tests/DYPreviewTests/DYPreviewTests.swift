import CoreGraphics
import DYCore
import Foundation
import XCTest
@testable import DYPreview

/// Counts loader calls from any thread.
final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var names: [String] = []
    func add(_ name: String) { lock.lock(); names.append(name); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return names }
}

func tempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dypreview-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

func item(_ name: String, _ kind: FileKind, in dir: URL, dataless: Bool = false, directory: Bool = false) -> PreviewItem {
    PreviewItem(url: dir.appendingPathComponent(name), name: name, size: 10, kind: kind, isDirectory: directory, isDataless: dataless)
}

func countingLoaders(_ calls: Calls) -> PreviewLoaders {
    PreviewLoaders(
        image: { _, _ in calls.add("image"); return nil },
        isPlayable: { _ in calls.add("playable"); return true },
        pdfPageCount: { _ in calls.add("pdf"); return 1 },
        text: { _ in calls.add("text"); return "hi" },
        waveform: { _ in calls.add("wave"); return Waveform(peaks: [1], duration: 1) })
}

final class RoutingTests: XCTestCase {
    func testRoutesByKind() throws {
        let d = try tempDir()
        XCTAssertEqual(PreviewRoute.route(for: item("a.mov", .video, in: d)), .video)
        XCTAssertEqual(PreviewRoute.route(for: item("a.png", .image, in: d)), .image)
        XCTAssertEqual(PreviewRoute.route(for: item("a.wav", .audio, in: d)), .audio)
        XCTAssertEqual(PreviewRoute.route(for: item("a.pdf", .document, in: d)), .pdf)
        XCTAssertEqual(PreviewRoute.route(for: item("a.txt", .document, in: d)), .text)
        XCTAssertEqual(PreviewRoute.route(for: item("a.swift", .code, in: d)), .text)
        XCTAssertEqual(PreviewRoute.route(for: item("a.docx", .document, in: d)), .quickLook)
        XCTAssertEqual(PreviewRoute.route(for: item("a.zip", .archive, in: d)), .quickLook)
        XCTAssertEqual(PreviewRoute.route(for: item("d", .other, in: d, directory: true)), .directory)
    }

    func testDatalessRoutesFirstForEveryKind() throws {
        let d = try tempDir()
        for kind in FileKind.allCases {
            XCTAssertEqual(PreviewRoute.route(for: item("x.pdf", kind, in: d, dataless: true)), .dataless)
        }
    }
}

final class ProviderTests: XCTestCase {
    func testDatalessInvokesNoLoader() async throws {
        let calls = Calls()
        let provider = PreviewContentProvider(loaders: countingLoaders(calls))
        let d = try tempDir()
        for kind in FileKind.allCases {
            let it = item("x", kind, in: d, dataless: true)
            let content = await provider.content(for: it)
            guard case .dataless = content else { return XCTFail("expected dataless for \(kind)") }
            await provider.prepare([it])
            let full = await provider.fullImage(for: it)
            XCTAssertNil(full)
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(calls.all, [])
    }

    func testPrepareCachesAndIsBounded() async throws {
        let calls = Calls()
        let provider = PreviewContentProvider(loaders: countingLoaders(calls), cacheSize: 4, prepareLimit: 2)
        let d = try tempDir()
        let items = (0..<6).map { item("f\($0).txt", .document, in: d) }
        await provider.prepare(items)
        try await Task.sleep(nanoseconds: 200_000_000)
        let cached = await provider.cachedCount
        XCTAssertEqual(cached, 2, "only prepareLimit items are preloaded")
        let before = calls.all.count
        _ = await provider.content(for: items[0])
        XCTAssertEqual(calls.all.count, before, "cached item does not reload")
        for it in items { _ = await provider.content(for: it) }
        let after = await provider.cachedCount
        XCTAssertLessThanOrEqual(after, 4)
    }

    func testFailedLoadFallsBackToQuickLook() async throws {
        let provider = PreviewContentProvider(loaders: PreviewLoaders(
            image: { _, _ in nil }, isPlayable: { _ in false }, pdfPageCount: { _ in 0 },
            text: { _ in nil }, waveform: { _ in nil }))
        let d = try tempDir()
        for (name, kind) in [("a.png", FileKind.image), ("a.mov", .video), ("a.pdf", .document), ("a.txt", .document), ("a.wav", .audio)] {
            let content = await provider.content(for: item(name, kind, in: d))
            guard case .quickLook = content else { return XCTFail("\(name) should fall back") }
        }
    }

    func testCorruptFilesFallBackWithLiveLoaders() async throws {
        let d = try tempDir()
        defer { try? FileManager.default.removeItem(at: d) }
        let junk = Data((0..<2000).map { UInt8($0 % 251) })
        let provider = PreviewContentProvider()
        for (name, kind) in [("bad.png", FileKind.image), ("bad.mov", .video), ("bad.pdf", .document), ("bad.txt", .document), ("bad.wav", .audio)] {
            let it = item(name, kind, in: d)
            try junk.write(to: it.url)
            let content = await provider.content(for: it)
            guard case .quickLook = content else { return XCTFail("\(name) should fall back") }
        }
    }

    func testLiveLoadersOnGeneratedFixtures() async throws {
        let d = try tempDir()
        defer { try? FileManager.default.removeItem(at: d) }
        try PreviewFixtures.image(at: d.appendingPathComponent("a.png"))
        try PreviewFixtures.pdf(at: d.appendingPathComponent("a.pdf"))
        try PreviewFixtures.text(at: d.appendingPathComponent("a.txt"))
        try await PreviewFixtures.video(at: d.appendingPathComponent("a.mov"))
        try PreviewFixtures.audio(at: d.appendingPathComponent("a.wav"))
        let provider = PreviewContentProvider(screenSide: 100)
        if case .image(let img) = await provider.content(for: item("a.png", .image, in: d)) {
            XCTAssertLessThanOrEqual(max(img.width, img.height), 100, "decodes at screen size, not full size")
        } else { XCTFail("image") }
        if case .pdf = await provider.content(for: item("a.pdf", .document, in: d)) {} else { XCTFail("pdf") }
        if case .text = await provider.content(for: item("a.txt", .document, in: d)) {} else { XCTFail("text") }
        if case .video = await provider.content(for: item("a.mov", .video, in: d)) {} else { XCTFail("video") }
        if case .audio = await provider.content(for: item("a.wav", .audio, in: d)) {} else { XCTFail("audio") }
        let full = await provider.fullImage(for: item("a.png", .image, in: d))
        XCTAssertEqual(full?.width, 640)
    }
}

final class CacheTests: XCTestCase {
    func testLRUEvictsOldestAndRespectsRecency() {
        var cache = LRUCache<Int, String>(maxCost: 3)
        cache.set(1, "a"); cache.set(2, "b"); cache.set(3, "c")
        _ = cache.get(1)
        cache.set(4, "d")
        XCTAssertFalse(cache.contains(2))
        XCTAssertTrue(cache.contains(1))
        XCTAssertEqual(cache.count, 3)
    }

    func testThumbnailCacheEvictsByBytes() async throws {
        let calls = Calls()
        let cache = ThumbnailCache(maxBytes: 2 * 64 * 64 * 4) { url, side in
            calls.add(url.lastPathComponent)
            let ctx = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 64 * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            return ctx.makeImage()
        }
        let d = URL(fileURLWithPath: "/nonexistent-dypreview")
        for n in ["a", "b", "c"] { _ = await cache.image(for: d.appendingPathComponent(n), side: 64) }
        let count = await cache.count
        XCTAssertEqual(count, 2)
        _ = await cache.image(for: d.appendingPathComponent("c"), side: 64)
        XCTAssertEqual(calls.all, ["a", "b", "c"], "hit does not decode again")
        _ = await cache.image(for: d.appendingPathComponent("a"), side: 64)
        XCTAssertEqual(calls.all.count, 4, "evicted entry decodes again")
    }
}

final class ExtractionTests: XCTestCase {
    func testWaveformFromGeneratedAudio() async throws {
        let d = try tempDir()
        defer { try? FileManager.default.removeItem(at: d) }
        let url = d.appendingPathComponent("t.wav")
        try PreviewFixtures.audio(at: url, seconds: 2)
        let wave = await WaveformExtractor.extract(from: url, buckets: 20)
        XCTAssertEqual(wave?.peaks.count, 20)
        XCTAssertEqual(wave?.duration ?? 0, 2, accuracy: 0.1)
        XCTAssertEqual(wave?.peaks.last ?? 0, 1, accuracy: 0.001)
        XCTAssertLessThan(wave?.peaks.first ?? 1, 0.3, "amplitude ramps up")
    }

    func testTextExtractionTruncatesAndRejectsBinary() throws {
        let d = try tempDir()
        defer { try? FileManager.default.removeItem(at: d) }
        let big = d.appendingPathComponent("big.txt")
        try PreviewFixtures.text(at: big, bytes: 600_000)
        XCTAssertLessThanOrEqual(TextExtractor.head(of: big)?.utf8.count ?? .max, 256 * 1024)
        XCTAssertGreaterThan(TextExtractor.head(of: big)?.utf8.count ?? 0, 200_000)
        let bin = d.appendingPathComponent("b.bin")
        try Data([1, 2, 0, 3]).write(to: bin)
        XCTAssertNil(TextExtractor.head(of: bin))
        XCTAssertNil(TextExtractor.head(of: d.appendingPathComponent("missing")))
        let utf = d.appendingPathComponent("u.txt")
        try "héllo wörld ✓".write(to: utf, atomically: true, encoding: .utf8)
        XCTAssertEqual(TextExtractor.head(of: utf, limit: 100), "héllo wörld ✓")
        XCTAssertNotNil(TextExtractor.head(of: utf, limit: 15), "cut-off multibyte tail is trimmed")
    }

    func testDirectoryLayoutTilesBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        let rects = DirectoryLayout.rects(weights: [600, 300, 100, 50], in: bounds)
        XCTAssertEqual(rects.map { $0.width * $0.height }.reduce(0, +), bounds.width * bounds.height, accuracy: 0.01)
        XCTAssertEqual(rects[0].width * rects[0].height / (bounds.width * bounds.height), 600.0 / 1050, accuracy: 0.001)
    }
}

@MainActor
final class ControllerTests: XCTestCase {
    func testItemChangeReleasesPlayer() async throws {
        let d = try tempDir()
        defer { try? FileManager.default.removeItem(at: d) }
        try await PreviewFixtures.video(at: d.appendingPathComponent("a.mov"))
        let controller = PreviewController()
        await controller.show(item("a.mov", .video, in: d))
        XCTAssertNotNil(controller.player)
        controller.togglePlay()
        XCTAssertTrue(controller.isPlaying)
        await controller.show(item("x.png", .image, in: d, dataless: true))
        XCTAssertNil(controller.player)
        XCTAssertFalse(controller.isPlaying)
        XCTAssertTrue(controller.filmstrip.frames.isEmpty)
    }

    func testZoomIsClampedAndDatalessNeverDecodes() async throws {
        let calls = Calls()
        let controller = PreviewController(provider: PreviewContentProvider(loaders: countingLoaders(calls)))
        let d = try tempDir()
        await controller.show(item("a.png", .image, in: d, dataless: true))
        controller.zoom(by: 100)
        XCTAssertEqual(controller.zoomScale, 8)
        controller.zoom(by: 0.001)
        XCTAssertEqual(controller.zoomScale, 1)
        controller.requestDownloadNoop()
        XCTAssertEqual(calls.all, [])
    }
}

extension PreviewController {
    /// Test helper: the download handler is replaceable and does nothing here.
    func requestDownloadNoop() { downloadHandler = { _ in } ; requestDownload() }
}

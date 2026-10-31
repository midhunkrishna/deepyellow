import AppKit
import DYCore
import DYPreview
import DYWorkspace
import SwiftUI
import XCTest
@testable import DYLenses

/// Renders each lens from the demo workspace to a PNG, so the look can be inspected. Demo mode only: the Trash is in memory.
@MainActor
final class RenderTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("dy-lenses-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: directory) }

    /// A workspace on the demo disk, settled.
    private func demoWorkspace() async -> Workspace {
        let workspace = Workspace(environment: .demo(dataDirectory: directory))
        workspace.open(.demo)
        await workspace.settle()
        return workspace
    }

    /// Where PNGs go: `DY_RENDER_DIR` when set, else a temp folder that is removed with the test.
    private var outputDirectory: URL {
        ProcessInfo.processInfo.environment["DY_RENDER_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? directory
    }

    /// Draws a view offscreen at `size` and writes `name.png`. Returns the number of distinct pixel values sampled.
    @discardableResult
    private func render<V: View>(_ view: V, size: CGSize, name: String) async throws -> Int {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let root = view.frame(width: size.width, height: size.height).preferredColorScheme(.dark)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        for _ in 0..<4 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(nanoseconds: 150_000_000)
        }
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: outputDirectory.appendingPathComponent("\(name).png"))
        var seen = Set<UInt32>()
        for x in stride(from: 0, to: rep.pixelsWide, by: 7) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 7) { seen.insert(UInt32(truncatingIfNeeded: rep.colorAt(x: x, y: y)?.hashValue ?? 0)) }
        }
        return seen.count
    }

    func testThingsRenders() async throws {
        let workspace = await demoWorkspace()
        workspace.setLens(.things)
        await workspace.settle()
        XCTAssertNotNil(workspace.things)
        if let first = workspace.things?.items.first, case .node(let node) = first.content { workspace.click(node, additive: false) }
        let distinct = try await render(ThingsLens(workspace: workspace), size: CGSize(width: 1180, height: 700), name: "things")
        XCTAssertGreaterThan(distinct, 8)
    }

    func testSlidingDetailChangesTheCut() async throws {
        let workspace = await demoWorkspace()
        workspace.setLens(.things)
        await workspace.settle()
        let coarse = workspace.things?.items.count ?? 0
        workspace.setThingsItemTarget(ThingsDetail.target(forPosition: 0.9))
        await workspace.settle()
        XCTAssertGreaterThan(workspace.things?.items.count ?? 0, coarse)
        XCTAssertEqual(workspace.things?.items.reduce(0) { $0 + $1.value }, workspace.things?.total)
    }

    func testSpectrumRendersAndColumnWritesQuery() async throws {
        let workspace = await demoWorkspace()
        workspace.setLens(.spectrum)
        await workspace.settle()
        let result = try XCTUnwrap(workspace.spectrum)
        let bin = try XCTUnwrap(result.bins.first { $0.lower >= 1_000_000 })
        workspace.setQuery(SpectrumModel.query(workspace.queryText, selecting: bin))
        XCTAssertTrue(workspace.queryText.contains("size>"))
        workspace.setQuery("")
        await workspace.settle()
        let distinct = try await render(SpectrumLens(workspace: workspace), size: CGSize(width: 1180, height: 760), name: "spectrum")
        XCTAssertGreaterThan(distinct, 8)
        try await render(SpectrumLens(workspace: workspace), size: CGSize(width: 1600, height: 760), name: "spectrum-1600")
        try await render(SpectrumLens(workspace: workspace), size: CGSize(width: 1100, height: 1000), name: "spectrum-1100")
    }

    func testFoldersTakeTheirDominantKind() async throws {
        let workspace = await demoWorkspace()
        let music = try XCTUnwrap(workspace.tree?.find(path: "/Users/demo/Music/Lossless"))
        XCTAssertEqual(NodeFacts.displayKind(workspace, music), .audio)
    }

    func testBrowseRenders() async throws {
        let workspace = await demoWorkspace()
        workspace.setLens(.browse)
        workspace.select(paths: ["/Users/demo/Movies"])
        await workspace.settle()
        let distinct = try await render(BrowseLens(workspace: workspace), size: CGSize(width: 1180, height: 640), name: "browse")
        XCTAssertGreaterThan(distinct, 8)
    }

    func testReclaimRendersBeforeAndAfterDuplicateSearch() async throws {
        let workspace = await demoWorkspace()
        workspace.setLens(.reclaim)
        await workspace.settle()
        XCTAssertNotNil(workspace.reclaimReport)
        XCTAssertTrue(workspace.resolved?.effective.allSatisfy { $0 == 0 } ?? true, "nothing is pre-marked")
        try await render(ReclaimLens(workspace: workspace), size: CGSize(width: 1180, height: 2500), name: "reclaim-before")
        try await render(ReclaimLens(workspace: workspace), size: CGSize(width: 1600, height: 1900), name: "reclaim-1600")
        try await render(ReclaimLens(workspace: workspace), size: CGSize(width: 1180, height: 900), name: "reclaim-1180")
        try await render(ReclaimLens(workspace: workspace), size: CGSize(width: 1100, height: 2500), name: "reclaim-1100")
        workspace.findDuplicates()
        await workspace.settle()
        XCTAssertNotNil(workspace.worklists.first { $0.kind == .duplicates })
        let distinct = try await render(ReclaimLens(workspace: workspace), size: CGSize(width: 1180, height: 2500), name: "reclaim")
        XCTAssertGreaterThan(distinct, 8)
    }

    func testReclaimNarrowsToTheQuery() async throws {
        let workspace = await demoWorkspace()
        workspace.setLens(.reclaim)
        await workspace.settle()
        let report = try XCTUnwrap(workspace.reclaimReport)
        let open = ReclaimModel.scope(report: report, worklists: workspace.worklists, lens: workspace.lens, baseLens: workspace.baseLens)
        XCTAssertFalse(open.isNarrowed)
        XCTAssertEqual(open.groups.map(\.bytes), ReclaimModel.groups(report).map(\.bytes), "no filter leaves the report unchanged")

        workspace.setQuery("kind:video")
        await workspace.settle()
        let scope = ReclaimModel.scope(report: report, worklists: workspace.worklists, lens: workspace.lens, baseLens: workspace.baseLens)
        XCTAssertTrue(scope.isNarrowed)
        let lens = try XCTUnwrap(workspace.lens)
        for family in scope.groups.flatMap(\.families) {
            XCTAssertTrue(family.nodes.allSatisfy { lens.included[Int($0)] && lens.size[Int($0)] > 0 })
            XCTAssertLessThanOrEqual(family.bytes, scope.fullBytes[family.id] ?? 0)
        }
        XCTAssertLessThanOrEqual(ReclaimModel.headline(scope.groups).reclaimable, ReclaimModel.headline(open.groups).reclaimable)
        XCTAssertLessThanOrEqual(scope.totalBytes, open.totalBytes)
        try await render(ReclaimLens(workspace: workspace), size: CGSize(width: 1180, height: 1400), name: "reclaim-narrowed")

        workspace.setQuery("size>100tb")
        await workspace.settle()
        let empty = ReclaimModel.scope(report: report, worklists: workspace.worklists, lens: workspace.lens, baseLens: workspace.baseLens)
        XCTAssertTrue(empty.isEmpty)
        try await render(ReclaimLens(workspace: workspace), size: CGSize(width: 1180, height: 500), name: "reclaim-empty")
    }

    func testReviewRendersAndAdvances() async throws {
        let workspace = await demoWorkspace()
        let list = try XCTUnwrap(workspace.worklists.first { $0.kind == .largestUndecided })
        XCTAssertTrue(workspace.startReview(worklist: list))
        workspace.reviewVerdict(.keep)
        workspace.reviewVerdict(.remove)
        workspace.reviewVerdict(.later)
        XCTAssertEqual(workspace.review?.index, 3)
        let controller = PreviewController()
        let distinct = try await render(ReviewMode(workspace: workspace, controller: controller), size: CGSize(width: 1280, height: 760), name: "review")
        XCTAssertGreaterThan(distinct, 8)
        workspace.reviewGo(to: workspace.review?.items.count ?? 0)
        try await render(ReviewMode(workspace: workspace, controller: controller), size: CGSize(width: 1280, height: 520), name: "review-finished")
        XCTAssertTrue(workspace.review?.isFinished ?? false)
    }
}

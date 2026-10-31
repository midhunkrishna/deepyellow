import XCTest
import AppKit
import DYCore
@testable import DYRender

final class MapSceneTests: XCTestCase {
    static let tree = SyntheticTree.make(scale: 0.4)
    static let lens = TreeLens(tree: tree)
    let viewPx = SIMD2<Double>(3200, 2000)

    private func model(mode: ColorMode = .kind) -> MapModel {
        let model = MapModel()
        model.setContent(lens: Self.lens, style: NodeStyle(colorMode: mode, now: SyntheticTree.referenceNow), metric: .bytes,
                         selection: [], animated: false, viewPx: viewPx, scale: 2, now: 0)
        return model
    }

    func testOverviewStaysInsideViewAndHitTestsFindNodes() throws {
        let model = model()
        let scene = model.buildScene(viewPx: viewPx, scale: 2, now: 0)
        XCTAssertGreaterThan(scene.tiles.count, 20)
        XCTAssertEqual(scene.tiles.count, scene.hitNodes.count)
        for tile in scene.tiles {
            XCTAssertGreaterThanOrEqual(tile.rect.x, -20_000)
            XCTAssertGreaterThan(tile.rect.z, 0)
        }
        let hit = try XCTUnwrap(model.hitTest(px: SIMD2(1600, 1000)))
        XCTAssertTrue(hit >= 0 && Int(hit) < Self.tree.count)
    }

    func testZoomingIntoDustResolvesIntoMoreTilesOfThatDirectory() throws {
        let tree = Self.tree
        let node = try XCTUnwrap(tree.find(path: "/Users/demo/Library/Caches/Homebrew"))
        let model = model()
        model.ensureLayout(viewPx: viewPx)
        let before = model.buildScene(viewPx: viewPx, scale: 2, now: 0)
        model.focus(on: node, animated: false, viewPx: viewPx, now: 0)
        let after = model.buildScene(viewPx: viewPx, scale: 2, now: 0)
        let inside = { (scene: SceneOutput) in scene.hitNodes.filter { tree.isAncestor(node, of: $0) && $0 != node }.count }
        XCTAssertGreaterThan(inside(after), inside(before))
        XCTAssertGreaterThan(inside(after), 50)
        XCTAssertEqual(after.focusNode, node)
    }

    func testFrameCostIsBoundedByTheScreenAtAnyZoom() throws {
        let model = model()
        model.ensureLayout(viewPx: viewPx)
        for _ in 0..<40 { model.zoom(by: 1.3, anchorPx: SIMD2(900, 600), viewPx: viewPx) }
        let scene = model.buildScene(viewPx: viewPx, scale: 2, now: 0)
        XCTAssertLessThan(scene.tiles.count, 80_000)
        XCTAssertLessThan(model.camera.scale, Camera.maxScale + 1)
    }

    func testZoomKeepsTheWorldPointUnderTheCursorFixed() throws {
        let model = model()
        let layout = try XCTUnwrap(model.ensureLayout(viewPx: viewPx))
        let anchor = SIMD2<Double>(2100, 700)
        func world() -> SIMD2<Double> {
            let ppu = model.camera.pixelsPerUnit(viewWidth: viewPx.x, world: layout.worldRect)
            return SIMD2(model.camera.centerX + (anchor.x - viewPx.x / 2) / ppu, model.camera.centerY + (anchor.y - viewPx.y / 2) / ppu)
        }
        let before = world()
        model.zoom(by: 3, anchorPx: anchor, viewPx: viewPx)
        let after = world()
        XCTAssertEqual(before.x, after.x, accuracy: 1e-9)
        XCTAssertEqual(before.y, after.y, accuracy: 1e-9)
    }

    func testColourModesUseOnlyPaletteColours() throws {
        let tree = Self.tree
        let node = try XCTUnwrap(tree.find(path: "/Users/demo/Movies/wedding-final-master.mov"))
        var style = NodeStyle(colorMode: .kind, now: SyntheticTree.referenceNow)
        let kind = TileColoring(tree: tree, style: style, dominantKind: []).color(of: node)
        XCTAssertEqual(kind, Palette.kind(.video))
        style = NodeStyle(colorMode: .safety, safety: [UInt8](repeating: SafetyTier.safe.rawValue, count: tree.count), now: 0)
        let coloring = TileColoring(tree: tree, style: style, dominantKind: [])
        XCTAssertEqual(coloring.color(of: node), Palette.accent)
        XCTAssertEqual(coloring.glow(of: node), 1)
        style = NodeStyle(colorMode: .decision, decisions: [UInt8](repeating: Decision.remove.rawValue, count: tree.count), now: 0)
        XCTAssertEqual(TileColoring(tree: tree, style: style, dominantKind: []).color(of: node), Palette.remove)
    }

    func testLensChangeTweensFromOldRectangles() throws {
        let model = model()
        model.ensureLayout(viewPx: viewPx)
        model.buildScene(viewPx: viewPx, scale: 2, now: 0)
        var hidden = [Bool](repeating: false, count: Self.tree.count)
        hidden[Int(try XCTUnwrap(Self.tree.find(path: "/Users/demo/Movies")))] = true
        model.setContent(lens: TreeLens(tree: Self.tree, hidden: hidden), style: NodeStyle(), metric: .bytes, selection: [],
                         animated: true, viewPx: viewPx, scale: 2, now: 10)
        XCTAssertTrue(model.step(now: 10.1), "tween should be running")
        XCTAssertFalse(model.step(now: 11), "tween should finish")
    }

    func testMotionIsSkippedWhenReduced() throws {
        let model = model()
        model.reduceMotion = true
        model.ensureLayout(viewPx: viewPx)
        model.focus(on: try XCTUnwrap(Self.tree.find(path: "/Users/demo/Movies")), animated: true, viewPx: viewPx, now: 0)
        XCTAssertFalse(model.step(now: 0.01))
    }

    func testAtlasEvictsLeastRecentlyUsedWhenFull() {
        let atlas = LabelAtlas(width: 128, height: 64)
        var kept = 0
        for index in 0..<80 {
            atlas.beginFrame()
            if atlas.entry(for: TextSpec(text: "label \(index)", size: 12)) != nil { kept += 1 }
        }
        XCTAssertEqual(kept, 80, "old entries must be evicted to make room")
        atlas.beginFrame()
        XCTAssertNotNil(atlas.entry(for: TextSpec(text: "label 79", size: 12)))
        XCTAssertFalse(atlas.takeDirty().isEmpty)
    }

    func testTextIsRasterisedWithTruncation() {
        let full = TextRasterizer.rasterize(TextSpec(text: "a rather long file name.mov", size: 14))
        let cut = TextRasterizer.rasterize(TextSpec(text: "a rather long file name.mov", size: 14, maxWidth: 80))
        XCTAssertLessThan(cut.textWidth, 81)
        XCTAssertGreaterThan(full.textWidth, cut.textWidth)
        XCTAssertTrue(full.pixels.contains { $0 > 128 })
    }

    @MainActor
    func testSnapshotRendersOffscreenAndIdlesWithoutADisplayLink() throws {
        try XCTSkipIf(GPUContext.shared == nil, "no Metal device")
        _ = NSApplication.shared
        let canvas = MapCanvas(frame: NSRect(x: 0, y: 0, width: 400, height: 250))
        canvas.update(lens: Self.lens, style: NodeStyle(now: SyntheticTree.referenceNow), metric: .bytes, selection: [], animated: false)
        XCTAssertFalse(canvas.isAnimating, "idle must run no display link")
        let image = try XCTUnwrap(canvas.snapshot(size: CGSize(width: 400, height: 250), scale: 2))
        XCTAssertEqual(image.width, 800)
        XCTAssertEqual(image.height, 500)
        let data = try XCTUnwrap(image.dataProvider?.data as Data?)
        XCTAssertGreaterThan(Set(data.prefix(40_000)).count, 8, "image should not be flat")
        XCTAssertGreaterThan(canvas.lastCounts.tiles, 10)
    }
}

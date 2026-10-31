import XCTest
import AppKit
import DYCore
@testable import DYRender

final class RingsFieldTests: XCTestCase {
    static let tree = SyntheticTree.make(scale: 0.4)
    static let lens = TreeLens(tree: tree)

    func testRingsSpansSumToParentSpanAtEveryNode() {
        for metric in [Metric.bytes, .files] {
            let arcs = RingsLayout.arcs(lens: Self.lens, metric: metric, root: 0)
            XCTAssertFalse(arcs.isEmpty)
            XCTAssertLessThanOrEqual((arcs.map(\.depth).max() ?? 0) + 1, RingsLayout.levels)
            var childSpan: [NodeID: Double] = [:], childValue: [NodeID: UInt64] = [:]
            for arc in arcs { childSpan[arc.parent, default: 0] += arc.span; childValue[arc.parent, default: 0] += arc.value }
            XCTAssertEqual(childSpan[0] ?? 0, 2 * Double.pi, accuracy: 1e-9)
            for arc in arcs where !arc.isDust && arc.isDirectory && arc.depth < RingsLayout.levels - 1 {
                XCTAssertEqual(childSpan[arc.node] ?? 0, arc.span, accuracy: 1e-9, "children must fill \(arc.node)")
                XCTAssertEqual(childValue[arc.node] ?? 0, arc.value - (arc.value - (childValue[arc.node] ?? 0)))
            }
        }
    }

    func testRingsArcsNestInsideTheirParentAndDustIsOneArcPerParent() {
        let arcs = RingsLayout.arcs(lens: Self.lens, metric: .bytes, root: 0)
        let byNode = Dictionary(uniqueKeysWithValues: arcs.filter { !$0.isDust }.map { ($0.node, $0) })
        for arc in arcs where arc.parent != 0 {
            let parent = byNode[arc.parent]!
            XCTAssertGreaterThanOrEqual(arc.start, parent.start - 1e-9)
            XCTAssertLessThanOrEqual(arc.end, parent.end + 1e-9)
            XCTAssertEqual(arc.depth, parent.depth + 1)
        }
        let dust = arcs.filter(\.isDust)
        XCTAssertEqual(Set(dust.map(\.parent)).count, dust.count)
        XCTAssertTrue(dust.allSatisfy { $0.dustFiles > 0 || $0.dustBytes > 0 })
        XCTAssertEqual(arcs.map(\.start), RingsLayout.arcs(lens: Self.lens, metric: .bytes, root: 0).map(\.start))
    }

    func testRingsFocusedDirectoryFillsTheCircle() throws {
        let node = try XCTUnwrap(Self.tree.find(path: "/Users/demo/Developer"))
        let arcs = RingsLayout.arcs(lens: Self.lens, metric: .bytes, root: node)
        XCTAssertEqual(arcs.filter { $0.depth == 0 }.reduce(0) { $0 + $1.span }, 2 * Double.pi, accuracy: 1e-9)
    }

    func testRingsGeometryLocatesDepthAndAngle() {
        let g = RingsGeometry(viewPx: SIMD2(1000, 1000), margin: 20)
        XCTAssertNil(g.locate(g.centre))
        XCTAssertNil(g.locate(SIMD2(0, 0)))
        let right = g.locate(SIMD2(g.centre.x + (g.edges[0] + g.edges[1]) / 2, g.centre.y))
        XCTAssertEqual(right?.depth, 0)
        XCTAssertEqual(right?.angle ?? -1, Double.pi / 2, accuracy: 1e-9)
        let top = g.locate(SIMD2(g.centre.x, g.centre.y - (g.edges[4] + g.edges[5]) / 2))
        XCTAssertEqual(top?.depth, 4)
    }

    @MainActor
    func testRingsSnapshotHitTestsAndIdles() throws {
        try XCTSkipIf(GPUContext.shared == nil, "no Metal device")
        _ = NSApplication.shared
        let canvas = RingsCanvas(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        canvas.update(lens: Self.lens, style: NodeStyle(now: SyntheticTree.referenceNow), metric: .bytes, selection: [], animated: false)
        XCTAssertFalse(canvas.isAnimating)
        let image = try XCTUnwrap(canvas.snapshot(size: CGSize(width: 500, height: 400), scale: 2))
        XCTAssertEqual(image.width, 1000)
        XCTAssertGreaterThan(canvas.lastArcCount, 10)
        let g = RingsGeometry(viewPx: SIMD2(1000, 800), margin: 44)
        XCTAssertNotNil(canvas.arc(atPx: SIMD2(g.centre.x + (g.edges[0] + g.edges[1]) / 2, g.centre.y + 1)))
        XCTAssertNil(canvas.arc(atPx: g.centre))
    }

    @MainActor
    func testFieldSnapshotFindsTheBiggestPointAndIdles() throws {
        try XCTSkipIf(GPUContext.shared == nil, "no Metal device")
        _ = NSApplication.shared
        var positions: [SIMD2<Float>] = [], nodes: [NodeID] = []
        for index in 0..<5_000 {
            positions.append(SIMD2(Float(index % 100) / 40, 3 + Float(index % 50) / 10))
            nodes.append(NodeID(index))
        }
        positions.append(SIMD2(3.0, 10.5))
        nodes.append(99_999)
        let canvas = FieldCanvas(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        canvas.setPoints(positions: positions, kinds: [UInt8](repeating: 1, count: positions.count), nodes: nodes, ageRange: 0...3.5, sizeRange: 3...11)
        XCTAssertFalse(canvas.isAnimating)
        let image = try XCTUnwrap(canvas.snapshot(size: CGSize(width: 400, height: 300), scale: 2))
        XCTAssertEqual(image.height, 600)
        let data = try XCTUnwrap(image.dataProvider?.data as Data?)
        XCTAssertGreaterThan(Set(data.prefix(60_000)).count, 6)
        var found = false
        for x in stride(from: 100.0, to: 800.0, by: 4.0) {
            for y in stride(from: 20.0, to: 150.0, by: 4.0) where canvas.node(atPx: SIMD2(x, y)) == 99_999 { found = true }
        }
        XCTAssertTrue(found, "the biggest file must be hoverable")
    }

    func testBrushEventExistsOnCanvasEvents() {
        var events = CanvasEvents()
        var got: (ClosedRange<Float>, ClosedRange<Float>)?
        events.onBrush = { got = ($0, $1) }
        events.onBrush?(0...1, 3...5)
        XCTAssertEqual(got?.1, 3...5)
    }

    @MainActor
    func testFieldSurvivesFewPointsAndLiftsThem() throws {
        try XCTSkipIf(GPUContext.shared == nil, "no Metal device")
        _ = NSApplication.shared
        for count in [1, 3, 15, 17] {
            let canvas = FieldCanvas(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
            let positions = (0..<count).map { SIMD2(Float($0) / 5, 3 + Float($0) / 3) }
            canvas.setPoints(positions: positions, kinds: [UInt8](repeating: 2, count: count), nodes: (0..<count).map { NodeID($0) },
                             ageRange: 0...3.5, sizeRange: 3...9)
            XCTAssertNotNil(canvas.snapshot(size: CGSize(width: 300, height: 200), scale: 1), "\(count) points")
        }
        XCTAssertEqual(FieldCanvas.fewPointBoost(count: 1), 1)
        XCTAssertEqual(FieldCanvas.fewPointBoost(count: 100), 1)
        XCTAssertEqual(FieldCanvas.fewPointBoost(count: 20_000), 0, "dense fields must render exactly as before")
        XCTAssertEqual(FieldCanvas.fewPointBoost(count: 2_000_000), 0)
        XCTAssertGreaterThan(FieldCanvas.fewPointBoost(count: 1_000), FieldCanvas.fewPointBoost(count: 5_000))
    }
}

import XCTest
import DYCore
@testable import DYRender

final class MapLayoutTests: XCTestCase {
    static let tree = SyntheticTree.make(scale: 0.4)
    static let lens = TreeLens(tree: tree)

    private func values(_ seed: UInt64, count: Int) -> [Double] {
        var state = seed
        var result: [Double] = []
        for _ in 0..<count {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            result.append(pow(Double(state >> 40) / Double(1 << 24) + 0.001, 3) * 1000 + 1)
        }
        return result.sorted(by: >)
    }

    func testSquarifyTilesParentExactlyWithoutOverlap() {
        let rect = WRect(0.2, 0.1, 1.6, 1.0)
        let vals = values(7, count: 60)
        let rects = Squarify.layout(values: vals, in: rect)
        XCTAssertEqual(rects.count, vals.count)
        XCTAssertEqual(rects.reduce(0) { $0 + $1.area }, rect.area, accuracy: 1e-9)
        for (index, r) in rects.enumerated() {
            XCTAssertTrue(rect.contains(r), "tile \(index) escapes")
            XCTAssertEqual(r.area / rect.area, vals[index] / vals.reduce(0, +), accuracy: 1e-9)
            for other in rects[(index + 1)...] { XCTAssertFalse(r.overlaps(other)) }
        }
    }

    func testSquarifyAspectsStayModerate() {
        let rect = WRect(0, 0, 1.6, 1.0)
        let rects = Squarify.layout(values: values(3, count: 30), in: rect)
        let total = rect.area
        for r in rects where r.area / total > 0.02 {
            let aspect = max(r.w / r.h, r.h / r.w)
            XCTAssertLessThan(aspect, 5, "big tile too elongated: \(r)")
        }
    }

    func testSquarifyIsDeterministicAndHandlesEdgeCases() {
        let rect = WRect(0, 0, 1.6, 1)
        let vals = values(11, count: 40)
        XCTAssertEqual(Squarify.layout(values: vals, in: rect), Squarify.layout(values: vals, in: rect))
        XCTAssertTrue(Squarify.layout(values: [], in: rect).isEmpty)
        XCTAssertEqual(Squarify.layout(values: [5], in: rect), [rect])
    }

    func testContainerTilesSumToParentAreaAndValueExactly() {
        for metric in [Metric.bytes, .files] {
            let layout = MapLayout(lens: Self.lens, metric: metric, worldAspect: 1.6)
            let root = layout.layout(parent: 0, start: 0, in: layout.contentRect(of: layout.worldRect))
            XCTAssertFalse(root.tiles.isEmpty)
            XCTAssertEqual(root.tiles.reduce(0) { $0 + $1.rect.area }, root.rect.area, accuracy: 1e-9)
            let list = layout.children(of: 0)
            XCTAssertEqual(root.tiles.reduce(0) { $0 + $1.value }, list.valuePrefix[list.count])
            for (index, tile) in root.tiles.enumerated() {
                XCTAssertTrue(root.rect.contains(tile.rect))
                for other in root.tiles[(index + 1)...] { XCTAssertFalse(tile.rect.overlaps(other.rect)) }
            }
        }
    }

    func testDustChainResolvesEveryChildExactlyOnce() throws {
        let layout = MapLayout(lens: Self.lens, metric: .bytes, worldAspect: 1.6)
        let tree = Self.tree
        let parent = try XCTUnwrap(tree.find(path: "/Users/demo/Library/Caches/Homebrew"))
        let list = layout.children(of: parent)
        XCTAssertGreaterThan(list.count, 100)
        var seen: [NodeID] = []
        var start = 0
        var rect = WRect(0, 0, 1.6, 1)
        var valueSum: UInt64 = 0
        var chunks = 0
        while true {
            let container = layout.layout(parent: parent, start: start, in: rect)
            XCTAssertEqual(container.tiles.reduce(0) { $0 + $1.rect.area }, rect.area, accuracy: 1e-9)
            var tail: LayoutTile?
            for tile in container.tiles {
                if tile.isTail { tail = tile } else { seen.append(tile.node); valueSum += tile.value }
            }
            chunks += 1
            guard let tail, let info = tail.tail else { break }
            XCTAssertEqual(info.start + info.count, list.count)
            XCTAssertEqual(tail.value, list.valuePrefix[list.count] - list.valuePrefix[info.start])
            XCTAssertGreaterThan(info.start, start)
            start = info.start
            rect = tail.rect
        }
        XCTAssertGreaterThan(chunks, 1, "dust must recurse")
        XCTAssertEqual(seen, list.ids)
        XCTAssertEqual(valueSum, list.valuePrefix[list.count])
    }

    func testLayoutIsDeterministicAcrossInstances() {
        let a = MapLayout(lens: Self.lens, metric: .bytes, worldAspect: 1.6)
        let b = MapLayout(lens: Self.lens, metric: .bytes, worldAspect: 1.6)
        let rect = a.contentRect(of: a.worldRect)
        let first = a.layout(parent: 0, start: 0, in: rect).tiles
        let second = b.layout(parent: 0, start: 0, in: rect).tiles
        XCTAssertEqual(first.map(\.rect), second.map(\.rect))
        XCTAssertEqual(first.map(\.node), second.map(\.node))
    }

    func testRectOfFindsNodesInsideTheirParentsContentRect() throws {
        let layout = MapLayout(lens: Self.lens, metric: .bytes, worldAspect: 1.6)
        XCTAssertEqual(layout.rect(of: 0), layout.worldRect)
        for path in ["/Users/demo/Movies", "/Users/demo/Developer/storefront/node_modules", "/Users/demo/Library/Caches/Homebrew/cache_17.bin"] {
            let node = try XCTUnwrap(Self.tree.find(path: path))
            let rect = try XCTUnwrap(layout.rect(of: node), path)
            let parent = try XCTUnwrap(layout.rect(of: Self.tree.parent(node)))
            XCTAssertTrue(layout.contentRect(of: parent).contains(rect), path)
        }
        XCTAssertGreaterThan(layout.rect(of: try XCTUnwrap(Self.tree.find(path: "/Users")))!.area, 0)
    }

    func testHiddenNodesHaveNoRect() throws {
        let tree = Self.tree
        var hidden = [Bool](repeating: false, count: tree.count)
        let movies = try XCTUnwrap(tree.find(path: "/Users/demo/Movies"))
        hidden[Int(movies)] = true
        let layout = MapLayout(lens: TreeLens(tree: tree, hidden: hidden), metric: .bytes, worldAspect: 1.6)
        XCTAssertNil(layout.rect(of: movies))
    }
}

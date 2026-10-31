import DYCore
import XCTest
@testable import DYAnalysis

final class SpectrumFieldTests: XCTestCase {
    func testBinsPartitionFilesAndBytes() {
        let tree = SyntheticTree.make(scale: 0.3)
        let lens = TreeLens(tree: tree)
        let result = SpectrumEngine.compute(lens: lens, under: 0)
        XCTAssertEqual(result.bins.reduce(0) { $0 + $1.count }, result.totalFiles)
        XCTAssertEqual(result.bins.reduce(0) { $0 + $1.bytes }, result.totalBytes)
        XCTAssertLessThanOrEqual(result.totalBytes, lens.size[0])
        for bin in result.bins {
            XCTAssertEqual(bin.bytesByKind.reduce(0, +), bin.bytes)
            XCTAssertEqual(bin.countByKind.reduce(0, +), bin.count)
            XCTAssertEqual(bin.bytesByKind.count, FileKind.allCases.count)
            XCTAssertLessThan(bin.lower, bin.upper)
        }
        for (a, b) in zip(result.bins, result.bins.dropFirst()) { XCTAssertEqual(a.upper, b.lower) }
    }

    func testBinBoundariesAreOneTwoFive() {
        XCTAssertEqual(SpectrumEngine.binIndex(0), 0)
        XCTAssertEqual(SpectrumEngine.binIndex(1), 1)
        XCTAssertEqual(SpectrumEngine.binIndex(2), 2)
        XCTAssertEqual(SpectrumEngine.binIndex(4), 2)
        XCTAssertEqual(SpectrumEngine.binIndex(5), 3)
        XCTAssertEqual(SpectrumEngine.binIndex(9), 3)
        XCTAssertEqual(SpectrumEngine.binIndex(10), 4)
        XCTAssertEqual(SpectrumEngine.binIndex(999_999), 3 * 5 + 3)
        XCTAssertEqual(SpectrumEngine.binIndex(UInt64.max), 1 + 19 * 3)
    }

    func testCurveAndItemsForShare() {
        let sketch = TreeSketch(root: "/s")
        for size in [800, 100, 50, 30, 10, 5, 3, 2] as [UInt64] { sketch.file(0, "f\(size)", size) }
        let lens = TreeLens(tree: sketch.tree())
        let result = SpectrumEngine.compute(lens: lens, under: 0)
        XCTAssertEqual(result.itemsForShare(0.5), 1)
        XCTAssertEqual(result.itemsForShare(0.8), 1)
        XCTAssertEqual(result.itemsForShare(0.81), 2)
        XCTAssertEqual(result.itemsForShare(1), 8)
        XCTAssertEqual(result.itemsForShare(0), 0)
        XCTAssertEqual(result.curve.count, 8)
        XCTAssertEqual(result.curve.last?.byteShare ?? 0, 1, accuracy: 1e-9)
        XCTAssertEqual(result.curve.first?.itemShare ?? 0, 0.125, accuracy: 1e-9)
    }

    func testCurveIsBoundedAndMonotone() {
        let tree = SyntheticTree.make(scale: 1)
        let result = SpectrumEngine.compute(lens: TreeLens(tree: tree), under: 0)
        XCTAssertLessThanOrEqual(result.curve.count, 512)
        XCTAssertGreaterThan(result.curve.count, 50)
        for (a, b) in zip(result.curve, result.curve.dropFirst()) {
            XCTAssertLessThan(a.itemShare, b.itemShare)
            XCTAssertLessThanOrEqual(a.byteShare, b.byteShare)
        }
        let top = result.itemsForShare(0.8)
        XCTAssertGreaterThan(top, 0)
        XCTAssertLessThan(Double(top), Double(result.totalFiles) * 0.2)
        XCTAssertLessThanOrEqual(result.itemsForShare(0.5), top)
    }

    func testFieldKeepsEverythingUnderMaxAndSamplesDeterministically() throws {
        let tree = SyntheticTree.make(scale: 0.3)
        let lens = TreeLens(tree: tree)
        let all = FieldEngine.compute(lens: lens, under: 0, clock: .modified, maxPoints: .max)
        XCTAssertEqual(all.positions.count, all.nodes.count)
        XCTAssertEqual(all.kinds.count, all.nodes.count)
        XCTAssertGreaterThan(all.nodes.count, 1_000)
        XCTAssertTrue(all.positions.allSatisfy { all.ageRange.contains($0.x) && all.sizeRange.contains($0.y) })
        let limit = 500
        let first = FieldEngine.compute(lens: lens, under: 0, clock: .accessed, maxPoints: limit)
        let second = FieldEngine.compute(lens: lens, under: 0, clock: .accessed, maxPoints: limit)
        XCTAssertEqual(first.nodes, second.nodes)
        XCTAssertLessThanOrEqual(first.nodes.count, limit)
        XCTAssertGreaterThan(first.nodes.count, limit * 9 / 10)
        let biggest = all.nodes.max { lens.size[Int($0)] < lens.size[Int($1)] }!
        XCTAssertTrue(first.nodes.contains(biggest))
        let largest50 = all.nodes.sorted { lens.size[Int($0)] > lens.size[Int($1)] }.prefix(limit / 2)
        XCTAssertTrue(Set(first.nodes).isSuperset(of: largest50))
    }

    func testFieldAxes() throws {
        let sketch = TreeSketch(root: "/f")
        sketch.file(0, "old", 1_000, modified: SyntheticTree.referenceNow - 100 * 86_400)
        let lens = TreeLens(tree: sketch.tree())
        let data = FieldEngine.compute(lens: lens, under: 0, clock: .modified, maxPoints: 10)
        XCTAssertEqual(data.positions[0].x, 2, accuracy: 0.01)
        XCTAssertEqual(data.positions[0].y, 3, accuracy: 0.01)
    }
}

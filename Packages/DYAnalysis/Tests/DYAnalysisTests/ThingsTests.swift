import DYCore
import XCTest
@testable import DYAnalysis

final class ThingsTests: XCTestCase {
    /// Asserts the cut is disjoint and sums to the value at `under`.
    func assertExactCut(_ lens: TreeLens, under: NodeID, threshold: UInt64, metric: Metric, file: StaticString = #filePath, line: UInt = #line) {
        let result = ThingsEngine.cut(lens: lens, under: under, threshold: threshold, metric: metric)
        XCTAssertEqual(result.total, lens.value(under, metric), file: file, line: line)
        XCTAssertEqual(result.items.reduce(0) { $0 + $1.value }, result.total, "T=\(threshold)", file: file, line: line)
        XCTAssertEqual(Set(result.items.map(\.id)).count, result.items.count, "duplicate ids", file: file, line: line)
        var nodes: [NodeID] = []
        for item in result.items {
            if case .node(let node) = item.content { nodes.append(node); XCTAssertEqual(item.value, lens.value(node, metric), file: file, line: line) }
            if case .rest(let parent, _) = item.content { XCTAssertTrue(lens.tree.isAncestor(under, of: parent), file: file, line: line) }
        }
        for (i, a) in nodes.enumerated() {
            for b in nodes[(i + 1)...] where lens.tree.isAncestor(a, of: b) || lens.tree.isAncestor(b, of: a) {
                XCTFail("overlapping items \(a) \(b)", file: file, line: line)
            }
        }
        XCTAssertEqual(result.items.map(\.value), result.items.map(\.value).sorted(by: >), file: file, line: line)
    }

    func testSumsExactlyForManyThresholdsBothMetrics() {
        let tree = SyntheticTree.make(scale: 0.3)
        let lens = TreeLens(tree: tree)
        for metric in [Metric.bytes, .files] {
            let total = lens.value(0, metric)
            var threshold: UInt64 = 1
            while threshold < total * 2 {
                assertExactCut(lens, under: 0, threshold: threshold, metric: metric)
                threshold = threshold * 3 + 1
            }
            assertExactCut(lens, under: 0, threshold: 0, metric: metric)
        }
    }

    func testExactUnderSubdirectoriesAndWithHiddenAndFilter() throws {
        let tree = SyntheticTree.make(scale: 0.3)
        let hidden = IgnoreEngine.evaluate(.defaults, tree: tree, home: "/Users/demo", isCancelled: { false })!.hidden
        let matches = QueryEngine.matches(Query.parse("size>20000"), tree: tree, context: QueryContext(now: SyntheticTree.referenceNow), isCancelled: { false })
        let lens = TreeLens(tree: tree, hidden: hidden, matches: matches)
        for path in ["/", "/Users/demo", "/Users/demo/Library", "/Users/demo/Developer/storefront/node_modules", "/Applications/Xcode.app"] {
            let node = try XCTUnwrap(tree.find(path: path))
            for threshold in [1, 10_000, 1_000_000, 50 * megabyte, 2_000 * megabyte] as [UInt64] {
                assertExactCut(lens, under: node, threshold: threshold, metric: .bytes)
            }
            assertExactCut(lens, under: node, threshold: 100, metric: .files)
        }
    }

    func testOwnersExampleFileAndDirectoryAreNeighbours() throws {
        let sketch = TreeSketch(root: "/data")
        sketch.file(0, "interview.mp4", 400 * megabyte)
        let folder = sketch.dir(0, "Exports")
        for index in 0..<41 { sketch.file(folder, "part\(index).bin", 10 * megabyte) }
        sketch.file(0, "notes.txt", 5 * megabyte)
        let tree = sketch.tree()
        let lens = TreeLens(tree: tree)
        let exports = try XCTUnwrap(tree.find(path: "/data/Exports"))
        let video = try XCTUnwrap(tree.find(path: "/data/interview.mp4"))
        let result = ThingsEngine.cut(lens: lens, under: 0, threshold: 400 * megabyte, metric: .bytes)
        XCTAssertEqual(result.items.map(\.content), [.node(exports), .node(video), .rest(parent: 0, items: 1)])
        XCTAssertEqual(result.items.map(\.value), [410 * megabyte, 400 * megabyte, 5 * megabyte])
        assertExactCut(lens, under: 0, threshold: 400 * megabyte, metric: .bytes)
    }

    func testSmallRemainderIsCarriedUpward() throws {
        let sketch = TreeSketch(root: "/r")
        let outer = sketch.dir(0, "outer")
        let inner = sketch.dir(outer, "inner")
        sketch.file(inner, "huge", 100)
        sketch.file(inner, "dust1", 3)
        sketch.file(outer, "dust2", 4)
        sketch.file(0, "other", 60)
        let lens = TreeLens(tree: sketch.tree())
        let result = ThingsEngine.cut(lens: lens, under: 0, threshold: 50, metric: .bytes)
        let rests = result.items.filter { if case .rest = $0.content { true } else { false } }
        XCTAssertEqual(rests.count, 1)
        XCTAssertEqual(rests[0].value, 7)
        XCTAssertEqual(rests[0].content, .rest(parent: 0, items: 2))
        assertExactCut(lens, under: 0, threshold: 50, metric: .bytes)
    }

    func testAtomsStayWholeUnlessUnderIsTheAtom() throws {
        let sketch = TreeSketch(root: "/p")
        let project = sketch.dir(0, "proj")
        let modulesBuilt = sketch.dir(project, "node_modules")
        for index in 0..<10 { sketch.file(modulesBuilt, "pkg\(index)", 100) }
        sketch.file(project, "package.json", 1)
        let scratch = sketch.dir(0, "scratch")
        let targetBuilt = sketch.dir(scratch, "target")
        for index in 0..<10 { sketch.file(targetBuilt, "obj\(index)", 100) }
        let appBuilt = sketch.dir(0, "Thing.app", flags: .package)
        for index in 0..<10 { sketch.file(appBuilt, "res\(index)", 100) }
        let looseBuilt = sketch.dir(0, "build")
        for index in 0..<10 { sketch.file(looseBuilt, "o\(index)", 100) }
        let tree = sketch.tree()
        let lens = TreeLens(tree: tree)
        let modules = tree.find(path: "/p/proj/node_modules")!, app = tree.find(path: "/p/Thing.app")!
        let target = tree.find(path: "/p/scratch/target")!, loose = tree.find(path: "/p/build")!
        XCTAssertTrue(ThingsEngine.isAtom(tree: tree, node: modules))
        XCTAssertTrue(ThingsEngine.isAtom(tree: tree, node: app))
        XCTAssertFalse(ThingsEngine.isAtom(tree: tree, node: target), "target without Cargo.toml is not an atom")
        XCTAssertFalse(ThingsEngine.isAtom(tree: tree, node: loose))
        XCTAssertFalse(ThingsEngine.isAtom(tree: tree, node: tree.find(path: "/p/proj/package.json")!))
        let contents = ThingsEngine.cut(lens: lens, under: 0, threshold: 100, metric: .bytes).items.map(\.content)
        XCTAssertTrue(contents.contains(.node(modules)))
        XCTAssertTrue(contents.contains(.node(app)))
        XCTAssertFalse(contents.contains(.node(target)))
        let inside = ThingsEngine.cut(lens: lens, under: modules, threshold: 100, metric: .bytes)
        XCTAssertEqual(inside.items.count, 10)
    }

    func testTargetBecomesAtomBesideCargoToml() {
        let sketch = TreeSketch(root: "/p")
        let target = sketch.dir(0, "target")
        sketch.file(target, "a", 10)
        sketch.file(0, "Cargo.toml", 1)
        let tree = sketch.tree()
        XCTAssertTrue(ThingsEngine.isAtom(tree: tree, node: tree.find(path: "/p/target")!))
    }

    func testThresholdForApproximatelyItems() {
        let tree = SyntheticTree.make(scale: 0.5)
        let lens = TreeLens(tree: tree)
        for wanted in [12, 100, 1_000] {
            let threshold = ThingsEngine.thresholdForApproximately(items: wanted, lens: lens, under: 0, metric: .bytes)
            let count = ThingsEngine.cut(lens: lens, under: 0, threshold: threshold, metric: .bytes).items.count
            XCTAssertLessThan(abs(count - wanted), max(3, wanted / 5), "wanted \(wanted) got \(count)")
        }
    }

    func testEmptyAndSingleFile() {
        let sketch = TreeSketch(root: "/p")
        let file = sketch.file(0, "only", 9)
        let lens = TreeLens(tree: sketch.tree())
        XCTAssertEqual(ThingsEngine.cut(lens: lens, under: file, threshold: 100, metric: .bytes).items.map(\.value), [9])
        XCTAssertTrue(ThingsEngine.cut(lens: lens, under: 0, threshold: 1, metric: .files).items.count == 1)
    }
}

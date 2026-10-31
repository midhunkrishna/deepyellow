import DYCore
import XCTest
@testable import DYAnalysis

final class IgnoreTests: XCTestCase {
    let home = "/Users/demo"

    func evaluate(_ patterns: [String], tree: FileTree) -> IgnoreResult {
        let set = IgnoreRuleSet(rules: patterns.map { IgnoreRule(pattern: $0) })
        return IgnoreEngine.evaluate(set, tree: tree, home: home, isCancelled: { false })!
    }

    func testDefaultsHideDSStoreAndKeepCachesVisible() throws {
        let tree = SyntheticTree.make(scale: 0.2)
        let result = try XCTUnwrap(IgnoreEngine.evaluate(.defaults, tree: tree, home: home, isCancelled: { false }))
        let caches = try XCTUnwrap(tree.find(path: "/Users/demo/Library/Caches"))
        XCTAssertFalse(result.hidden[Int(caches)])
        for child in tree.children(caches) { XCTAssertFalse(result.hidden[Int(child)]) }
        let store = try XCTUnwrap(tree.find(path: "/Users/demo/.DS_Store"))
        XCTAssertTrue(result.hidden[Int(store)])
    }

    func testKeepBeatsHideOnSameNode() throws {
        let tree = SyntheticTree.make(scale: 0.2)
        var rules = IgnoreRuleSet.defaults.rules
        rules.append(IgnoreRule(pattern: "Caches"))
        rules.append(IgnoreRule(pattern: "~/Library/Caches/*"))
        let result = try XCTUnwrap(IgnoreEngine.evaluate(IgnoreRuleSet(rules: rules), tree: tree, home: home, isCancelled: { false }))
        let caches = try XCTUnwrap(tree.find(path: "/Users/demo/Library/Caches"))
        XCTAssertFalse(result.hidden[Int(caches)])
        let safari = try XCTUnwrap(tree.find(path: "/Users/demo/Library/Caches/com.apple.Safari"))
        XCTAssertTrue(result.hidden[Int(safari)])
    }

    func testDefaultPresetsHaveStableUniqueIDs() {
        let ids = IgnoreRuleSet.defaults.rules.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(ids, IgnoreRuleSet.defaults.rules.map(\.id))
        XCTAssertTrue(IgnoreRuleSet.defaults.rules.allSatisfy(\.isPreset))
    }

    func testPerRuleCountsTopmostNodeOnce() throws {
        let sketch = TreeSketch()
        let cache = sketch.dir(0, "junk")
        sketch.file(cache, "a.tmp", 100)
        let inner = sketch.dir(cache, "junk")
        sketch.file(inner, "b.tmp", 50)
        sketch.file(0, "keep.txt", 7)
        let tree = sketch.tree()
        let rules = IgnoreRuleSet(rules: [IgnoreRule(pattern: "junk"), IgnoreRule(pattern: "*.tmp")])
        let result = try XCTUnwrap(IgnoreEngine.evaluate(rules, tree: tree, home: home, isCancelled: { false }))
        XCTAssertEqual(result.perRule[rules.rules[0].id]?.bytes, 150)
        XCTAssertEqual(result.perRule[rules.rules[0].id]?.files, 2)
        XCTAssertEqual(result.perRule[rules.rules[1].id]?.bytes, 0)
        XCTAssertTrue(result.hidden[Int(tree.find(path: "/junk/junk/b.tmp")!)])
        XCTAssertFalse(result.hidden[Int(tree.find(path: "/keep.txt")!)])
    }

    func testPatternShapes() throws {
        let sketch = TreeSketch()
        let library = sketch.dir(0, "Library")
        let logs = sketch.dir(library, "Logs")
        sketch.file(logs, "x.log", 1)
        let other = sketch.dir(0, "Other")
        let otherLogs = sketch.dir(other, "Logs")
        sketch.file(other, "Logs.txt", 1)
        sketch.file(otherLogs, "y.log", 1)
        let tree = sketch.tree()
        func hidden(_ pattern: String, _ path: String) -> Bool {
            evaluate([pattern], tree: tree).hidden[Int(tree.find(path: path)!)]
        }
        XCTAssertTrue(hidden("Library/Logs", "/Library/Logs"))
        XCTAssertFalse(hidden("Library/Logs", "/Other/Logs"))
        XCTAssertTrue(hidden("/Other/Logs", "/Other/Logs/y.log"))
        XCTAssertFalse(hidden("/Logs", "/Other/Logs"))
        XCTAssertTrue(hidden("logs/", "/Other/Logs"))
        XCTAssertFalse(hidden("Logs.txt/", "/Other/Logs.txt"))
        XCTAssertTrue(hidden("L?gs.*", "/Other/Logs.txt"))
        XCTAssertTrue(hidden("*.LOG", "/Library/Logs/x.log"))
    }

    func testCancellationReturnsNil() {
        let tree = SyntheticTree.make(scale: 2)
        XCTAssertNil(IgnoreEngine.evaluate(.defaults, tree: tree, home: home, isCancelled: { true }))
    }

    func testHiddenFeedsLensAndKeepsAccounting() throws {
        let tree = SyntheticTree.make(scale: 0.2)
        let result = try XCTUnwrap(IgnoreEngine.evaluate(.defaults, tree: tree, home: home, isCancelled: { false }))
        let lens = TreeLens(tree: tree, hidden: result.hidden)
        XCTAssertEqual(lens.size[0] + lens.hiddenBytes, tree.allocated(0))
        XCTAssertEqual(result.perRule.values.reduce(0) { $0 + $1.bytes }, lens.hiddenBytes)
    }
}

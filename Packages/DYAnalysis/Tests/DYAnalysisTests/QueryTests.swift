import DYCore
import XCTest
@testable import DYAnalysis

final class QueryTests: XCTestCase {
    var tree: FileTree!
    let now = SyntheticTree.referenceNow
    let day: Int32 = 86_400

    override func setUp() {
        let sketch = TreeSketch(root: "/Users/demo")
        let movies = sketch.dir(0, "Movies")
        sketch.file(movies, "Big.MOV", 500 * megabyte, modified: now - 400 * day, accessed: now - 10 * day)
        sketch.file(movies, "small.mp4", 2 * megabyte, modified: now - 2 * day, accessed: now - day)
        let pictures = sketch.dir(0, "Pictures")
        sketch.file(pictures, "a.png", 3 * megabyte, modified: now - 30 * day, accessed: now - 100 * day)
        let app = sketch.dir(pictures, "Thing.app", flags: .package)
        sketch.file(app, "inner.bin", 10, modified: now, accessed: now, flags: .dataless)
        sketch.file(0, "clone.dat", 5, modified: now, accessed: now, flags: .cloneDuplicate)
        tree = sketch.tree()
    }

    func names(_ text: String, context: QueryContext? = nil) throws -> Set<String> {
        let query = Query.parse(text)
        let context = context ?? QueryContext(now: now)
        let flags = try XCTUnwrap(QueryEngine.matches(query, tree: tree, context: context, isCancelled: { false }))
        return Set(flags.indices.filter { flags[$0] }.map { tree.name(NodeID($0)) })
    }

    func testParseCollectsErrorsWithoutCrashing() {
        let query = Query.parse("size>12xx foo:bar age>zz kind:nothing is:wat mark:x safe:y ext:")
        XCTAssertEqual(query.errors.count, 8)
        XCTAssertTrue(Query.parse("").isEmpty)
        XCTAssertTrue(Query.parse("  ").isEmpty)
        XCTAssertFalse(Query.parse("size>1mb").isEmpty)
        XCTAssertEqual(Query.parse("size>1mb").text, "size>1mb")
        XCTAssertEqual(Query.parse("size>1mb"), Query.parse("size>1mb"))
    }

    func testSizeAndAgeAndOpened() throws {
        XCTAssertEqual(try names("size>100mb"), ["Big.MOV"])
        XCTAssertEqual(try names("size<1mb -is:dataless size>4"), ["clone.dat"])
        XCTAssertEqual(try names("age>1y"), ["Big.MOV"])
        XCTAssertEqual(try names("age<1w kind:video"), ["small.mp4"])
        XCTAssertEqual(try names("opened<2d"), ["small.mp4", "inner.bin", "clone.dat"])
        XCTAssertEqual(try names("opened>5d kind:video"), ["Big.MOV"])
    }

    func testNamesExtKindAndBareWords() throws {
        XCTAssertEqual(try names("ext:mov,mp4"), ["Big.MOV", "small.mp4"])
        XCTAssertEqual(try names("ext:.png"), ["a.png"])
        XCTAssertEqual(try names("kind:image"), ["a.png"])
        XCTAssertEqual(try names("name:SMALL"), ["small.mp4"])
        XCTAssertEqual(try names("big"), ["Big.MOV"])
        XCTAssertEqual(try names("movies"), ["Big.MOV", "small.mp4"])
        XCTAssertEqual(try names("path:pictures -ext:png"), ["inner.bin"])
        XCTAssertEqual(try names("movies/big"), ["Big.MOV"])
        XCTAssertEqual(try names("\"thing.app\""), ["inner.bin"])
    }

    func testFlagsAndInheritance() throws {
        XCTAssertEqual(try names("is:package"), ["inner.bin"])
        XCTAssertEqual(try names("is:dataless"), ["inner.bin"])
        XCTAssertEqual(try names("is:clone"), ["clone.dat"])
        XCTAssertEqual(try names("-is:package ext:bin"), [])
        XCTAssertEqual(try names("is:dir").count, 5)
    }

    func testMarkAndSafety() throws {
        var decisions = [UInt8](repeating: 0, count: tree.count)
        var safety = [UInt8](repeating: 0, count: tree.count)
        let big = Int(tree.find(path: "/Users/demo/Movies/Big.MOV")!)
        decisions[big] = Decision.remove.rawValue
        safety[big] = SafetyTier.safe.rawValue
        let context = QueryContext(decisions: decisions, safety: safety, now: now)
        XCTAssertEqual(try names("mark:remove", context: context), ["Big.MOV"])
        XCTAssertEqual(try names("safe:safe", context: context), ["Big.MOV"])
        XCTAssertEqual(try names("mark:none kind:video", context: context), ["small.mp4"])
        XCTAssertEqual(try names("mark:remove", context: QueryContext(now: now)), [])
    }

    func testOnlyLeavesAreSetAndLensTotalsAgree() throws {
        let query = Query.parse("ext:png")
        let flags = try XCTUnwrap(QueryEngine.matches(query, tree: tree, context: QueryContext(now: now), isCancelled: { false }))
        XCTAssertFalse(flags[0])
        let lens = TreeLens(tree: tree, matches: flags)
        XCTAssertEqual(lens.size[0], 3 * megabyte)
    }

    func testCancellationReturnsNil() {
        let big = SyntheticTree.make(scale: 2)
        XCTAssertNil(QueryEngine.matches(Query.parse("size>1"), tree: big, context: QueryContext(), isCancelled: { true }))
    }
}

import DYCore
import XCTest
@testable import DYAnalysis

/// Budgets from the contract, enforced only in optimised builds. Run with `swift test -c release`.
final class PerformanceTests: XCTestCase {
    func milliseconds(_ body: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
    }

    func testBudgetsOnFiveMillionNodes() throws {
        #if DEBUG
        throw XCTSkip("Budgets are measured in release builds")
        #else
        let tree = SyntheticTree.make(scale: 100)
        XCTAssertGreaterThan(tree.count, 4_000_000)
        let lens = TreeLens(tree: tree)
        let context = QueryContext(now: SyntheticTree.referenceNow)
        let query = Query.parse("size>1mb age>1y kind:video -path:Photos ext:mov,mp4,mkv is:clone")

        var best = Double.infinity
        for _ in 0..<3 { best = min(best, milliseconds { _ = QueryEngine.matches(query, tree: tree, context: context, isCancelled: { false }) }) }
        print("PERF nodes=\(tree.count) query_ms=\(best)")
        XCTAssertLessThan(best, 150)

        let words = Query.parse("storefront size>10")
        best = .infinity
        for _ in 0..<3 { best = min(best, milliseconds { _ = QueryEngine.matches(words, tree: tree, context: context, isCancelled: { false }) }) }
        print("PERF bare_word_query_ms=\(best)")
        XCTAssertLessThan(best, 150)

        var ignoreBest = Double.infinity
        for _ in 0..<3 { ignoreBest = min(ignoreBest, milliseconds { _ = IgnoreEngine.evaluate(.defaults, tree: tree, home: "/Users/demo", isCancelled: { false }) }) }
        print("PERF ignore_ms=\(ignoreBest)")

        let total = lens.size[0]
        for divisor: UInt64 in [12, 100, 1_000, 4_000, 100_000] {
            for metric in [Metric.bytes, .files] {
                let threshold = lens.value(0, metric) / divisor
                var cutBest = Double.infinity
                var items = 0
                for _ in 0..<3 { cutBest = min(cutBest, milliseconds { items = ThingsEngine.cut(lens: lens, under: 0, threshold: threshold, metric: metric).items.count }) }
                print("PERF cut metric=\(metric) divisor=\(divisor) items=\(items) ms=\(cutBest)")
                XCTAssertLessThan(cutBest, 50)
            }
        }
        _ = total

        let spectrum = milliseconds { _ = SpectrumEngine.compute(lens: lens, under: 0) }
        let field = milliseconds { _ = FieldEngine.compute(lens: lens, under: 0, clock: .modified, maxPoints: 50_000) }
        print("PERF spectrum_ms=\(spectrum) field_ms=\(field)")
        #endif
    }
}

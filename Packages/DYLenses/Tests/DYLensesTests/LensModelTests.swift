import DYAdvisor
import DYAnalysis
import DYCore
import XCTest
@testable import DYLenses

final class LensModelTests: XCTestCase {
    private let lens = TreeLens(tree: SyntheticTree.make(scale: 0.05))

    /// A real bin from the sample disk with its edges replaced, because the engine's initialisers are internal.
    private func bin(_ lower: UInt64, _ upper: UInt64) -> SpectrumBin {
        var result = SpectrumEngine.compute(lens: lens, under: 0).bins[0]
        result.lower = lower
        result.upper = upper
        return result
    }

    func testDetailSliderRoundTripsAndStaysInRange() {
        XCTAssertEqual(ThingsDetail.target(forPosition: 0), 6)
        XCTAssertEqual(ThingsDetail.target(forPosition: 1), 3000)
        XCTAssertEqual(ThingsDetail.target(forPosition: -4), 6)
        for target in [6, 48, 400, 3000] {
            XCTAssertEqual(ThingsDetail.target(forPosition: ThingsDetail.position(forTarget: target)), target)
        }
        let ticks = (0...20).map { ThingsDetail.target(forPosition: Double($0) / 20) }
        XCTAssertEqual(ticks, ticks.sorted())
    }

    func testThingsSummaryHeadlineAndEightyPercent() {
        let metric = Metric.bytes
        let threshold = ThingsEngine.thresholdForApproximately(items: 20, lens: lens, under: 0, metric: metric)
        let result = ThingsEngine.cut(lens: lens, under: 0, threshold: threshold, metric: metric)
        let summary = ThingsSummary(result: result, metric: metric)
        XCTAssertEqual(summary.title, "\(Format.bytes(result.total)) as \(result.items.count) things")
        XCTAssertEqual(summary.cumulative.count, result.items.count)
        XCTAssertEqual(summary.cumulative.last ?? 0, 1, accuracy: 1e-9)
        XCTAssertEqual(summary.cumulative, summary.cumulative.sorted())
        XCTAssertGreaterThan(summary.countFor80, 0)
        XCTAssertGreaterThanOrEqual(summary.cumulative[summary.countFor80 - 1], 0.8)
        if summary.countFor80 > 1 { XCTAssertLessThan(summary.cumulative[summary.countFor80 - 2], 0.8) }
        XCTAssertTrue(summary.subtitle.hasPrefix("The largest \(summary.countFor80) hold 80%"))
    }

    func testSpectrumHeadlineIsComputedFromTheData() {
        let result = SpectrumEngine.compute(lens: lens, under: 0)
        let headline = SpectrumModel.headline(result)
        let small = result.bins.filter { $0.upper <= 1_000_000 }
        XCTAssertTrue(headline.title.contains(Format.percent(small.reduce(0) { $0 + $1.count }, of: result.totalFiles)))
        XCTAssertTrue(headline.subtitle.contains(Format.bytes(small.reduce(0) { $0 + $1.bytes })))
        XCTAssertFalse(SpectrumModel.presentKinds(result).isEmpty)
    }

    /// A filter can leave only big files, and the headline must not read "0% of your files use only 0%".
    func testSpectrumHeadlineWithNoSmallFiles() {
        var matches = [Bool](repeating: false, count: lens.tree.count)
        for index in 0..<lens.tree.count where !lens.tree.isDirectory(NodeID(index)) && lens.tree.allocated(NodeID(index)) > 1_000_000_000 { matches[index] = true }
        let result = SpectrumEngine.compute(lens: TreeLens(tree: lens.tree, matches: matches), under: 0)
        XCTAssertGreaterThan(result.totalFiles, 0)
        XCTAssertTrue(SpectrumModel.headline(result).title.hasPrefix("All \(Format.count(result.totalFiles)) files here"))
    }

    func testSpectrumSizeTermsAreExactAndReplaceEachOther() {
        XCTAssertEqual(SpectrumModel.sizeToken(20_000_000), "20mb")
        XCTAssertEqual(SpectrumModel.sizeToken(1_000), "1kb")
        XCTAssertEqual(SpectrumModel.sizeToken(500), "500")
        let first = SpectrumModel.query("kind:video", selecting: bin(1_000_000, 2_000_000))
        XCTAssertEqual(first, "kind:video size>1mb size<2mb")
        let second = SpectrumModel.query(first, selecting: bin(5_000_000, 10_000_000))
        XCTAssertEqual(second, "kind:video size>5mb size<10mb")
        XCTAssertEqual(SpectrumModel.query(second, selecting: bin(5_000_000, 10_000_000)), "kind:video", "clicking again clears")
        XCTAssertEqual(SpectrumModel.query("", selecting: bin(0, 1_000)), "size<1kb")
        XCTAssertTrue(SpectrumModel.hasSizeTerms(second))
        XCTAssertEqual(SpectrumModel.clearingSize(second), "kind:video")
    }

    func testBrowseColumnsFollowTheSelection() {
        let tree = SyntheticTree.make(scale: 0.05)
        let home = tree.find(path: "/Users/demo")!
        let movies = tree.find(path: "/Users/demo/Movies")!
        XCTAssertEqual(BrowseModel.columnParents(tree: tree, focus: 0, selected: nil), [0])
        XCTAssertEqual(BrowseModel.columnParents(tree: tree, focus: 0, selected: movies), [0, tree.parent(home), home, movies])
        let file = tree.children(movies).lowerBound
        let chain = BrowseModel.columnParents(tree: tree, focus: 0, selected: file)
        XCTAssertEqual(chain.last, tree.isDirectory(file) ? file : movies)
        XCTAssertEqual(BrowseModel.columnParents(tree: tree, focus: movies, selected: home), [movies], "selection outside the focus is ignored")
    }

    func testBrowseArrowKeysMoveThroughColumns() {
        let tree = SyntheticTree.make(scale: 0.05)
        let lens = TreeLens(tree: tree)
        let first = lens.visibleChildren(of: 0)
        XCTAssertEqual(BrowseModel.move(.down, from: nil, lens: lens, focus: 0), first.first)
        XCTAssertEqual(BrowseModel.move(.down, from: first[0], lens: lens, focus: 0), first[1])
        XCTAssertNil(BrowseModel.move(.up, from: first[0], lens: lens, focus: 0))
        let inside = BrowseModel.move(.right, from: first[0], lens: lens, focus: 0)
        XCTAssertNotNil(inside)
        XCTAssertEqual(tree.parent(inside!), first[0])
        XCTAssertNil(BrowseModel.move(.left, from: first[0], lens: lens, focus: 0), "no column to the left of the focus")
        XCTAssertEqual(BrowseModel.move(.left, from: inside, lens: lens, focus: 0), first[0])
    }

    func testReclaimWordingLabelsGuessesAndStaging() {
        XCTAssertNil(ReclaimModel.guessNote(guesses: 0, identified: 4))
        XCTAssertTrue(ReclaimModel.guessNote(guesses: 2, identified: 0)!.contains("a guess"))
        XCTAssertTrue(ReclaimModel.guessNote(guesses: 1, identified: 3)!.contains("The other 3 carry"))
        XCTAssertTrue(ReclaimModel.guessNote(guesses: 1, identified: 1)!.contains("The other one carries"))
        XCTAssertEqual(ReclaimModel.noAdviceBytes(total: 100, groups: []), 100)
        XCTAssertTrue(ReclaimModel.isStaged([1, 2], effective: [0, 2, 2]))
        XCTAssertFalse(ReclaimModel.isStaged([1, 2], effective: [0, 2, 1]))
        XCTAssertFalse(ReclaimModel.isStaged([], effective: [0]))
    }

    func testTierWordsAndDecisionWords() {
        XCTAssertEqual(TierPill.title(.safe), "Safe")
        XCTAssertEqual(TierPill.title(.rebuild), "Recoverable")
        XCTAssertEqual(TierPill.title(.review), "Look first")
        XCTAssertEqual(TierPill.title(.never), "Not offered")
        XCTAssertNil(TierPill.title(.unknown))
        XCTAssertEqual(DecisionTag.title(.remove), "Remove")
    }

    private func rule(_ tier: SafetyTier = .safe) -> ReclaimRule {
        ReclaimRule(id: "t", title: "T", pattern: "x", tier: tier, whatItIs: "", consequence: "")
    }

    /// A lens where only files under Movies pass, like a query would.
    private func moviesOnly() -> (tree: FileTree, lens: TreeLens, movies: NodeID, music: NodeID) {
        let tree = SyntheticTree.make(scale: 0.05)
        let movies = tree.find(path: "/Users/demo/Movies")!, music = tree.find(path: "/Users/demo/Music")!
        let matches = (0..<tree.count).map { tree.isAncestor(movies, of: Int32($0)) || Int32($0) == movies }
        return (tree, TreeLens(tree: tree, matches: matches), movies, music)
    }

    func testNarrowingAFamilyKeepsOnlyNodesInTheResultAndResumsFromTheLens() {
        let (tree, lens, movies, music) = moviesOnly()
        let family = ReclaimFamily(rule: rule(), nodes: [movies, music], bytes: tree.allocated(movies) + tree.allocated(music),
                                   reclaimable: UInt64.max, files: 99, newestModified: 5)
        let narrowed = ReclaimModel.narrow(family, lens: lens)
        XCTAssertEqual(narrowed?.nodes, [movies])
        XCTAssertEqual(narrowed?.bytes, lens.size[Int(movies)])
        XCTAssertEqual(narrowed?.files, UInt64(lens.files[Int(movies)]))
        XCTAssertEqual(narrowed?.reclaimable, lens.size[Int(movies)], "reclaimable never exceeds the narrowed bytes")
        XCTAssertEqual(narrowed?.newestModified, 5)
        XCTAssertNil(ReclaimModel.narrow(ReclaimFamily(rule: rule(), nodes: [music], bytes: 1, reclaimable: 1, files: 1, newestModified: 1), lens: lens))
    }

    func testNarrowingAWorklistDropsExcludedNodes() {
        let (_, lens, movies, music) = moviesOnly()
        let list = Worklist(kind: .forgotten, title: "A", why: "w", nodes: [music, movies], bytes: 10, files: 10)
        let narrowed = ReclaimModel.narrow(list, lens: lens)
        XCTAssertEqual(narrowed?.nodes, [movies])
        XCTAssertEqual(narrowed?.bytes, lens.size[Int(movies)])
        XCTAssertNil(ReclaimModel.narrow(Worklist(kind: .forgotten, title: "A", why: "w", nodes: [music], bytes: 1, files: 1), lens: lens))
    }

    func testPartialNoteOnlyAppearsWhenSmallerThanTheWhole() {
        XCTAssertEqual(ReclaimModel.partialNote(bytes: 12_600_000_000, full: 18_000_000_000), "12.6 GB in this result, of 18.0 GB")
        XCTAssertNil(ReclaimModel.partialNote(bytes: 5, full: 5))
        XCTAssertNil(ReclaimModel.partialNote(bytes: 5, full: nil))
    }
}

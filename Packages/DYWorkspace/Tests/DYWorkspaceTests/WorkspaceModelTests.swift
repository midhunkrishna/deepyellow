import DYAdvisor
import DYAnalysis
import DYCore
import DYDecide
import DYScan
import XCTest
@testable import DYWorkspace

@MainActor
final class WorkspaceModelTests: XCTestCase {
    private let home = DemoDisk.home

    // MARK: Analyses

    func testDemoRunsAnalysesInOrderAndRefinesKindsKeepingIds() async throws {
        let workspace = Workspace(environment: .demo(dataDirectory: makeTempDirectory(self)))
        workspace.open(.demo)
        await workspace.settle()
        for stage in [AnalysisStage.reclaim, .ownership, .kinds] { XCTAssertEqual(workspace.analysis[stage], .done, "\(stage)") }
        XCTAssertEqual(workspace.analysis[.duplicates], .idle)
        XCTAssertNotNil(workspace.reclaimReport)
        XCTAssertNotNil(workspace.ownershipReport)
        let mystery = workspace.node(DemoDisk.mystery)
        XCTAssertEqual(workspace.tree?.kind(mystery), .archive)
        XCTAssertEqual(workspace.tree?.count, workspace.lens?.tree.count)
        XCTAssertGreaterThan(workspace.kindRefinement?.refinedFiles ?? 0, 0)
    }

    func testDuplicatesStartOnlyOnRequest() async throws {
        let workspace = await openDemo(self)
        XCTAssertNil(workspace.duplicateReport)
        workspace.findDuplicates()
        await workspace.settle()
        XCTAssertEqual(workspace.analysis[.duplicates], .done)
        let sets = try XCTUnwrap(workspace.duplicateReport).sets
        XCTAssertGreaterThanOrEqual(sets.count, 3)
        XCTAssertTrue(workspace.worklists.contains { $0.kind == .duplicates })
    }

    func testWorklistsShowForgottenAndLeftovers() async {
        let workspace = await openDemo(self)
        let kinds = Set(workspace.worklists.map(\.kind))
        XCTAssertTrue(kinds.contains(.forgotten))
        XCTAssertTrue(kinds.contains(.leftovers))
        XCTAssertTrue(kinds.contains(.largestUndecided))
    }

    func testCancelledAnalysisIsReportedAsCancelled() async {
        let workspace = Workspace(environment: .demo(dataDirectory: makeTempDirectory(self)))
        workspace.open(.demo)
        await eventually("analysis to start") { workspace.analysis[.reclaim] != nil }
        workspace.cancelAnalyses()
        await workspace.settle()
        XCTAssertNotEqual(workspace.analysis[.reclaim], .running(fraction: nil))
    }

    // MARK: Selection

    func testSelectionCountsBytesOnceAndAllowsRoot() async {
        let workspace = await openDemo(self)
        let downloads = workspace.node(home + "/Downloads")
        let file = workspace.node(home + "/Downloads/Figma.dmg")
        workspace.click(downloads, additive: false)
        let folderBytes = workspace.selectionBytes
        workspace.click(file, additive: true)
        XCTAssertEqual(workspace.selectionCount, 2)
        XCTAssertEqual(workspace.selectionBytes, folderBytes, "a file inside a selected folder adds nothing")
        workspace.click(downloads, additive: false)
        workspace.click(downloads, additive: false)
        XCTAssertEqual(workspace.selectionCount, 0, "clicking the only selected node clears it")
        workspace.click(0, additive: false)
        XCTAssertEqual(workspace.selectionCount, 1)
        XCTAssertEqual(workspace.selectedNodes, [0])
    }

    func testSelectionSurvivesTreeSwapByPath() async {
        let workspace = await openDemo(self)
        workspace.click(workspace.node(home + "/Downloads/Figma.dmg"), additive: false)
        let bytes = workspace.selectionBytes
        workspace.open(.demo)
        XCTAssertEqual(workspace.selectionCount, 0, "a new source starts with no selection")
        await workspace.settle()
        workspace.select(paths: [home + "/Downloads/Figma.dmg"])
        XCTAssertEqual(workspace.selectionBytes, bytes)
    }

    func testHoverAndSelectionQueueNoBackgroundWork() async {
        let workspace = await openDemo(self)
        let epoch = workspace.taskEpoch
        workspace.hover = workspace.node(home + "/Movies")
        workspace.click(workspace.node(home + "/Movies"), additive: false)
        XCTAssertEqual(workspace.taskEpoch, epoch)
    }

    // MARK: Marks

    func testMarkNeedsSelectionAndUndoRedo() async {
        let workspace = await openDemo(self)
        XCTAssertFalse(workspace.mark(.remove))
        XCTAssertNotNil(workspace.notice)
        XCTAssertEqual(workspace.stagedBytes, 0, "nothing is ever pre-marked")
        let file = workspace.node(home + "/Downloads/old-backup.zip")
        workspace.click(file, additive: false)
        XCTAssertTrue(workspace.mark(.remove))
        await workspace.settle()
        XCTAssertEqual(workspace.resolved?.effective[Int(file)], Decision.remove.rawValue)
        XCTAssertGreaterThan(workspace.stagedBytes, 0)
        XCTAssertTrue(workspace.undoDecision())
        await workspace.settle()
        XCTAssertEqual(workspace.resolved?.effective[Int(file)], 0)
        XCTAssertTrue(workspace.redoDecision())
        await workspace.settle()
        XCTAssertEqual(workspace.resolved?.effective[Int(file)], Decision.remove.rawValue)
    }

    func testDecisionsPersistUnderTheDataDirectory() async {
        let directory = makeTempDirectory(self)
        let first = await openDemo(self, dataDirectory: directory)
        let file = first.node(home + "/Downloads/old-backup.zip")
        first.click(file, additive: false)
        first.mark(.keep)
        await first.settle()
        let second = await openDemo(self, dataDirectory: directory)
        XCTAssertEqual(second.resolved?.effective[Int(second.node(home + "/Downloads/old-backup.zip"))], Decision.keep.rawValue)
    }

    // MARK: Plan

    func testRootIsSelectableButBlockedFromThePlan() async {
        let workspace = await openDemo(self)
        workspace.click(0, additive: false)
        workspace.mark(.remove)
        await workspace.settle()
        XCTAssertTrue(workspace.plan?.items.isEmpty ?? false)
        XCTAssertTrue(workspace.plan?.blocked.contains { $0.path == "/" } ?? false)
        XCTAssertFalse(workspace.canApply)
    }

    func testEstimateSaysAtLeastOnlyWhenItIsAFloor() async {
        let workspace = await openDemo(self)
        let docker = workspace.node(home + "/Library/Containers/com.docker.docker/Data/Docker.raw")
        workspace.click(docker, additive: false)
        workspace.mark(.remove)
        await workspace.settle()
        XCTAssertTrue(workspace.planIsRefined)
        XCTAssertEqual(workspace.plan?.items.count, 1)
        XCTAssertEqual(workspace.plan?.estimateIsLowerBound, true)
        XCTAssertTrue(workspace.planEstimateText.hasPrefix("frees at least"))

        workspace.undoDecision()
        workspace.click(workspace.node(home + "/Downloads/old-backup.zip"), additive: false)
        workspace.mark(.remove)
        await workspace.settle()
        XCTAssertEqual(workspace.plan?.estimateIsLowerBound, false)
        XCTAssertTrue(workspace.planEstimateText.hasPrefix("frees "))
        XCTAssertFalse(workspace.planEstimateText.contains("at least"))
    }

    func testStagedPlanIsCancelledAndReplacedByNewerOne() async {
        let workspace = await openDemo(self)
        workspace.click(workspace.node(home + "/Downloads/old-backup.zip"), additive: false)
        workspace.mark(.remove)
        workspace.click(workspace.node(home + "/Downloads/Figma.dmg"), additive: false)
        workspace.mark(.remove)
        await workspace.settle()
        XCTAssertEqual(workspace.plan?.items.count, 2)
    }

    // MARK: Query, rules, ledger

    func testQueryFiltersOffMainAndShowsInLedger() async {
        let workspace = await openDemo(self)
        let before = workspace.reconciliation
        XCTAssertEqual(before?.filteredBytes, 0)
        workspace.setQuery("kind:video")
        workspace.setQuery("ext:pdf")
        await workspace.settle()
        XCTAssertEqual(workspace.query.text, "ext:pdf")
        let after = workspace.reconciliation
        XCTAssertLessThan(after?.visibleBytes ?? .max, before?.visibleBytes ?? 0)
        XCTAssertGreaterThan(after?.filteredBytes ?? 0, 0)
    }

    func testLedgerAddsUp() async {
        let workspace = await openDemo(self)
        let ledger = try! XCTUnwrap(workspace.reconciliation)
        XCTAssertEqual(ledger.visibleBytes + ledger.hiddenBytes + ledger.filteredBytes + ledger.removedThisSessionBytes, ledger.scannedBytes)
        XCTAssertTrue(ledger.usesSampleValues)
        XCTAssertEqual(ledger.volumeAvailable, 88_000_000_000)
        XCTAssertNotNil(ledger.remainderBytes)
        XCTAssertGreaterThan(ledger.hiddenBytes, 0, "the default rules hide .DS_Store files")
        XCTAssertEqual(ledger.hiddenByRule.reduce(0) { $0 + $1.bytes }, ledger.hiddenBytes)
    }

    func testLedgerNeverInventsVolumeNumbers() async {
        let tree = SyntheticTree.make(scale: 0.05)
        let workspace = Workspace(environment: plainEnvironment(directory: makeTempDirectory(self), scan: finishedScan(tree)))
        workspace.open(.path("/"))
        await workspace.settle()
        let ledger = try! XCTUnwrap(workspace.reconciliation)
        XCTAssertNil(ledger.volumeTotal)
        XCTAssertNil(ledger.volumeAvailable)
        XCTAssertNil(ledger.remainderBytes)
        XCTAssertFalse(ledger.usesSampleValues)
        XCTAssertEqual(ledger.hardlinkBytesSaved, tree.meta.hardlinkBytesSaved)
    }

    func testHideAddsRuleCountsInLedgerPersistsAndUndoes() async {
        let directory = makeTempDirectory(self)
        let workspace = await openDemo(self, dataDirectory: directory)
        let hiddenBefore = workspace.reconciliation?.hiddenBytes ?? 0
        workspace.hide(.ext, nodes: [workspace.node(home + "/Downloads/Figma.dmg")])
        await workspace.settle()
        XCTAssertGreaterThan(workspace.reconciliation?.hiddenBytes ?? 0, hiddenBefore)
        XCTAssertTrue(workspace.ignoreRules.rules.contains { $0.pattern == "*.dmg" })
        let reloaded = await openDemo(self, dataDirectory: directory)
        XCTAssertTrue(reloaded.ignoreRules.rules.contains { $0.pattern == "*.dmg" })
        workspace.undoNotice()
        await workspace.settle()
        XCTAssertEqual(workspace.reconciliation?.hiddenBytes, hiddenBefore)
    }

    // MARK: Views, focus, preview

    func testThingsSpectrumAndFieldComputeForTheActiveLens() async {
        let workspace = await openDemo(self)
        workspace.setLens(.things)
        await workspace.settle()
        let things = workspace.things
        XCTAssertFalse(things?.items.isEmpty ?? true)
        XCTAssertEqual(things?.items.reduce(0) { $0 + $1.value }, things?.total)
        workspace.setLens(.spectrum)
        workspace.setLens(.field)
        await workspace.settle()
        XCTAssertNil(workspace.spectrum, "only the active lens is computed")
        XCTAssertFalse(workspace.field?.nodes.isEmpty ?? true)
        workspace.setLens(.spectrum)
        await workspace.settle()
        XCTAssertGreaterThan(workspace.spectrum?.totalFiles ?? 0, 0)
    }

    func testFocusZoomAndBreadcrumb() async {
        let workspace = await openDemo(self)
        let movies = workspace.node(home + "/Movies")
        workspace.zoomIn(movies)
        XCTAssertEqual(workspace.focus, movies)
        XCTAssertEqual(workspace.breadcrumb.last, movies)
        workspace.zoomIn(workspace.node(home + "/Downloads/Figma.dmg"))
        XCTAssertEqual(workspace.focus, movies, "files can't be zoomed into")
        XCTAssertTrue(workspace.zoomOut())
        XCTAssertEqual(workspace.focus, workspace.node(home))
    }

    func testPreviewItemCarriesLargestChildrenAndFlags() async {
        let workspace = await openDemo(self)
        let item = workspace.previewItem(for: workspace.node(home + "/Movies"))
        XCTAssertEqual(item?.isDirectory, true)
        XCTAssertEqual(item?.largestChildren.first?.name, "wedding-final-master.mov")
        workspace.click(workspace.node(home + "/Downloads/Figma.dmg"), additive: false)
        XCTAssertEqual(workspace.selectionPreview?.name, "Figma.dmg")
        XCTAssertEqual(workspace.selectionPreview?.isDataless, false)
    }

    func testNodeStyleCarriesDecisionsAndSafety() async {
        let workspace = await openDemo(self)
        let style = workspace.nodeStyle
        XCTAssertEqual(style.decisions.count, workspace.tree?.count)
        XCTAssertEqual(style.safety.count, workspace.tree?.count)
        XCTAssertEqual(style.dominantKind.count, workspace.tree?.count)
        workspace.setColorMode(.safety)
        XCTAssertTrue(workspace.nodeStyle.dominantKind.isEmpty)
    }

    // MARK: Scan lifecycle and cache

    func testScanLifecycleReportsProgressAndFinishes() async {
        let tree = SyntheticTree.make(scale: 0.05)
        let workspace = Workspace(environment: plainEnvironment(directory: makeTempDirectory(self), scan: finishedScan(tree)))
        workspace.open(.path("/"))
        await workspace.settle()
        XCTAssertEqual(workspace.scanPhase, .finished)
        XCTAssertEqual(workspace.scanProgress?.files, 10)
        XCTAssertFalse(workspace.isLiveSnapshot)
        XCTAssertTrue(workspace.tree === workspace.lens?.tree || workspace.tree?.count == tree.count)
    }

    func testSnapshotsKeepSelectionAndFinishedScanIsCached() async throws {
        let full = SyntheticTree.make(scale: 0.05)
        let (stream, continuation) = AsyncStream<ScanEvent>.makeStream()
        let directory = makeTempDirectory(self)
        let workspace = Workspace(environment: plainEnvironment(directory: directory) { _ in ScanHandle(events: stream, cancel: {}) })
        workspace.open(.path("/"))
        workspace.select(paths: [home + "/Downloads"])
        continuation.yield(.snapshot(full))
        await eventually("snapshot") { workspace.isLiveSnapshot }
        XCTAssertEqual(workspace.selectionCount, 1)
        continuation.yield(.finished(full))
        continuation.finish()
        await workspace.settle()
        XCTAssertFalse(workspace.isLiveSnapshot)
        XCTAssertEqual(workspace.selectionCount, 1)
        let cached = try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("scans").path)
        XCTAssertEqual(cached.filter { $0.hasSuffix(".dyscan") }.count, 1)
    }

    func testCachedScanOpensBeforeTheRescanFinishes() async throws {
        let full = SyntheticTree.make(scale: 0.05)
        let directory = makeTempDirectory(self)
        let first = Workspace(environment: plainEnvironment(directory: directory, scan: finishedScan(full)))
        first.open(.path("/"))
        await first.settle()

        let (stream, continuation) = AsyncStream<ScanEvent>.makeStream()
        let second = Workspace(environment: plainEnvironment(directory: directory) { _ in
            ScanHandle(events: stream, cancel: { continuation.finish() })
        })
        second.open(.path("/"))
        await eventually("cached tree") { second.isShowingCachedScan && second.tree != nil }
        XCTAssertNotNil(second.cachedScanAge)
        XCTAssertEqual(second.tree?.count, full.count)
        second.cancelScan()
        await second.settle()
        XCTAssertTrue(second.scanWasCancelled)
        XCTAssertEqual(second.tree?.count, full.count, "a cancelled rescan keeps the cached scan")
    }

    // MARK: Environment

    func testDataDirectoryHonoursDeepYellowHome() {
        XCTAssertEqual(WorkspaceEnvironment.defaultDataDirectory(environment: ["DEEPYELLOW_HOME": "/tmp/x"], home: "/Users/a").path, "/tmp/x")
        XCTAssertEqual(WorkspaceEnvironment.defaultDataDirectory(environment: [:], home: "/Users/a").path,
                       "/Users/a/Library/Application Support/DeepYellow")
    }

    func testWorkspaceSourcesNeverNameTheSystemTrash() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/DYWorkspace")
        let files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty)
        for file in files {
            XCTAssertFalse(try String(contentsOf: file, encoding: .utf8).contains("SystemTrash"), file.lastPathComponent)
        }
    }
}

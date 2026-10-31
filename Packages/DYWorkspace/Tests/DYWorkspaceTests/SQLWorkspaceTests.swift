import DYCore
import DYDecide
import DYScan
import DYSQL
import XCTest
@testable import DYWorkspace

@MainActor
final class SQLWorkspaceTests: XCTestCase {
    private let home = DemoDisk.home
    private let topFiles = "SELECT id FROM files ORDER BY size DESC LIMIT 5"

    /// Runs a statement and waits for the views to follow it.
    private func run(_ workspace: Workspace, _ sql: String) async {
        workspace.runSQL(sql)
        await workspace.settle()
    }

    /// What the lens totals at the root for a set of files: their sizes plus the own bytes of every directory above them.
    private func expectedRoot(_ workspace: Workspace, files: [NodeID]) -> UInt64 {
        let tree = workspace.tree!, base = workspace.baseLens!
        var total: UInt64 = 0
        var directories = Set<NodeID>()
        for file in files {
            total += base.size[Int(file)]
            var ancestor = tree.parent(file)
            while ancestor >= 0 { directories.insert(ancestor); ancestor = tree.parent(ancestor) }
        }
        for directory in directories {
            let children = tree.children(directory).reduce(UInt64(0)) { $0 + tree.allocated($1) }
            total += tree.allocated(directory) - children
        }
        return total
    }

    // MARK: The set drives the views

    func testNodesResultNarrowsTheLensAndEveryView() async throws {
        let workspace = await openDemo(self)
        await run(workspace, topFiles)
        XCTAssertEqual(workspace.sqlPhase, .finished)
        XCTAssertTrue(workspace.sqlIsFiltering)
        let result = try XCTUnwrap(workspace.sqlResult)
        XCTAssertTrue(result.tree === workspace.tree, "kind refinement keeps the result bound to the tree on screen")
        XCTAssertEqual(result.nodes.count, 5)
        XCTAssertEqual(workspace.lens?.size[0], expectedRoot(workspace, files: result.nodes))
        XCTAssertLessThan(workspace.lens!.size[0], workspace.baseLens!.size[0])
        XCTAssertTrue(workspace.sqlFilterSummary?.hasPrefix("5 things · ") ?? false, workspace.sqlFilterSummary ?? "nil")

        workspace.setLens(.things)
        await workspace.settle()
        XCTAssertEqual(workspace.things?.total, workspace.lens?.size[0])
        workspace.setLens(.spectrum)
        await workspace.settle()
        XCTAssertEqual(workspace.spectrum?.totalFiles, 5)
        workspace.setLens(.field)
        await workspace.settle()
        XCTAssertEqual(workspace.field?.nodes.count, 5)
    }

    func testDirectoryRowIncludesItsWholeSubtree() async {
        let workspace = await openDemo(self)
        await run(workspace, "SELECT id FROM dirs WHERE path = '\(home)/Movies'")
        let movies = workspace.node(home + "/Movies")
        XCTAssertEqual(workspace.lens?.size[Int(movies)], workspace.baseLens?.size[Int(movies)])
        let nested = workspace.node(home + "/Movies/Exports/cut_v1.mp4")
        XCTAssertEqual(workspace.lens?.included[Int(nested)], true)
        XCTAssertEqual(workspace.lens?.included[Int(workspace.node(home + "/Downloads"))], false)
        XCTAssertEqual(workspace.sqlFilterSummary?.hasPrefix("1 thing · "), true)
    }

    /// The chip agrees with the table when a folder and its contents are both rows, and counts each byte once.
    func testFilterSummaryCountsRowsAndBytesOnce() async {
        let workspace = await openDemo(self)
        await run(workspace, "SELECT id FROM dirs WHERE path = '\(home)/Movies'")
        let folderOnly = workspace.lens!.size[0]
        await run(workspace, "SELECT id FROM nodes WHERE path = '\(home)/Movies' OR path = '\(home)/Movies/wedding-final-master.mov'")
        XCTAssertEqual(workspace.sqlResult?.rowCount, 2)
        XCTAssertEqual(workspace.sqlFilterSummary?.hasPrefix("2 things · "), true)
        XCTAssertEqual(workspace.lens!.size[0], folderOnly)
    }

    func testSQLIsAndedWithTheSlashQuery() async {
        let workspace = await openDemo(self)
        await run(workspace, "SELECT id FROM dirs WHERE path = '\(home)/Movies'")
        let sqlOnly = workspace.lens!.size[0]
        workspace.setQuery("ext:mp4")
        await workspace.settle()
        let both = workspace.lens!.size[0]
        XCTAssertGreaterThan(both, 0)
        XCTAssertLessThan(both, sqlOnly)
        XCTAssertEqual(workspace.lens?.included[Int(workspace.node(home + "/Movies/wedding-final-master.mov"))], false)
        XCTAssertEqual(workspace.lens?.included[Int(workspace.node(home + "/Movies/interview-raw.mp4"))], true)
        XCTAssertEqual(workspace.lens?.included[Int(workspace.node(home + "/Downloads/conference-talk.mp4"))], false, "outside the SQL set")
    }

    func testBaseLensIgnoresSQLAndTheLedgerStillReconciles() async throws {
        let workspace = await openDemo(self)
        let before = workspace.baseLens!.size[0]
        await run(workspace, topFiles)
        XCTAssertEqual(workspace.baseLens?.size[0], before)
        let ledger = try XCTUnwrap(workspace.reconciliation)
        XCTAssertEqual(ledger.visibleBytes + ledger.hiddenBytes + ledger.filteredBytes + ledger.removedThisSessionBytes, ledger.scannedBytes)
        XCTAssertGreaterThan(ledger.filteredBytes, 0)
    }

    // MARK: Groups

    func testGroupsUnionDrillAndBack() async throws {
        let workspace = await openDemo(self)
        await run(workspace, "SELECT kind, SUM(size) AS bytes, ids(id) AS ids FROM files GROUP BY kind ORDER BY bytes DESC")
        let result = try XCTUnwrap(workspace.sqlResult)
        XCTAssertEqual(result.shape, .groups)
        XCTAssertGreaterThan(result.rowCount, 2)
        XCTAssertEqual(workspace.sqlActiveNodes, result.nodes)
        let union = workspace.lens!.size[0]

        workspace.drillSQL(row: 1)
        await workspace.settle()
        XCTAssertEqual(workspace.sqlDrillRow, 1)
        XCTAssertEqual(workspace.sqlActiveNodes, result.rowGroup[1])
        XCTAssertLessThan(workspace.lens!.size[0], union)

        workspace.drillSQL(row: 9_999)
        XCTAssertEqual(workspace.sqlDrillRow, 1, "an unknown row is ignored")
        workspace.drillSQL(row: nil)
        await workspace.settle()
        XCTAssertNil(workspace.sqlDrillRow)
        XCTAssertEqual(workspace.lens?.size[0], union)
    }

    func testDrillSurvivesARerunWithTheSameRowCount() async {
        let workspace = await openDemo(self)
        await run(workspace, "SELECT kind, ids(id) AS ids FROM files GROUP BY kind")
        workspace.drillSQL(row: 0)
        await workspace.settle()
        workspace.click(workspace.node(home + "/Downloads/Figma.dmg"), additive: false)
        workspace.mark(.keep)
        await workspace.settle()
        XCTAssertEqual(workspace.sqlDrillRow, 0)
    }

    func testDrillIsIgnoredForNodeResults() async {
        let workspace = await openDemo(self)
        await run(workspace, topFiles)
        workspace.drillSQL(row: 0)
        XCTAssertNil(workspace.sqlDrillRow)
    }

    // MARK: Table-only, failure, clear, cancel

    func testTableOnlyClearsAnEarlierFilterAndLeavesViews() async {
        let workspace = await openDemo(self)
        workspace.setLens(.things)
        await run(workspace, topFiles)
        XCTAssertTrue(workspace.sqlIsFiltering)
        await run(workspace, "SELECT kind, COUNT(*) FROM files GROUP BY kind")
        XCTAssertEqual(workspace.sqlResult?.shape, .tableOnly)
        XCTAssertFalse(workspace.sqlIsFiltering)
        XCTAssertNil(workspace.sqlFilterSummary)
        XCTAssertEqual(workspace.lens?.size[0], workspace.baseLens?.size[0])
        XCTAssertEqual(workspace.lensKind, .things)
    }

    func testFailureKeepsThePreviousFilter() async {
        let workspace = await openDemo(self)
        await run(workspace, topFiles)
        let nodes = workspace.sqlResult?.nodes
        await run(workspace, "DELETE FROM nodes")
        guard case .failed(.refused) = workspace.sqlPhase else { return XCTFail("\(workspace.sqlPhase)") }
        XCTAssertTrue(workspace.sqlIsFiltering)
        XCTAssertEqual(workspace.sqlResult?.nodes, nodes)
        await run(workspace, "SELEKT 1")
        guard case .failed(.invalid) = workspace.sqlPhase else { return XCTFail("\(workspace.sqlPhase)") }
        XCTAssertTrue(workspace.sqlIsFiltering)
    }

    func testClearReturnsViewsAndKeepsTextAndHistory() async {
        let workspace = await openDemo(self)
        let before = workspace.lens!.size[0]
        await run(workspace, topFiles)
        workspace.clearSQL()
        await workspace.settle()
        XCTAssertFalse(workspace.sqlIsFiltering)
        XCTAssertEqual(workspace.sqlPhase, .idle)
        XCTAssertNil(workspace.sqlResult)
        XCTAssertEqual(workspace.lens?.size[0], before)
        XCTAssertEqual(workspace.sqlText, topFiles)
        XCTAssertEqual(workspace.sqlHistory, [topFiles])
    }

    func testANewerRunCancelsAnOlderOne() async {
        let workspace = await openDemo(self)
        workspace.runSQL("SELECT id FROM files ORDER BY size DESC LIMIT 3")
        workspace.runSQL("SELECT id FROM files ORDER BY size DESC LIMIT 7")
        await workspace.settle()
        XCTAssertEqual(workspace.sqlText, "SELECT id FROM files ORDER BY size DESC LIMIT 7")
        XCTAssertEqual(workspace.sqlResult?.nodes.count, 7)
        XCTAssertEqual(workspace.sqlPhase, .finished)
    }

    func testCancelKeepsAnExistingResult() async {
        let workspace = await openDemo(self)
        await run(workspace, topFiles)
        workspace.runSQL("SELECT id FROM files")
        workspace.cancelSQL()
        await workspace.settle()
        XCTAssertNotEqual(workspace.sqlPhase, .running)
        XCTAssertEqual(workspace.sqlResult?.nodes.count, 5)
    }

    func testSQLWaitsForTheScanToFinish() async {
        let tree = SyntheticTree.make(scale: 0.05)
        let (stream, continuation) = AsyncStream<ScanEvent>.makeStream()
        let workspace = Workspace(environment: plainEnvironment(directory: makeTempDirectory(self)) { _ in
            ScanHandle(events: stream, cancel: { continuation.finish() })
        })
        workspace.open(.path("/"))
        continuation.yield(.snapshot(tree))
        await eventually("snapshot") { workspace.isLiveSnapshot }
        workspace.runSQL(topFiles)
        XCTAssertEqual(workspace.sqlPhase, .failed(.invalid(message: "SQL is available when the scan finishes.")))
        continuation.yield(.finished(tree))
        continuation.finish()
        await workspace.settle()
        XCTAssertFalse(workspace.sqlIsFiltering)
    }

    // MARK: A result stays true

    func testRerunsAfterADecisionChange() async {
        let workspace = await openDemo(self)
        await run(workspace, "SELECT id FROM files WHERE mark = 'remove'")
        XCTAssertEqual(workspace.sqlResult?.nodes, [])
        let file = workspace.node(home + "/Downloads/old-backup.zip")
        workspace.click(file, additive: false)
        workspace.mark(.remove)
        await workspace.settle()
        XCTAssertEqual(workspace.sqlResult?.nodes, [file])
        XCTAssertEqual(workspace.sqlPhase, .finished)
        XCTAssertTrue(workspace.sqlIsFiltering)
        workspace.undoDecision()
        await workspace.settle()
        XCTAssertEqual(workspace.sqlResult?.nodes, [])
    }

    func testRerunsAfterAHideRule() async {
        let workspace = await openDemo(self)
        await run(workspace, "SELECT id FROM files WHERE ext = 'dmg'")
        XCTAssertEqual(workspace.sqlResult?.nodes.count, 1)
        workspace.hide(.ext, nodes: [workspace.node(home + "/Downloads/Figma.dmg")])
        await workspace.settle()
        XCTAssertEqual(workspace.sqlResult?.nodes.count, 0, "hidden files are not visible to the next run")
    }

    func testRerunsAfterDemoApplyAndUndoAndNeverCallsTheMover() async throws {
        let workspace = await openDemo(self)
        let trash = try XCTUnwrap(workspace.environment.mover as? DemoTrash)
        let path = home + "/Downloads/old-backup.zip"
        await run(workspace, "SELECT id FROM files WHERE visible = 1 AND path = '\(path)'")
        XCTAssertEqual(workspace.sqlResult?.nodes.count, 1)
        XCTAssertTrue(trash.calls.isEmpty, "SQL alone never moves anything")
        XCTAssertEqual(workspace.stagedBytes, 0)
        XCTAssertEqual(workspace.resolved?.removeRoots, 0)

        workspace.click(workspace.node(path), additive: false)
        workspace.mark(.remove)
        await workspace.settle()
        _ = await workspace.applyPlan()
        await workspace.settle()
        XCTAssertEqual(workspace.sqlResult?.nodes.count, 0, "a file in the Trash is not visible")
        XCTAssertEqual(trash.calls.count, 1)
        _ = await workspace.undoApply()
        await workspace.settle()
        XCTAssertEqual(workspace.sqlResult?.nodes.count, 1)
        XCTAssertEqual(trash.calls.count, 2, "only the Apply and its Undo reached the mover")
    }

    func testASetNeverAppliesToADifferentTree() async {
        let workspace = await openDemo(self)
        await run(workspace, topFiles)
        XCTAssertTrue(workspace.sqlIsFiltering)
        workspace.adopt(SyntheticTree.make(scale: 0.05))
        XCTAssertFalse(workspace.sqlIsFiltering, "dropped until the re-run lands")
        XCTAssertNil(workspace.sqlActiveNodes)
        await workspace.settle()
        XCTAssertTrue(workspace.sqlIsFiltering)
        XCTAssertTrue(workspace.sqlResult?.tree === workspace.tree)
        XCTAssertEqual(workspace.sqlResult?.nodes.count, 5)
    }

    // MARK: Selection, review, history

    func testSelectAndReviewTakeTheCurrentSet() async {
        let workspace = await openDemo(self)
        await run(workspace, topFiles)
        workspace.selectSQLResults()
        XCTAssertEqual(workspace.selectionCount, 5)
        XCTAssertEqual(Set(workspace.selectedNodes), Set(workspace.sqlResult!.nodes))
        workspace.reviewSQLResults()
        XCTAssertEqual(workspace.review?.items.count, 5)
        XCTAssertEqual(workspace.review?.title, "SQL results")
        XCTAssertEqual(workspace.stagedBytes, 0, "SQL marks nothing")
    }

    func testHistoryIsNewestFirstDeduplicatedCappedAndPersisted() async {
        let directory = makeTempDirectory(self)
        let workspace = await openDemo(self, dataDirectory: directory)
        for limit in 1...22 { workspace.runSQL("SELECT id FROM files LIMIT \(limit)") }
        workspace.runSQL("SELECT id FROM files LIMIT 10")
        await workspace.settle()
        XCTAssertEqual(workspace.sqlHistory.count, 20)
        XCTAssertEqual(workspace.sqlHistory.first, "SELECT id FROM files LIMIT 10")
        XCTAssertEqual(Set(workspace.sqlHistory).count, 20)
        XCTAssertFalse(workspace.sqlHistory.contains("SELECT id FROM files LIMIT 1"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("sql-history.json").path))
        let reloaded = Workspace(environment: .demo(dataDirectory: directory))
        XCTAssertEqual(reloaded.sqlHistory, workspace.sqlHistory)
    }
}

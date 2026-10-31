import DYAdvisor
import DYCore
import DYDecide
import XCTest
@testable import DYWorkspace

@MainActor
final class ReviewAndTrashTests: XCTestCase {
    private let home = DemoDisk.home

    private func downloads(_ workspace: Workspace, _ names: [String]) -> [NodeID] { names.map { workspace.node(home + "/Downloads/" + $0) } }

    // MARK: Review

    func testReviewFromSelectionAdvancesStagesAndUndoesStepBack() async {
        let workspace = await openDemo(self)
        let nodes = downloads(workspace, ["old-backup.zip", "Figma.dmg", "Ubuntu-24.04.iso"])
        workspace.select(nodes)
        let started = await workspace.startReview()
        XCTAssertTrue(started)
        XCTAssertEqual(workspace.review?.items.count, 3)
        let first = workspace.review?.current?.path
        workspace.reviewVerdict(.remove)
        workspace.mark(.keep)
        XCTAssertEqual(workspace.review?.index, 2)
        XCTAssertEqual(workspace.review?.tally.left, 1)
        await workspace.settle()
        XCTAssertEqual(workspace.resolved?.effective[Int(workspace.node(first!))], Decision.remove.rawValue)
        XCTAssertTrue(workspace.undoDecision())
        XCTAssertEqual(workspace.review?.index, 1)
        workspace.reviewVerdict(.later)
        workspace.reviewVerdict(.keep)
        XCTAssertTrue(workspace.review?.isFinished ?? false)
        XCTAssertNil(workspace.reviewPreview)
    }

    func testReviewMarksOnlyTheCurrentItemNotTheSelection() async {
        let workspace = await openDemo(self)
        let nodes = downloads(workspace, ["old-backup.zip", "Figma.dmg"])
        workspace.select(nodes)
        await workspace.startReview()
        workspace.mark(.remove)
        await workspace.settle()
        let decided = nodes.filter { workspace.resolved?.effective[Int($0)] == Decision.remove.rawValue }
        XCTAssertEqual(decided.count, 1)
    }

    func testReviewCanBeSeededFromAFamilyAndAWorklist() async {
        let workspace = await openDemo(self)
        let family = try! XCTUnwrap(workspace.reclaimReport?.families.first)
        XCTAssertTrue(workspace.startReview(family: family))
        XCTAssertEqual(workspace.review?.title, family.rule.title)
        let list = try! XCTUnwrap(workspace.worklists.first)
        XCTAssertTrue(workspace.startReview(worklist: list))
        XCTAssertEqual(workspace.review?.items.count, list.nodes.count)
        workspace.endReview()
        XCTAssertNil(workspace.review)
    }

    func testDefaultReviewTakesLargestUndecidedFiles() async {
        let workspace = await openDemo(self)
        let started = await workspace.startReview()
        XCTAssertTrue(started)
        let items = workspace.review?.items ?? []
        XCTAssertEqual(items.count, 18)
        XCTAssertEqual(items.map(\.bytes), items.map(\.bytes).sorted(by: >))
        XCTAssertEqual(workspace.review?.title, "Largest undecided files")
    }

    func testReviewUpcomingPreviewsLookAhead() async {
        let workspace = await openDemo(self)
        workspace.select(downloads(workspace, ["old-backup.zip", "Figma.dmg", "Ubuntu-24.04.iso"]))
        await workspace.startReview()
        XCTAssertEqual(workspace.reviewUpcoming(count: 5).count, 2)
        XCTAssertNotNil(workspace.reviewPreview)
    }

    // MARK: Apply and undo on the demo disk

    func testDemoApplyAndUndoTouchNothingOnDisk() async throws {
        let sentinel = makeTempDirectory(self)
        let marker = sentinel.appendingPathComponent("marker.txt")
        try "unchanged".write(to: marker, atomically: true, encoding: .utf8)
        let before = try FileManager.default.contentsOfDirectory(atPath: sentinel.path)

        let workspace = await openDemo(self)
        let trash = try XCTUnwrap(workspace.environment.mover as? DemoTrash)
        let targets = downloads(workspace, ["old-backup.zip", "Figma.dmg"])
        workspace.select(targets)
        workspace.mark(.remove)
        await workspace.settle()
        XCTAssertTrue(workspace.canApply)
        let stagedPaths = Set(workspace.plan?.items.map(\.id) ?? [])
        let staged = workspace.stagedBytes

        let applied = await workspace.applyPlan()
        let report = try XCTUnwrap(applied)
        await workspace.settle()
        XCTAssertEqual(Set(report.moved.map(\.original)), stagedPaths)
        XCTAssertEqual(workspace.trashedPaths, stagedPaths)
        XCTAssertEqual(workspace.reconciliation?.removedThisSessionBytes, staged)
        XCTAssertEqual(workspace.stagedBytes, 0, "applied marks are cleared")
        XCTAssertTrue(workspace.canUndoApply)
        XCTAssertEqual(Set(trash.calls.compactMap { if case .moveToTrash(let path) = $0 { path } else { nil } }), stagedPaths)
        XCTAssertTrue(workspace.notice?.canUndo ?? false)

        let reverted = await workspace.undoApply()
        let undone = try XCTUnwrap(reverted)
        await workspace.settle()
        XCTAssertEqual(Set(undone.moved.map(\.original)), stagedPaths)
        XCTAssertTrue(workspace.trashedPaths.isEmpty)
        XCTAssertEqual(workspace.reconciliation?.removedThisSessionBytes, 0)
        XCTAssertEqual(workspace.stagedBytes, staged, "undo restores the staged marks")
        XCTAssertEqual(Set(trash.calls.compactMap { if case .moveBack(_, let to) = $0 { to } else { nil } }), stagedPaths)

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: sentinel.path), before)
        XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), "unchanged")
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.environment.dataDirectory.appendingPathComponent("trash-journal.json").path))
    }

    func testApplyIsRefusedWithoutSafetyAdvice() async {
        let workspace = Workspace(environment: .demo(dataDirectory: makeTempDirectory(self)))
        XCTAssertFalse(workspace.canApply)
        let report = await workspace.applyPlan()
        XCTAssertNil(report)
    }
}

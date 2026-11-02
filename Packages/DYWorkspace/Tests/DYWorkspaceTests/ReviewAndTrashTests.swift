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

    func testReviewFromSelectionStagesMovesAndUndoesStepBack() async {
        let workspace = await openDemo(self)
        let nodes = downloads(workspace, ["old-backup.zip", "Figma.dmg", "Ubuntu-24.04.iso"])
        workspace.select(nodes)
        let started = await workspace.startReview()
        XCTAssertTrue(started)
        XCTAssertEqual(workspace.review?.items.count, 3)
        let first = workspace.review?.current?.path
        workspace.reviewVerdict(.remove)
        XCTAssertEqual(workspace.review?.index, 0, "a mark stays on the item")
        workspace.reviewMove(by: 1)
        workspace.mark(.keep)
        XCTAssertEqual(workspace.review?.index, 1)
        XCTAssertEqual(workspace.reviewTally.left, 1)
        workspace.reviewMove(by: 1)
        await workspace.settle()
        XCTAssertEqual(workspace.resolved?.effective[Int(workspace.node(first!))], Decision.remove.rawValue)
        XCTAssertTrue(workspace.undoDecision())
        XCTAssertEqual(workspace.review?.index, 1, "undo goes back to the item it changed")
        XCTAssertTrue(workspace.redoDecision())
        XCTAssertEqual(workspace.review?.verdicts[workspace.review?.current?.path ?? ""], .keep)
        workspace.reviewMove(by: 1)
        XCTAssertEqual(workspace.review?.index, 2)
        workspace.reviewMove(by: 1)
        XCTAssertEqual(workspace.review?.index, 2, "the last item stays put")
        XCTAssertNotNil(workspace.reviewPreview)
    }

    func testPressingAMarkTwiceNeedsOneUndo() async {
        let workspace = await openDemo(self)
        workspace.select(downloads(workspace, ["old-backup.zip", "Figma.dmg"]))
        await workspace.startReview()
        let path = try! XCTUnwrap(workspace.review?.current?.path)
        workspace.reviewVerdict(.remove)
        workspace.reviewVerdict(.remove)
        XCTAssertTrue(workspace.undoDecision())
        XCTAssertNil(workspace.review?.verdicts[path])
        XCTAssertFalse(workspace.undoDecision())
    }

    func testAFolderOpensOnItsContentsAndPacksStayWhole() async throws {
        let workspace = await openDemo(self)
        let folder = workspace.node(home + "/Downloads")
        workspace.select([folder])
        let started = await workspace.startReview()
        XCTAssertTrue(started)
        let session = try XCTUnwrap(workspace.review)
        XCTAssertEqual(session.title, "Downloads")
        XCTAssertEqual(session.depth, 0)
        XCTAssertEqual(session.items.map(\.node), workspace.lens?.visibleChildren(of: folder, metric: workspace.metric))
        XCTAssertEqual(session.index, 0)
    }

    func testGoingInMarkingAndComingBackUp() async throws {
        let workspace = await openDemo(self)
        workspace.select([workspace.node(home)])
        await workspace.startReview()
        let folderIndex = try XCTUnwrap(workspace.review?.items.firstIndex(where: \.canGoIn))
        workspace.reviewGo(to: folderIndex)
        let folder = try XCTUnwrap(workspace.review?.current)

        XCTAssertTrue(workspace.reviewEnter())
        XCTAssertEqual(workspace.review?.depth, 1)
        XCTAssertEqual(workspace.review?.index, 0, "going in starts on the first item")
        XCTAssertEqual(workspace.review?.trail.last, folder.name)
        let first = try XCTUnwrap(workspace.review?.current)
        workspace.reviewVerdict(.remove)
        XCTAssertEqual(workspace.reviewDecision(of: first), .remove)
        await workspace.settle()

        XCTAssertTrue(workspace.reviewUp())
        XCTAssertEqual(workspace.review?.depth, 0)
        XCTAssertEqual(workspace.review?.current?.path, folder.path, "coming up returns to the folder")
        let counts = try XCTUnwrap(workspace.reviewMarkedFiles(of: folder))
        XCTAssertGreaterThan(counts.marked, 0)
        XCTAssertLessThanOrEqual(counts.marked, counts.files)
        XCTAssertEqual(workspace.reviewDecision(of: folder), .none, "a mark inside does not mark the folder")
        XCTAssertFalse(workspace.reviewUp(), "the starting level is the top")

        XCTAssertTrue(workspace.undoDecision())
        XCTAssertEqual(workspace.review?.current?.path, folder.path, "undo from another level stays put")
        await workspace.settle()
        XCTAssertEqual(workspace.reviewMarkedFiles(of: folder)?.marked, 0)
    }

    func testAMarkOnAFolderReachesInsideAndADeeperMarkWins() async throws {
        let workspace = await openDemo(self)
        workspace.select([workspace.node(home)])
        await workspace.startReview()
        workspace.reviewGo(to: try XCTUnwrap(workspace.review?.items.firstIndex(where: \.canGoIn)))
        workspace.reviewVerdict(.remove)
        await workspace.settle()
        XCTAssertTrue(workspace.reviewEnter())
        let first = try XCTUnwrap(workspace.review?.current)
        XCTAssertEqual(workspace.reviewDecision(of: first), .remove)
        XCTAssertTrue(workspace.reviewMarkIsInherited(first))

        workspace.reviewVerdict(.keep)
        XCTAssertEqual(workspace.reviewDecision(of: first), .keep)
        XCTAssertFalse(workspace.reviewMarkIsInherited(first))
        await workspace.settle()
        XCTAssertEqual(workspace.resolved?.effective[Int(first.node)], Decision.keep.rawValue)

        workspace.reviewVerdict(.none)
        XCTAssertEqual(workspace.reviewDecision(of: first), .remove, "clearing falls back to the folder's mark")
        XCTAssertTrue(workspace.notice?.message.contains("Still marked") ?? false)
    }

    func testAFileAndAPackageCannotBeEntered() async throws {
        let workspace = await openDemo(self)
        workspace.select(downloads(workspace, ["old-backup.zip", "Figma.dmg"]))
        await workspace.startReview()
        XCTAssertFalse(workspace.reviewEnter())
        XCTAssertEqual(workspace.review?.depth, 0)
        let item = ReviewItem(path: "/a.app", name: "a.app", bytes: 1, kind: .application, isDirectory: true, isPackage: true)
        XCTAssertFalse(item.canGoIn)
    }

    func testSeveralItemsStayAListAndItsFoldersCanBeEntered() async throws {
        let workspace = await openDemo(self)
        let nodes = [workspace.node(home + "/Downloads"), workspace.node(home + "/Library")]
        workspace.select(nodes)
        await workspace.startReview()
        XCTAssertEqual(workspace.review?.items.map(\.node), workspace.selectedNodes)
        XCTAssertEqual(workspace.review?.title, "Selected items")
        XCTAssertTrue(workspace.reviewEnter())
        XCTAssertEqual(workspace.review?.trail.first, "Selected items")
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

    func testUnstagingTakesAnItemOutOfThePlanAndUndoPutsItBack() async throws {
        let workspace = await openDemo(self)
        workspace.select(downloads(workspace, ["old-backup.zip", "Figma.dmg"]))
        workspace.mark(.remove)
        await workspace.settle()
        let path = home + "/Downloads/Figma.dmg"
        XCTAssertEqual(workspace.plan?.items.count, 2)
        workspace.unstage(paths: [path])
        await workspace.settle()
        XCTAssertEqual(workspace.plan?.items.map(\.id), [home + "/Downloads/old-backup.zip"])
        XCTAssertEqual(workspace.resolved?.effective[Int(workspace.node(path))], Decision.none.rawValue)
        XCTAssertTrue(workspace.notice?.canUndo ?? false)
        XCTAssertTrue(workspace.undoDecision())
        await workspace.settle()
        XCTAssertEqual(workspace.plan?.items.count, 2)
    }

    func testUnstagingAnItemStagedThroughItsFolderKeepsIt() async throws {
        let workspace = await openDemo(self)
        let lens = try XCTUnwrap(workspace.lens)
        let tree = lens.tree
        let files = { (node: NodeID) in lens.visibleChildren(of: node).filter { !tree.isDirectory($0) } }
        let folder = try XCTUnwrap((0..<NodeID(tree.count)).first {
            tree.isDirectory($0) && !tree.flags($0).contains(.package) && files($0).count >= 3 && tree.path($0).split(separator: "/").count > 3
        })
        let children = files(folder)
        workspace.select([folder])
        workspace.mark(.remove)
        workspace.select([children[0]])
        workspace.mark(.keep)
        await workspace.settle()
        let target = tree.path(children[1])
        XCTAssertTrue(workspace.plan?.items.contains { $0.id == target } ?? false, "the folder is split, so its children are the roots")

        workspace.unstage(paths: [target])
        await workspace.settle()
        XCTAssertFalse(workspace.plan?.items.contains { $0.id == target } ?? true)
        XCTAssertEqual(workspace.resolved?.effective[Int(children[1])], Decision.keep.rawValue)
        XCTAssertEqual(workspace.resolved?.effective[Int(folder)], Decision.remove.rawValue, "the folder's other items stay staged")
        XCTAssertTrue(workspace.plan?.items.contains { $0.id == tree.path(children[2]) } ?? false)

        XCTAssertTrue(workspace.undoDecision())
        await workspace.settle()
        XCTAssertTrue(workspace.plan?.items.contains { $0.id == target } ?? false, "one undo restores it")
    }

    func testItemsThatCouldNotMoveStayStagedWithTheirReasonAndCanBeUnstaged() async throws {
        let workspace = await openDemo(self)
        let trash = try XCTUnwrap(workspace.environment.mover as? DemoTrash)
        let nodes = downloads(workspace, ["old-backup.zip", "Figma.dmg", "Ubuntu-24.04.iso"])
        workspace.select(nodes)
        workspace.mark(.remove)
        await workspace.settle()
        let stuck = [home + "/Downloads/Figma.dmg", home + "/Downloads/Ubuntu-24.04.iso"]
        trash.refuseMoves(of: stuck)

        let applied = await workspace.applyPlan()
        let report = try XCTUnwrap(applied)
        await workspace.settle()
        XCTAssertEqual(report.moved.map(\.original), [home + "/Downloads/old-backup.zip"])
        XCTAssertEqual(Set(workspace.plan?.items.map(\.id) ?? []), Set(stuck), "what failed stays staged")
        XCTAssertEqual(Set(workspace.planProblems.keys), Set(stuck))
        XCTAssertFalse(workspace.planProblems[stuck[0]]?.isEmpty ?? true)

        workspace.unstage(paths: [stuck[0]])
        await workspace.settle()
        XCTAssertEqual(workspace.plan?.items.map(\.id), [stuck[1]])
        XCTAssertEqual(Array(workspace.planProblems.keys), [stuck[1]], "the reason goes with the item")

        workspace.unstage(paths: Array(workspace.planProblems.keys))
        await workspace.settle()
        XCTAssertEqual(workspace.plan?.items.isEmpty, true)
        XCTAssertTrue(workspace.planProblems.isEmpty)
        XCTAssertFalse(workspace.canApply, "nothing left to apply")
    }

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

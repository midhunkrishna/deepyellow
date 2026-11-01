import AVFoundation
import AppKit
import DYDecide
import DYCore
import DYLenses
import DYSQL
import DYAnalysis
import DYWorkspace
import XCTest

@testable import DeepYellowKit

final class ShellTests: XCTestCase {
    func testLaunchOptionsParse() {
        let options = LaunchOptions.parse(["--demo", "--shot", "app-map", "--out", "/tmp/x.png", "-psn_0_1", "/a/b"])
        XCTAssertTrue(options.demo)
        XCTAssertEqual(options.shot, "app-map")
        XCTAssertEqual(options.out, "/tmp/x.png")
        XCTAssertEqual(options.paths, ["/a/b"])
    }

    /// The real Trash mover is chosen only for a normal launch; demo and shot launches always get the fake.
    func testRealTrashOnlyForNonDemoLaunch() {
        XCTAssertEqual(Composition.moverKind(for: LaunchOptions.parse([])), .system)
        XCTAssertEqual(Composition.moverKind(for: LaunchOptions.parse(["/some/folder"])), .system)
        XCTAssertEqual(Composition.moverKind(for: LaunchOptions.parse(["--demo"])), .demo)
        XCTAssertEqual(Composition.moverKind(for: LaunchOptions.parse(["--shot", "app-map", "--out", "x"])), .demo)
        XCTAssertEqual(Composition.moverKind(for: LaunchOptions.parse(["--demo", "/some/folder"])), .demo)
    }

    /// A read-only launch gets a mover that refuses everything, never `SystemTrash`; demo still wins; a read-only shot is a real scan.
    func testReadOnlyLaunchGetsTheRefusingMover() throws {
        XCTAssertEqual(Composition.moverKind(for: .parse(["--read-only", "/some/folder"])), .refusing)
        XCTAssertEqual(Composition.moverKind(for: .parse(["--demo", "--read-only", "/some/folder"])), .demo)
        let shot = LaunchOptions.parse(["--read-only", "/some/folder", "--shot", "app-map", "--out", "x"])
        XCTAssertFalse(shot.isDemo)
        XCTAssertEqual(Composition.moverKind(for: shot), .refusing)
        XCTAssertEqual(Composition.moverKind(for: .parse(["/some/folder"])), .system)
        let refusing = RefusingTrash()
        XCTAssertThrowsError(try refusing.moveToTrash(path: "/anything"))
        XCTAssertThrowsError(try refusing.moveBack(from: "/a", to: "/b"))
        XCTAssertThrowsError(try refusing.currentFingerprint(path: "/a"))
    }

    @MainActor func testReadOnlyEnvironmentUsesTheRefusingMover() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dy-ro-\(UUID().uuidString)")
        let environment = Composition.environment(for: .parse(["--read-only", "/x"]), demoDirectory: directory)
        XCTAssertTrue(environment.mover is RefusingTrash)
        XCTAssertNil(environment.sampleDisk)
    }

    func testReadOnlyShotNeverFallsBackToHomeWithoutDEEPYELLOWHome() {
        let options = LaunchOptions.parse(["--read-only", "/x", "--shot", "app-map", "--out", "y"])
        let directory = Composition.dataDirectory(options: options, environment: [:])
        XCTAssertTrue(directory.path.contains("DeepYellowShot-"))
        XCTAssertEqual(Composition.dataDirectory(options: options, environment: ["DEEPYELLOW_HOME": "/tmp/h"]).path, "/tmp/h")
    }

    func testSampleMediaIsGeneratedAndMappedByKind() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("dy-media-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let locate = DemoMedia.locator(in: folder)
        XCTAssertNil(locate("/Users/demo/a.mov", .video), "nothing is mapped before the files exist")
        await DemoMedia.ensure(in: folder)
        let video = try XCTUnwrap(locate("/Users/demo/a.mov", .video))
        XCTAssertGreaterThan((try? Data(contentsOf: video).count) ?? 0, 10_000)
        XCTAssertEqual(video.pathExtension, "mp4")
        XCTAssertEqual(locate("/Users/demo/a.heic", .image)?.pathExtension, "jpg")
        XCTAssertEqual(locate("/Users/demo/a.pdf", .document)?.pathExtension, "pdf")
        XCTAssertNil(locate("/Users/demo/a.zip", .archive))
        let playable = try await AVURLAsset(url: video).load(.isPlayable)
        XCTAssertTrue(playable)
    }

    @MainActor func testDemoEnvironmentUsesTheFakeTrash() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dy-shell-\(UUID().uuidString)")
        let environment = Composition.environment(for: LaunchOptions.parse(["--demo"]), demoDirectory: directory)
        XCTAssertTrue(environment.mover is DemoTrash)
        XCTAssertNotNil(environment.sampleDisk)
    }

    func testDemoDataDirectoryHonoursHomeExceptForShots() {
        let env = ["DEEPYELLOW_HOME": "/tmp/dy-home-test"]
        XCTAssertEqual(Composition.demoDataDirectory(options: .parse(["--demo"]), environment: env).path, "/tmp/dy-home-test")
        XCTAssertNotEqual(Composition.demoDataDirectory(options: .parse(["--shot", "x"]), environment: env).path, "/tmp/dy-home-test")
    }

    func testKeyMap() {
        func key(_ c: String, _ code: UInt16 = 0, _ flags: NSEvent.ModifierFlags = []) -> ShellCommand? {
            KeyMap.command(characters: c, keyCode: code, flags: flags)
        }
        XCTAssertEqual(key("1"), .lens(.map))
        XCTAssertEqual(key("7"), .lens(.reclaim))
        XCTAssertEqual(key("k"), .mark(.keep))
        XCTAssertEqual(key("x"), .mark(.remove))
        XCTAssertEqual(key("k", 40, .command), .openPalette)
        XCTAssertEqual(key("\r", 36, .command), .openPlan)
        XCTAssertEqual(key(" ", 49), .togglePreview)
        XCTAssertEqual(key("", 53), .escape)
        XCTAssertEqual(key("", 123), .move(.left))
        XCTAssertEqual(key("\r", 36), .zoomIn)
        XCTAssertEqual(key("c", 8, .command), .copyReviewPath)
        XCTAssertNil(key("x", 7, .command))
        XCTAssertNil(key("q", 12))
    }

    func testBrushQueryReplacesEarlierBrushTerms() {
        let first = BrushQuery.apply(to: "kind:video", age: 2...3, size: 8...9, clock: "age")
        XCTAssertEqual(first, "kind:video age>100d age<1000d size>100mb size<1000mb")
        let second = BrushQuery.apply(to: first, age: 1...2, size: 6...7, clock: "age")
        XCTAssertEqual(second.components(separatedBy: " ").filter { $0.hasPrefix("age>") }.count, 1)
        XCTAssertTrue(second.hasPrefix("kind:video"))
        XCTAssertEqual(Query.parse(second).errors, [])
    }

    func testRecentStoreKeepsNewestFirstWithoutDuplicates() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dy-recent-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = RecentStore(directory: dir)
        store.record("/a"); store.record("/b"); store.record("/a")
        XCTAssertEqual(store.load(), ["/a", "/b"])
    }

    func testInstallerLinksOnlyIntoTheGivenDirectoryAndNeverOverwritesAFile() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("dy-install-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let script = base.appendingPathComponent("DeepYellow.app/Contents/Resources/bin/deepyellow")
        try FileManager.default.createDirectory(at: script.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: script)
        let bin = base.appendingPathComponent("bin")
        let installer = CLIInstaller(scriptURL: script)
        XCTAssertEqual(installer.install(into: bin, environment: ["PATH": bin.path]), .installed(link: bin.appendingPathComponent("deepyellow").path, onPath: true))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: bin.appendingPathComponent("deepyellow").path), script.path)
        XCTAssertEqual(installer.install(into: bin), .alreadyInstalled(link: bin.appendingPathComponent("deepyellow").path))
        let other = base.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: other.appendingPathComponent("deepyellow"))
        if case .refused = installer.install(into: other) {} else { XCTFail("must not overwrite a regular file") }
        XCTAssertEqual(try String(contentsOf: other.appendingPathComponent("deepyellow"), encoding: .utf8), "mine")
    }

    // MARK: SQL drawer

    func testSKeyTogglesTheSQLDrawer() {
        XCTAssertEqual(KeyMap.command(characters: "s", keyCode: 1, flags: []), .toggleSQL)
        XCTAssertNil(KeyMap.command(characters: "s", keyCode: 1, flags: .command))
        XCTAssertTrue(ShellCommand.catalog.contains { $0.command == .toggleSQL })
        XCTAssertTrue(ShellCommand.catalog.contains { $0.command == .runSQL })
    }

    /// Single keys never fire in a text field; ⌘⏎ runs the query in the SQL editor and opens the Plan everywhere else.
    func testKeyRoutingAroundTheSQLEditor() {
        XCTAssertEqual(KeyRouter.route(.openPlan, typing: true, sqlEditorFocused: true), .perform(.runSQL))
        XCTAssertEqual(KeyRouter.route(.openPlan, typing: true, sqlEditorFocused: false), .perform(.openPlan))
        XCTAssertEqual(KeyRouter.route(.openPlan, typing: false, sqlEditorFocused: false), .perform(.openPlan))
        for single in [ShellCommand.toggleSQL, .mark(.remove), .mark(.keep), .hide, .review, .lens(.things), .toggleMetric, .move(.left), .zoomOut] {
            XCTAssertEqual(KeyRouter.route(single, typing: true, sqlEditorFocused: true), .passThrough, "\(single) must not fire while typing")
            XCTAssertEqual(KeyRouter.route(single, typing: true, sqlEditorFocused: false), .passThrough)
            XCTAssertEqual(KeyRouter.route(single, typing: false, sqlEditorFocused: false), .perform(single))
        }
        XCTAssertEqual(KeyRouter.route(.escape, typing: true, sqlEditorFocused: true), .leaveTextField)
        XCTAssertEqual(KeyRouter.route(.openPalette, typing: true, sqlEditorFocused: true), .perform(.openPalette))
    }

    @MainActor func testTogglingTheDrawerFocusesTheEditor() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dy-sqlshell-\(UUID().uuidString)")
        let shell = ShellState(workspace: Workspace(environment: .demo(dataDirectory: directory)), isDemo: true, fullDiskAccess: .denied)
        XCTAssertFalse(shell.sqlOpen)
        shell.perform(.toggleSQL)
        XCTAssertTrue(shell.sqlOpen)
        XCTAssertEqual(shell.sqlFocusToken, 1)
        shell.perform(.toggleSQL)
        XCTAssertFalse(shell.sqlOpen)
        shell.perform(.runSQL)
        XCTAssertTrue(shell.sqlOpen, "running opens the drawer so the answer is visible")
    }

    /// A demo shell on a finished scan, with the Map's canvas holding the same lens the window would give it.
    @MainActor private func demoShell() async -> ShellState {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dy-keys-\(UUID().uuidString)")
        let workspace = Workspace(environment: .demo(dataDirectory: directory))
        let shell = ShellState(workspace: workspace, isDemo: true, fullDiskAccess: .denied)
        workspace.open(.demo)
        await workspace.settle()
        workspace.setLens(.map)
        await workspace.settle()
        shell.canvases.map.update(lens: workspace.lens!, style: workspace.nodeStyle, metric: workspace.metric, selection: [], animated: false)
        return shell
    }

    /// ⏎ goes into a folder and selects its first item, and Esc comes back to exactly where it was.
    @MainActor func testEnterGoesInAndEscapeComesBackOnTheMap() async throws {
        let shell = await demoShell()
        let workspace = shell.workspace
        let lens = try XCTUnwrap(workspace.lens)
        let tree = lens.tree
        var folder: NodeID = 0
        while let child = lens.visibleChildren(of: folder).first(where: { tree.isDirectory($0) && !lens.visibleChildren(of: $0).isEmpty }),
              tree.ancestry(child).count < 3 { folder = child }
        workspace.setFocus(folder)
        let start = try XCTUnwrap(lens.visibleChildren(of: folder).first { tree.isDirectory($0) && !lens.visibleChildren(of: $0).isEmpty })
        workspace.select([start])

        shell.perform(.zoomIn)
        XCTAssertEqual(workspace.focus, start)
        XCTAssertEqual(workspace.selectedNodes, [lens.visibleChildren(of: start).first!])

        shell.perform(.escape)
        XCTAssertEqual(workspace.focus, folder)
        XCTAssertEqual(workspace.selectedNodes, [start])

        var file = start
        while tree.isDirectory(file) { file = try XCTUnwrap(lens.visibleChildren(of: file).first) }
        workspace.select([file])
        let before = workspace.focus
        shell.perform(.zoomIn)
        XCTAssertEqual(workspace.focus, before, "a file has nothing to go into")
        XCTAssertEqual(workspace.selectedNodes, [file])
    }

    /// Esc walks all the way out: at the top level it clears the selection, and it clears a multi-selection straight away.
    @MainActor func testEscapeAtTheTopAndWithSeveralSelected() async throws {
        let shell = await demoShell()
        let workspace = shell.workspace
        let top = workspace.lens!.visibleChildren(of: 0)
        workspace.select([top[0]])
        shell.perform(.escape)
        XCTAssertTrue(workspace.selectedNodes.isEmpty)
        XCTAssertEqual(workspace.focus, 0)

        let inner = workspace.lens!.visibleChildren(of: top[0])
        XCTAssertGreaterThan(inner.count, 0)
        workspace.setFocus(top[0])
        shell.perform(.escape)
        XCTAssertEqual(workspace.focus, 0, "nothing selected steps out")
        XCTAssertEqual(workspace.selectedNodes, [top[0]], "and selects the folder just left")

        workspace.setFocus(top[0])
        workspace.select(Array(inner.prefix(2)) + [top[0]])
        shell.perform(.escape)
        XCTAssertTrue(workspace.selectedNodes.isEmpty)
    }

    /// All four arrows stay in the level, go the way the tiles really lie, and can reach every item.
    @MainActor func testArrowsWalkEveryTileOfALevelOnTheMap() async throws {
        let shell = await demoShell()
        let workspace = shell.workspace
        let lens = try XCTUnwrap(workspace.lens)
        var parent: NodeID = 0
        while let next = lens.visibleChildren(of: parent).max(by: { lens.visibleChildren(of: $0).count < lens.visibleChildren(of: $1).count }),
              lens.visibleChildren(of: parent).count < 8 { parent = next }
        let siblings = lens.visibleChildren(of: parent)
        XCTAssertGreaterThanOrEqual(siblings.count, 8)
        workspace.setFocus(parent)
        let rects = shell.canvases.map.levelRects(parent: parent)
        XCTAssertEqual(Set(rects.keys), Set(siblings))

        var reached: Set<NodeID> = [siblings[0]]
        var frontier = [siblings[0]]
        while let node = frontier.popLast() {
            for direction in [MoveDirection.left, .right, .up, .down] {
                workspace.select([node])
                shell.perform(.move(direction))
                let landed = try XCTUnwrap(workspace.selectedNodes.first)
                XCTAssertEqual(workspace.focus, parent)
                XCTAssertTrue(siblings.contains(landed), "arrows stay in the level")
                if landed != node {
                    let (from, to) = (rects[node]!, rects[landed]!)
                    switch direction {
                    case .left: XCTAssertLessThanOrEqual(to.maxX, from.minX + 1e-9)
                    case .right: XCTAssertGreaterThanOrEqual(to.minX, from.maxX - 1e-9)
                    case .up: XCTAssertLessThanOrEqual(to.maxY, from.minY + 1e-9)
                    case .down: XCTAssertGreaterThanOrEqual(to.minY, from.maxY - 1e-9)
                    }
                }
                if reached.insert(landed).inserted { frontier.append(landed) }
            }
        }
        XCTAssertEqual(reached, Set(siblings), "every item in the level can be reached")
    }

    /// Picks the tile straight ahead, not one that is merely closer off to the side.
    func testTileStepPrefersWhatIsStraightAhead() {
        let rects: [NodeID: CGRect] = [
            1: CGRect(x: 0, y: 0, width: 2, height: 2), 2: CGRect(x: 2, y: 0, width: 1, height: 1), 3: CGRect(x: 2, y: 1, width: 1, height: 1),
            4: CGRect(x: 0, y: 2, width: 3, height: 1),
        ]
        XCTAssertEqual(LevelNavigation.tile(from: 2, .left, rects: rects), 1)
        XCTAssertEqual(LevelNavigation.tile(from: 2, .down, rects: rects), 3)
        XCTAssertEqual(LevelNavigation.tile(from: 3, .down, rects: rects), 4)
        XCTAssertEqual(LevelNavigation.tile(from: 1, .down, rects: rects), 4)
        XCTAssertNil(LevelNavigation.tile(from: 1, .left, rects: rects))
        XCTAssertNil(LevelNavigation.tile(from: 1, .up, rects: rects))
        XCTAssertNil(LevelNavigation.tile(from: 99, .up, rects: rects))
    }

    /// In Things, up and down walk the list in order, skipping "smaller items" rows, and left and right do nothing.
    @MainActor func testThingsMovesWithUpAndDown() async throws {
        let shell = await demoShell()
        let workspace = shell.workspace
        workspace.setLens(.things)
        await workspace.settle()
        let rows = try XCTUnwrap(workspace.things).items.compactMap { thing -> NodeID? in
            if case .node(let node) = thing.content { node } else { nil }
        }
        XCTAssertGreaterThan(rows.count, 3)
        shell.perform(.move(.down))
        XCTAssertEqual(workspace.selectedNodes, [rows[0]], "nothing selected starts at the top")
        shell.perform(.move(.down))
        XCTAssertEqual(workspace.selectedNodes, [rows[1]])
        shell.perform(.move(.down))
        XCTAssertEqual(workspace.selectedNodes, [rows[2]])
        shell.perform(.move(.up))
        XCTAssertEqual(workspace.selectedNodes, [rows[1]])
        shell.perform(.move(.left))
        shell.perform(.move(.right))
        XCTAssertEqual(workspace.selectedNodes, [rows[1]], "the list has one column")
        workspace.select([rows[rows.count - 1]])
        shell.perform(.move(.down))
        XCTAssertEqual(workspace.selectedNodes, [rows[rows.count - 1]], "stops at the end")
    }

    /// The whole walk through the shell's commands: open a folder, mark, move, go in, mark, come back up, close.
    @MainActor func testReviewWalksThroughAFolderWithTheKeys() async throws {
        let shell = await demoShell()
        let workspace = shell.workspace
        let lens = try XCTUnwrap(workspace.lens)
        let tree = lens.tree
        var start: NodeID = 0
        while let child = lens.visibleChildren(of: start).first(where: { tree.isDirectory($0) }),
              lens.visibleChildren(of: start).filter({ tree.isDirectory($0) }).count < 2 { start = child }
        workspace.select([start])
        let focus = workspace.focus
        let started = await workspace.startReview()
        XCTAssertTrue(started)
        XCTAssertEqual(workspace.review?.depth, 0)

        let first = try XCTUnwrap(workspace.review?.current)
        shell.perform(.mark(.remove))
        XCTAssertEqual(workspace.review?.current?.path, first.path, "x stays on the item")
        shell.perform(.move(.right))
        XCTAssertEqual(workspace.review?.index, 1, "the arrow goes to the very next item")
        shell.perform(.move(.left))
        shell.perform(.mark(.none))
        XCTAssertEqual(workspace.reviewDecision(of: first), .none, "u clears the item on screen")

        workspace.reviewGo(to: try XCTUnwrap(workspace.review?.items.firstIndex(where: \.canGoIn)))
        let folder = try XCTUnwrap(workspace.review?.current)
        shell.perform(.zoomIn)
        XCTAssertEqual(workspace.review?.depth, 1)
        XCTAssertEqual(workspace.review?.index, 0)
        shell.perform(.mark(.remove))

        shell.perform(.zoomOut)
        XCTAssertEqual(workspace.review?.current?.path, folder.path, "⌫ comes back up too")
        shell.perform(.zoomIn)
        shell.perform(.escape)
        XCTAssertEqual(workspace.review?.depth, 0, "Esc goes up first")
        XCTAssertEqual(workspace.review?.current?.path, folder.path)

        shell.perform(.escape)
        XCTAssertNil(workspace.review, "Esc at the top closes Review")
        XCTAssertEqual(workspace.selectedNodes, [start], "back on the same highlight")
        XCTAssertEqual(workspace.focus, focus, "the view underneath didn't move")
        await workspace.settle()
        XCTAssertEqual(workspace.markedFiles[Int(start)] > 0, true, "marks stay after closing")
    }

    /// The path copied in Review is the full path of the item on screen, and goes to the given pasteboard only.
    @MainActor func testReviewPathCopies() async throws {
        let scratch = NSPasteboard.withUniqueName()
        defer { scratch.releaseGlobally() }
        PathClipboard.copy("/Users/demo/a file.mov", to: scratch)
        XCTAssertEqual(scratch.string(forType: .string), "/Users/demo/a file.mov")
    }

    func testSQLHighlighterFindsKeywordsFunctionsStringsNumbersAndComments() {
        let text = "SELECT human(size), 'a''b' -- note\nFROM files WHERE size > 100"
        let spans = SQLHighlighter.spans(in: text)
        let ns = text as NSString
        func words(_ token: SQLHighlighter.Token) -> [String] { spans.filter { $0.token == token }.map { ns.substring(with: $0.range) } }
        XCTAssertEqual(words(.keyword), ["SELECT", "FROM", "WHERE"])
        XCTAssertEqual(words(.function), ["human"])
        XCTAssertEqual(words(.string), ["'a''b'"])
        XCTAssertEqual(words(.number), ["100"])
        XCTAssertEqual(words(.comment), ["-- note"])
        XCTAssertTrue(SQLHighlighter.spans(in: "").isEmpty)
    }

    func testNarrowTablesFillTheDrawerWithTheLastTextColumn() {
        XCTAssertEqual(SQLColumnLayout.fill([60, 100, 80], numeric: [true, false, true], available: 500), [60, 360, 80])
        XCTAssertEqual(SQLColumnLayout.fill([60, 100], numeric: [true, true], available: 300), [60, 240])
        XCTAssertEqual(SQLColumnLayout.fill([300, 300], numeric: [false, false], available: 400), [300, 300], "wide tables keep their widths and scroll")
        XCTAssertEqual(SQLColumnLayout.fill([], numeric: [], available: 400), [])
    }

    func testResultCellsReadPlainly() {
        XCTAssertEqual(SQLValueText.text(.null), "NULL")
        XCTAssertEqual(SQLValueText.text(.integer(-4)), "-4")
        XCTAssertEqual(SQLValueText.text(.real(2.5)), "2.5")
        XCTAssertEqual(SQLValueText.text(.blob(byteCount: 12)), "<12 bytes>")
        XCTAssertTrue(SQLValueText.isNumber(.real(1)))
        XCTAssertFalse(SQLValueText.isNumber(.text("1")))
        XCTAssertEqual(SQLValueText.message(of: .refused(message: "No.")), "No.")
    }
}

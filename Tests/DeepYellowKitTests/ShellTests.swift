import AVFoundation
import AppKit
import DYDecide
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

import DYCore
import DYAdvisor
import DYWorkspace
import XCTest

@testable import DeepYellowKit

final class CLITests: XCTestCase {
    /// Output captured from a CLI run.
    final class Capture { var out = "", err = "", opened: [OpenRequest] = [] }

    /// Runs the CLI against captured streams.
    private func run(_ args: [String], tty: Bool = false, env: [String: String] = [:], home: String = "/nonexistent-home") -> (code: Int32, cap: Capture) {
        let cap = Capture()
        let context = CLIContext(isTTY: tty, environment: env, home: home, out: { cap.out += $0 }, err: { cap.err += $0 },
                                 open: { cap.opened.append($0); return 0 })
        return (CLI.run(arguments: args, context: context), cap)
    }

    /// A small folder tree made only for this test.
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("dy-cli-\(UUID().uuidString)")
        let big = root.appendingPathComponent("big"), small = root.appendingPathComponent("small")
        try FileManager.default.createDirectory(at: big, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: small, withIntermediateDirectories: true)
        try Data(count: 3_000_000).write(to: big.appendingPathComponent("a.bin"))
        try Data(count: 3_000_000).write(to: big.appendingPathComponent("b.bin"))
        try Data(count: 5_000).write(to: small.appendingPathComponent("c.txt"))
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    func testParsesSubcommandsAndOptions() throws {
        XCTAssertEqual(try CLIParser.parse(["things", "/x", "--min", "100mb", "--top=5", "--json"]),
                       .things(path: "/x", minimumBytes: 100_000_000, top: 5, json: true))
        XCTAssertEqual(try CLIParser.parse(["reclaim", "/x"]), .reclaim(path: "/x", json: false))
        XCTAssertEqual(try CLIParser.parse(["dupes", "/x"]), .dupes(path: "/x", minimumBytes: 1_000_000, json: false))
        XCTAssertEqual(try CLIParser.parse(["--version"]), .version)
        XCTAssertEqual(try CLIParser.parse(["things", "--help"]), .help(topic: "things"))
        XCTAssertEqual(try CLIParser.parse(["/f", "--read-only", "--print-open-args"]), .open(OpenRequest(path: "/f", demo: false, dryRun: true, readOnly: true)))
        XCTAssertThrowsError(try CLIParser.parse(["--read-only"]))
        XCTAssertEqual(try CLIParser.parse(["--demo"]), .open(OpenRequest(path: nil, demo: true, dryRun: false)))
        XCTAssertEqual(try CLIParser.parse(["/some/folder", "--print-open-args"]), .open(OpenRequest(path: "/some/folder", demo: false, dryRun: true)))
    }

    func testRejectsBadArguments() {
        XCTAssertThrowsError(try CLIParser.parse(["things"]))
        XCTAssertThrowsError(try CLIParser.parse(["things", "/x", "--min", "lots"]))
        XCTAssertThrowsError(try CLIParser.parse(["things", "/x", "--top", "0"]))
        XCTAssertThrowsError(try CLIParser.parse(["--delete", "/x"]))
        XCTAssertThrowsError(try CLIParser.parse([]))
    }

    func testSizeParser() {
        XCTAssertEqual(SizeParser.parse("100mb"), 100_000_000)
        XCTAssertEqual(SizeParser.parse("1.5 GB"), 1_500_000_000)
        XCTAssertEqual(SizeParser.parse("4096"), 4096)
        XCTAssertNil(SizeParser.parse("big"))
    }

    func testColorOnlyOnTerminalWithoutNoColor() {
        XCTAssertTrue(OutputStyle.detect(isTTY: true, environment: [:]).color)
        XCTAssertFalse(OutputStyle.detect(isTTY: false, environment: [:]).color)
        XCTAssertFalse(OutputStyle.detect(isTTY: true, environment: ["NO_COLOR": "1"]).color)
    }

    func testBarsAreExactWidthAndColouredOnlyWhenAsked() {
        XCTAssertEqual(BarRenderer.bar(fraction: 0.5, width: 10, style: .plain).count, 10)
        XCTAssertEqual(BarRenderer.bar(fraction: 1, width: 4, style: .plain), "████")
        XCTAssertFalse(BarRenderer.bar(fraction: 0.3, width: 10, style: .plain).contains("\u{1B}"))
        XCTAssertTrue(BarRenderer.bar(fraction: 0.3, width: 10, style: .colored).contains("\u{1B}[38;2;255;184;0m"))
    }

    func testThingsOutputOnSampleTree() throws {
        let tree = SyntheticTree.make(scale: 0.05)
        let report = CLIAnalysis.things(tree: tree, minimumBytes: nil, top: 10)
        XCTAssertFalse(report.rows.isEmpty)
        XCTAssertLessThanOrEqual(report.rows.count, 10)
        let plain = CLIRender.things(report, style: .plain)
        XCTAssertFalse(plain.contains("\u{1B}"))
        XCTAssertTrue(CLIRender.things(report, style: .colored).contains("\u{1B}["))
        let json = try JSONSerialization.jsonObject(with: Data(CLIRender.thingsJSON(report).utf8)) as? [String: Any]
        XCTAssertEqual((json?["things"] as? [[String: Any]])?.count, report.rows.count)
        XCTAssertEqual(CLIRender.thingsJSON(report), CLIRender.thingsJSON(report))
    }

    func testSpectrumAndReclaimRenderOnSampleTree() {
        let tree = SyntheticTree.make(scale: 0.05)
        XCTAssertTrue(CLIRender.spectrum(CLIAnalysis.spectrum(tree: tree), style: .plain).contains("largest files hold 80%"))
        let summary = CLIAnalysis.reclaim(tree: tree, home: "/Users/demo", catalog: NoApps())
        XCTAssertFalse(summary.groups.isEmpty)
        XCTAssertTrue(CLIRender.reclaim(summary, style: .plain).contains("Safety groups"))
        XCTAssertNotNil(try? JSONSerialization.jsonObject(with: Data(CLIRender.reclaimJSON(summary).utf8)))
    }

    func testUnknownPathExitsTwoWithMessageOnStderr() {
        let result = run(["things", "/definitely/not/here"])
        XCTAssertEqual(result.code, 2)
        XCTAssertTrue(result.cap.err.contains("no such folder"))
        XCTAssertTrue(result.cap.out.isEmpty)
        XCTAssertEqual(run(["/definitely/not/here"]).code, 2)
    }

    func testThingsJSONOnFixtureIsPlainAndStable() throws {
        let root = try fixture()
        let result = run(["things", root.path, "--min", "1mb", "--json"], tty: true)
        XCTAssertEqual(result.code, 0)
        XCTAssertFalse(result.cap.out.contains("\u{1B}"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(result.cap.out.utf8)) as? [String: Any])
        let paths = (json["things"] as? [[String: Any]])?.compactMap { $0["path"] as? String } ?? []
        XCTAssertTrue(paths.contains { $0.hasSuffix("a.bin") })
        XCTAssertTrue(paths.contains { $0.hasSuffix("b.bin") })
    }

    func testDupesFindsIdenticalFixtureFiles() throws {
        let root = try fixture()
        let result = run(["dupes", root.path, "--min", "1mb"])
        XCTAssertEqual(result.code, 0)
        XCTAssertTrue(result.cap.out.contains("2 copies"), result.cap.out)
    }

    func testOpenResolvesPathAndHandsItToTheOpener() throws {
        let root = try fixture()
        let result = run([root.path, "--print-open-args"])
        XCTAssertEqual(result.cap.opened.first?.path, root.standardizedFileURL.path)
        XCTAssertEqual(result.cap.opened.first?.dryRun, true)
        let text = AppOpener.description(of: OpenRequest(path: "/a", demo: true, dryRun: true), appURL: URL(fileURLWithPath: "/Apps/DeepYellow.app"))
        XCTAssertTrue(text.contains("arguments: --demo"))
        XCTAssertTrue(text.contains("new instance: yes"))
        let readOnly = AppOpener.description(of: OpenRequest(path: "/a", demo: false, dryRun: true, readOnly: true), appURL: nil)
        XCTAssertTrue(readOnly.contains("arguments: --read-only /a"))
        XCTAssertTrue(readOnly.contains("new instance: yes"))
    }

    func testVersionAndHelp() {
        XCTAssertTrue(run(["--version"]).cap.out.hasPrefix("DeepYellow "))
        let help = run(["--help"]).cap.out
        XCTAssertTrue(help.contains("read-only"))
        XCTAssertFalse(help.lowercased().contains("deepyellow delete"))
    }
}

/// An app catalog that knows no apps.
struct NoApps: AppCatalog {
    func app(bundleID: String) -> AppIdentity? { nil }
    func app(named: String) -> AppIdentity? { nil }
}

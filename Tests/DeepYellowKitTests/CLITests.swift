import DYCore
import DYSQL
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

    // MARK: sql

    func testSQLParsing() throws {
        XCTAssertEqual(try CLIParser.parse(["sql", "/x", "SELECT 1"]), .sql(SQLRequest(path: "/x", query: "SELECT 1", format: .table, top: 200)))
        XCTAssertEqual(try CLIParser.parse(["sql", "--demo", "SELECT 1", "--json", "--top", "5"]),
                       .sql(SQLRequest(path: nil, query: "SELECT 1", format: .json, top: 5)))
        XCTAssertEqual(try CLIParser.parse(["sql", "--demo", "SELECT 1", "--csv"]), .sql(SQLRequest(path: nil, query: "SELECT 1", format: .csv, top: 200)))
        XCTAssertEqual(try CLIParser.parse(["sql", "--schema"]), .sqlSchema)
        XCTAssertEqual(try CLIParser.parse(["sql", "--help"]), .help(topic: "sql"))
        XCTAssertEqual(try CLIParser.parse(["--demo"]), .open(OpenRequest(path: nil, demo: true, dryRun: false)), "--demo alone still opens the app")
        XCTAssertThrowsError(try CLIParser.parse(["sql", "--demo"]))
        XCTAssertThrowsError(try CLIParser.parse(["sql", "/x"]))
        XCTAssertThrowsError(try CLIParser.parse(["sql", "--demo", "  "]))
        XCTAssertThrowsError(try CLIParser.parse(["sql", "--demo", "SELECT 1", "--json", "--csv"]))
        XCTAssertThrowsError(try CLIParser.parse(["sql", "--demo", "SELECT 1", "--top", "0"]))
    }

    func testSQLTableOnTheSampleDisk() {
        let result = run(["sql", "--demo", "SELECT id, name, human(size) AS readable FROM files ORDER BY size DESC LIMIT 5", "--top", "3"])
        XCTAssertEqual(result.code, 0)
        XCTAssertTrue(result.cap.out.contains("Docker.raw"))
        XCTAssertTrue(result.cap.out.contains("2 more rows"), result.cap.out)
        XCTAssertFalse(result.cap.out.contains("\u{1B}"))
        XCTAssertTrue(result.cap.err.isEmpty)
    }

    func testSQLJSONAndCSVStreamEveryRowPastTheDisplayCap() throws {
        let query = "SELECT id, name FROM files"
        let disk = CLISQL.demoDisk()
        let expected = try SQLEngine.run(query, context: SQLContext(tree: disk.tree, lens: TreeLens(tree: disk.tree), now: disk.now), rowLimit: 0).rowCount
        XCTAssertGreaterThan(expected, 5_000, "the sample disk must be big enough to prove the stream isn't capped")

        let json = run(["sql", "--demo", query, "--json"])
        XCTAssertEqual(json.code, 0)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.cap.out.utf8)) as? [String: Any])
        XCTAssertEqual((object["rows"] as? [[Any]])?.count, expected)
        XCTAssertEqual(object["rowCount"] as? Int, expected)
        XCTAssertEqual(object["columns"] as? [String], ["id", "name"])

        let csv = run(["sql", "--demo", query, "--csv"])
        let lines = csv.cap.out.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.first, "id,name")
        XCTAssertEqual(lines.count, expected + 1)
    }

    func testSQLCSVQuotingAndNulls() {
        let result = run(["sql", "--demo", "SELECT 'a,b' AS x, 'say \"hi\"' AS y, NULL AS z, 2.5 AS w", "--csv"])
        XCTAssertEqual(result.cap.out, "x,y,z,w\n\"a,b\",\"say \"\"hi\"\"\",,2.5\n")
    }

    func testSQLSchemaListsColumnsFunctionsAndExamples() {
        let out = run(["sql", "--schema"]).cap.out
        XCTAssertTrue(out.contains("file_count"))
        XCTAssertTrue(out.contains("age_days(seconds)"))
        XCTAssertTrue(out.contains(SQLEngine.examples[0].title))
    }

    func testSQLRefusesWritesWithExit65() {
        for statement in ["DELETE FROM nodes", "UPDATE nodes SET size = 0", "DROP TABLE nodes", "PRAGMA writable_schema = 1"] {
            let result = run(["sql", "--demo", statement])
            XCTAssertEqual(result.code, 65, statement)
            XCTAssertTrue(result.cap.out.isEmpty, statement)
            XCTAssertFalse(result.cap.err.isEmpty, statement)
        }
        XCTAssertTrue(run(["sql", "--demo", "DELETE FROM nodes"]).cap.err.contains("read-only"))
    }

    func testSQLInvalidQueryIs65AndBadArgumentsAre64AndUnknownPathIs2() {
        XCTAssertEqual(run(["sql", "--demo", "SELEC 1"]).code, 65)
        XCTAssertEqual(run(["sql", "--demo", "SELECT 1; SELECT 2"]).code, 65)
        XCTAssertEqual(run(["sql", "--demo"]).code, 64)
        XCTAssertEqual(run(["sql", "--demo", "SELECT 1", "--json", "--csv"]).code, 64)
        let missing = run(["sql", "/definitely/not/here", "SELECT 1"])
        XCTAssertEqual(missing.code, 2)
        XCTAssertTrue(missing.cap.err.contains("no such folder"))
    }

    func testSQLOnAFolderFixture() throws {
        let root = try fixture()
        let result = run(["sql", root.path, "SELECT name, size FROM files ORDER BY name"], home: root.path)
        XCTAssertEqual(result.code, 0)
        XCTAssertTrue(result.cap.out.contains("a.bin"))
        XCTAssertTrue(result.cap.out.contains("c.txt"))
    }

    func testSQLHelpMentionsExitCode65AndStreaming() {
        let help = CLIHelp.text(topic: "sql")
        XCTAssertTrue(help.contains("65"))
        XCTAssertTrue(help.contains("--csv"))
        XCTAssertTrue(CLIHelp.text(topic: nil).contains("deepyellow sql"))
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

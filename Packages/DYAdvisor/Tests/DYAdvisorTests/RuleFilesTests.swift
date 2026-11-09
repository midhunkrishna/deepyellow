import DYCore
import Foundation
import XCTest
@testable import DYAdvisor

final class RuleFilesTests: XCTestCase {
    /// A valid rule as JSON fields, which a test can alter before encoding.
    private func goodRule() -> [String: Any] {
        ["id": "slack.cache", "title": "Slack's web cache", "pattern": "~/Library/Application Support/Slack/Cache",
         "tier": "safe", "whatItIs": "Pages Slack saved.", "consequence": "Slack downloads them again.",
         "sideCondition": "Quit Slack first.", "cleanupCommand": NSNull(), "ownerBundleIDs": ["com.tinyspeck.slackmacgap"],
         "source": "Measured on Slack 4.41",
         "evidence": ["method": "relaunch-test", "appVersion": "4.41.105", "macOSVersion": "15.7.7",
                      "measuredOn": "2026-11-08", "observed": "Came back at 14 MB."]]
    }

    private func fileJSON(_ rules: [[String: Any]], version: Int = 1, section: Any? = ["title": "T", "intro": "I"]) throws -> Data {
        var object: [String: Any] = ["version": version, "rules": rules]
        object["section"] = section
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func decode(_ rules: [[String: Any]], version: Int = 1) throws -> [ReclaimRule] {
        try RuleFiles.decode(fileJSON(rules, version: version), file: "t.json", home: testHome).rules
    }

    /// Asserts decoding fails and the message names the file, the rule and contains `fragment`.
    private func assertRejects(_ rule: [String: Any], _ fragment: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try decode([rule]), file: file, line: line) { error in
            let text = "\(error)"
            XCTAssertTrue(text.contains("t.json"), text, file: file, line: line)
            XCTAssertTrue(text.contains("slack.cache"), text, file: file, line: line)
            XCTAssertTrue(text.contains(fragment), text, file: file, line: line)
        }
    }

    private func temporaryFolder(_ files: [String: Data]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rules-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for (name, data) in files { try data.write(to: url.appendingPathComponent(name)) }
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// Counts the rule entries in the repo's JSON files without the loader, so the loader cannot drop rules unnoticed.
    private func ruleEntriesInFiles() throws -> Int {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../rules").standardizedFileURL
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        return try files.reduce(0) { total, file in
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
            return total + ((object?["rules"] as? [Any])?.count ?? 0)
        }
    }

    func testRepoRulesLoadEveryEntryWithUniqueIDs() throws {
        let entries = try ruleEntriesInFiles()
        XCTAssertGreaterThanOrEqual(entries, 57)
        XCTAssertEqual(repoRules.count, entries)
        XCTAssertEqual(Set(repoRules.map(\.id)).count, entries)
        XCTAssertEqual(repoSections.count, 6)
        XCTAssertTrue(repoSections.allSatisfy { !$0.title.isEmpty && !$0.intro.isEmpty })
    }

    func testDefaultRulesLoadFromTheRepoInDebugBuilds() throws {
        XCTAssertEqual(try ReclaimEngine.rules.get().count, try ruleEntriesInFiles())
    }

    func testValidRuleMapsToReclaimRule() throws {
        let rule = try XCTUnwrap(try decode([goodRule()]).first)
        XCTAssertEqual(rule.id, "slack.cache")
        XCTAssertEqual(rule.tier, .safe)
        XCTAssertEqual(rule.sideCondition, "Quit Slack first.")
        XCTAssertNil(rule.cleanupCommand)
        XCTAssertEqual(rule.ownerBundleIDs, ["com.tinyspeck.slackmacgap"])
    }

    func testSectionCarriesTitleAndIntro() throws {
        let section = try RuleFiles.decode(fileJSON([goodRule()]), file: "t.json", home: testHome)
        XCTAssertEqual(section.title, "T")
        XCTAssertEqual(section.intro, "I")
    }

    func testAlternativePatternsCompile() throws {
        var rule = goodRule()
        rule["pattern"] = "~/Library/A || ~/Library/B"
        XCTAssertEqual(try decode([rule]).count, 1)
    }

    func testRejectsUnknownAndUnknownTier() {
        for tier in ["unknown", "bogus"] {
            var rule = goodRule()
            rule["tier"] = tier
            assertRejects(rule, "tier")
        }
    }

    func testRejectsPatternThatDoesNotCompile() {
        var rule = goodRule()
        rule["pattern"] = "relative/path"
        assertRejects(rule, "pattern")
    }

    func testRejectsMissingOrEmptyRequiredFields() {
        for key in ["title", "pattern", "tier", "whatItIs", "consequence", "ownerBundleIDs", "evidence"] {
            var missing = goodRule()
            missing[key] = nil
            assertRejects(missing, key)
        }
        for key in ["title", "whatItIs", "consequence", "source"] {
            var empty = goodRule()
            empty[key] = ""
            assertRejects(empty, key)
        }
    }

    func testOptionalFieldsMayBeNullOrEmpty() throws {
        var rule = goodRule()
        rule["source"] = NSNull()
        rule["sideCondition"] = NSNull()
        rule["ownerBundleIDs"] = [String]()
        let decoded = try XCTUnwrap(try decode([rule]).first)
        XCTAssertNil(decoded.source)
        XCTAssertNil(decoded.sideCondition)
        XCTAssertEqual(decoded.ownerBundleIDs, [])
    }

    func testRejectsBadEvidence() {
        var unknownMethod = goodRule()
        unknownMethod["evidence"] = ["method": "guess"]
        assertRejects(unknownMethod, "evidence.method")
        var noObserved = goodRule()
        noObserved["evidence"] = ["method": "relaunch-test", "appVersion": "1", "macOSVersion": "15", "measuredOn": "x"]
        assertRejects(noObserved, "evidence.observed")
    }

    func testOnlyRelaunchTestNeedsMeasurementFields() throws {
        for method in ["vendor-doc", "research"] {
            var rule = goodRule()
            rule["evidence"] = ["method": method]
            XCTAssertEqual(try decode([rule]).count, 1, method)
        }
    }

    func testSafeAndRebuildRefuseLocationButReviewAndNeverMayUseIt() throws {
        for tier in ["safe", "rebuild"] {
            var rule = goodRule()
            rule["tier"] = tier
            rule["evidence"] = ["method": "location"]
            assertRejects(rule, "relaunch-test, vendor-doc or research")
        }
        for tier in ["review", "never"] {
            var rule = goodRule()
            rule["tier"] = tier
            rule["evidence"] = ["method": "location"]
            XCTAssertEqual(try decode([rule]).count, 1)
        }
    }

    func testResearchIsAllowedAtAnyTier() throws {
        for tier in ["safe", "rebuild", "review", "never"] {
            var rule = goodRule()
            rule["tier"] = tier
            rule["evidence"] = ["method": "research"]
            XCTAssertEqual(try decode([rule]).count, 1, tier)
        }
    }

    func testRejectsDuplicateIDsBadVersionBadJSONAndMissingSection() {
        XCTAssertThrowsError(try decode([goodRule(), goodRule()]))
        XCTAssertThrowsError(try decode([goodRule()], version: 2))
        XCTAssertThrowsError(try RuleFiles.decode(Data("nope".utf8), file: "t.json", home: testHome))
        XCTAssertThrowsError(try RuleFiles.decode(fileJSON([goodRule()], section: nil), file: "t.json", home: testHome))
        XCTAssertThrowsError(try RuleFiles.decode(fileJSON([goodRule()], section: ["title": "", "intro": "I"]), file: "t.json", home: testHome))
    }

    func testLoadReadsFilesInNameOrder() throws {
        var second = goodRule()
        second["id"] = "other.rule"
        let folder = try temporaryFolder(["20-b.json": fileJSON([second]), "10-a.json": fileJSON([goodRule()]), "notes.txt": Data("x".utf8)])
        let sections = try RuleFiles.load(directory: folder, home: testHome)
        XCTAssertEqual(sections.flatMap(\.rules).map(\.id), ["slack.cache", "other.rule"])
    }

    func testLoadRefusesDuplicateIDsAcrossFiles() throws {
        let folder = try temporaryFolder(["10-a.json": fileJSON([goodRule()]), "20-b.json": fileJSON([goodRule()])])
        XCTAssertThrowsError(try RuleFiles.load(directory: folder, home: testHome)) { error in
            XCTAssertTrue("\(error)".contains("20-b.json: slack.cache: duplicate id"), "\(error)")
        }
    }

    func testLoadRefusesEmptyOrMissingFolder() throws {
        XCTAssertThrowsError(try RuleFiles.load(directory: temporaryFolder([:]), home: testHome))
        XCTAssertThrowsError(try RuleFiles.load(directory: URL(fileURLWithPath: "/nonexistent-rules"), home: testHome))
    }

    func testLoadNamesTheBrokenFile() throws {
        let folder = try temporaryFolder(["10-a.json": Data("{".utf8)])
        XCTAssertThrowsError(try RuleFiles.load(directory: folder, home: testHome)) { error in
            XCTAssertTrue("\(error)".hasPrefix("10-a.json:"), "\(error)")
        }
    }

    /// Slack's measured rules govern its folders, including where the generic embedded-browser rule also matches.
    func testSlackRulesOverrideGenericBrowserRule() {
        let base = "/Users/tester/Library/Application Support/Slack"
        let tree = makeTree([file(base + "/Service Worker/CacheStorage/a/b/blob", 800),
                             file(base + "/Service Worker/ScriptCache/s", 10), file(base + "/Cache/Cache_Data/f", 400),
                             file(base + "/logs/default/browser.log", 50), file(base + "/GPUCache/data_0", 5)])
        let report = ReclaimEngine.analyze(lens: TreeLens(tree: tree), home: testHome, rules: repoRules,
                                           isCancelled: { false })!
        func ruleID(_ path: String) -> String? { report.rule(for: tree.find(path: base + path)!, tree: tree)?.id }
        XCTAssertEqual(ruleID("/Service Worker/CacheStorage/a/b/blob"), "slack.service-worker")
        XCTAssertEqual(ruleID("/Service Worker/ScriptCache/s"), "slack.service-worker")
        XCTAssertEqual(ruleID("/Cache/Cache_Data/f"), "slack.cache")
        XCTAssertEqual(ruleID("/logs/default/browser.log"), "slack.logs")
        XCTAssertEqual(ruleID("/GPUCache/data_0"), "chromium.caches")
    }

    /// Generic rules (node_modules, yarn) must not fire inside installed VS Code extensions, which would break them.
    func testVSCodeExtensionsProtectWhatTheyBundle() {
        let ext = "/Users/tester/.vscode/extensions/esbenp.prettier-vscode-12.4.0"
        let tree = makeTree([file(ext + "/node_modules/prettier/index.js", 700), file(ext + "/package.json", 2),
                             file(ext + "/package-lock.json", 2)])
        let report = ReclaimEngine.analyze(lens: TreeLens(tree: tree), home: testHome, rules: repoRules,
                                           isCancelled: { false })!
        let node = tree.find(path: ext + "/node_modules/prettier/index.js")!
        XCTAssertEqual(SafetyTier(rawValue: report.nodeTier[Int(node)]), .never)
        XCTAssertEqual(report.rule(for: node, tree: tree)?.id, "vscode.extensions")
    }

    /// Discord's downloaded program modules bundle node_modules; removing anything there stops Discord from starting.
    func testDiscordModulesProtectWhatTheyBundle() {
        let mod = "/Users/tester/Library/Application Support/discord/app-0.0.421/modules/discord_spellcheck-1/discord_spellcheck"
        let tree = makeTree([file(mod + "/node_modules/cld/build/Release/cld.node", 900), file(mod + "/package.json", 2)])
        let report = ReclaimEngine.analyze(lens: TreeLens(tree: tree), home: testHome, rules: repoRules,
                                           isCancelled: { false })!
        let node = tree.find(path: mod + "/node_modules/cld/build/Release/cld.node")!
        XCTAssertEqual(SafetyTier(rawValue: report.nodeTier[Int(node)]), .never)
        XCTAssertEqual(report.rule(for: node, tree: tree)?.id, "discord.app-code")
    }

    /// Poetry keeps real project environments inside ~/Library/Caches; they must not fall under the generic cache rule.
    func testPoetryEnvironmentsAreNotTreatedAsCache() {
        let base = "/Users/tester/Library/Caches/pypoetry"
        let tree = makeTree([file(base + "/virtualenvs/app-x1-py3.12/lib/numpy.so", 900), file(base + "/cache/repositories/x", 5),
                             file("/Users/tester/Library/Caches/com.example.app/blob", 7)])
        let report = ReclaimEngine.analyze(lens: TreeLens(tree: tree), home: testHome, rules: repoRules,
                                           isCancelled: { false })!
        func ruleID(_ path: String) -> String? { report.rule(for: tree.find(path: path)!, tree: tree)?.id }
        XCTAssertEqual(ruleID(base + "/virtualenvs/app-x1-py3.12/lib/numpy.so"), "poetry.virtualenvs")
        XCTAssertEqual(ruleID(base + "/cache/repositories/x"), "poetry.cache")
        XCTAssertEqual(ruleID("/Users/tester/Library/Caches/com.example.app/blob"), "caches.thirdparty")
    }

    /// Gem caches inside a Ruby install get their own rule, and Homebrew's own Ruby and gems stay protected.
    func testRubyGemCachesAndHomebrewsOwnRuby() {
        let gems = "/Users/tester/.rbenv/versions/3.4.12/lib/ruby/gems/3.4.0"
        let brew = "/opt/homebrew/Library/Homebrew/vendor"
        let app = "/Users/tester/Projects/app/vendor/bundle/ruby/3.4.0"
        let tree = makeTree([file(gems + "/cache/rails-8.1.4.1.gem", 9), file(gems + "/specifications/rails-8.1.4.1.gemspec", 1),
                             file(gems + "/gems/rails-8.1.4.1/README.md", 3), file(app + "/gems/nokogiri-1.18/lib/nokogiri.rb", 4),
                             file(brew + "/bundle/ruby/3.4.0/gems/sorbet-1/lib/sorbet.rb", 5),
                             file(brew + "/portable-ruby/4.0.9/lib/ruby/gems/4.0.0/cache/json.gem", 6),
                             file(brew + "/portable-ruby/4.0.9/lib/ruby/gems/4.0.0/specifications/json.gemspec", 1)])
        let report = ReclaimEngine.analyze(lens: TreeLens(tree: tree), home: testHome, rules: repoRules,
                                           isCancelled: { false })!
        func ruleID(_ path: String) -> String? { report.rule(for: tree.find(path: path)!, tree: tree)?.id }
        XCTAssertEqual(ruleID(gems + "/cache/rails-8.1.4.1.gem"), "ruby.gem-cache")
        XCTAssertEqual(ruleID(gems + "/gems/rails-8.1.4.1/README.md"), "rbenv.versions")
        XCTAssertEqual(ruleID(app + "/gems/nokogiri-1.18/lib/nokogiri.rb"), "bundler.vendor")
        XCTAssertEqual(ruleID(brew + "/bundle/ruby/3.4.0/gems/sorbet-1/lib/sorbet.rb"), "homebrew.program")
        XCTAssertEqual(ruleID(brew + "/portable-ruby/4.0.9/lib/ruby/gems/4.0.0/cache/json.gem"), "homebrew.program")
    }
}

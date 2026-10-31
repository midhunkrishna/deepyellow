import DYCore
import XCTest
@testable import DYAdvisor

final class ReclaimEngineTests: XCTestCase {
    private func analyze(_ tree: FileTree, rules: [ReclaimRule] = ReclaimEngine.builtinRules) -> ReclaimReport {
        ReclaimEngine.analyze(lens: TreeLens(tree: tree), home: testHome, rules: rules, isCancelled: { false })!
    }

    private func tier(_ report: ReclaimReport, _ tree: FileTree, _ path: String) -> SafetyTier {
        SafetyTier(rawValue: report.nodeTier[Int(tree.find(path: path)!)])!
    }

    private func custom(_ id: String, _ pattern: String, _ tier: SafetyTier) -> ReclaimRule {
        ReclaimRule(id: id, title: id, pattern: pattern, tier: tier, whatItIs: "x", consequence: "y")
    }

    func testNeverAncestorBeatsNestedSafeRule() {
        let tree = makeTree([file("/Users/tester/Library/Mail/V10/Logs/a.log", 100), file("/Users/tester/Library/Logs/b.log", 50)])
        let rules = [custom("mail", "~/Library/Mail", .never), custom("logs", "**/Logs", .safe)]
        let report = analyze(tree, rules: rules)
        XCTAssertEqual(tier(report, tree, "/Users/tester/Library/Mail/V10/Logs/a.log"), .never)
        XCTAssertEqual(report.rule(for: tree.find(path: "/Users/tester/Library/Mail/V10/Logs")!, tree: tree)?.id, "mail")
        XCTAssertEqual(tier(report, tree, "/Users/tester/Library/Logs/b.log"), .safe)
    }

    func testBuiltinNeverAncestorBeatsNestedRebuildRule() {
        let tree = makeTree([file("/Users/tester/Pictures/Lib.photoslibrary/proj/node_modules/x.js", 10),
                             file("/Users/tester/Pictures/Lib.photoslibrary/proj/package-lock.json", 1)])
        let report = analyze(tree)
        XCTAssertEqual(tier(report, tree, "/Users/tester/Pictures/Lib.photoslibrary/proj/node_modules"), .never)
    }

    func testMostSpecificMatchWinsBelowNonNeverAncestor() {
        let tree = makeTree([file("/Users/tester/Library/Caches/Foo/Offline/song.bin", 500), file("/Users/tester/Library/Caches/Foo/tmp.bin", 300)])
        let report = analyze(tree)
        XCTAssertEqual(tier(report, tree, "/Users/tester/Library/Caches/Foo/tmp.bin"), .rebuild)
        XCTAssertEqual(tier(report, tree, "/Users/tester/Library/Caches/Foo/Offline/song.bin"), .review)
        let rebuild = report.families.first { $0.rule.id == "caches.thirdparty" }!
        XCTAssertEqual(rebuild.bytes, 300, "the review part is carved out of the enclosing family")
    }

    func testCachesExceptions() {
        let base = "/Users/tester/Library/Caches"
        let tree = makeTree([
            file("\(base)/com.vendor.app/x", 1), file("\(base)/com.apple.akd/x", 1), file("\(base)/com.apple.Safari/x", 1),
            file("\(base)/com.apple.dt.Xcode/x", 1), file("\(base)/Homebrew/x", 1), file("\(base)/JetBrains/IntelliJ2024/x", 1),
            file("\(base)/com.spotify.client/Storage/x", 1), file("\(base)/Google/Chrome/x", 1),
            file("\(base)/com.other.app/Drafts/x", 1), file("\(base)/com.other.app/store.sqlite", 1),
            file("\(base)/com.other.app/Cache.sqlite", 1),
        ])
        let report = analyze(tree)
        XCTAssertEqual(tier(report, tree, "\(base)/com.vendor.app"), .rebuild)
        XCTAssertEqual(tier(report, tree, "\(base)/com.apple.akd"), .never)
        XCTAssertEqual(tier(report, tree, "\(base)/com.apple.Safari"), .never)
        XCTAssertEqual(tier(report, tree, "\(base)/com.apple.dt.Xcode"), .rebuild, "exception beats com.apple.*")
        XCTAssertEqual(tier(report, tree, "\(base)/Homebrew"), .safe)
        XCTAssertEqual(report.rule(for: tree.find(path: "\(base)/Homebrew")!, tree: tree)?.cleanupCommand, "brew cleanup")
        XCTAssertEqual(tier(report, tree, "\(base)/JetBrains/IntelliJ2024"), .review)
        XCTAssertEqual(tier(report, tree, "\(base)/com.spotify.client/Storage"), .rebuild)
        XCTAssertEqual(tier(report, tree, "\(base)/Google/Chrome"), .rebuild)
        XCTAssertEqual(tier(report, tree, "\(base)/com.other.app/Drafts"), .review)
        XCTAssertEqual(tier(report, tree, "\(base)/com.other.app/store.sqlite"), .review)
        XCTAssertEqual(tier(report, tree, "\(base)/com.other.app/Cache.sqlite"), .rebuild)
    }

    func testProjectMarkerRulesNeedSibling() {
        let tree = makeTree([
            file("/Users/tester/code/rs/Cargo.toml", 1), file("/Users/tester/code/rs/target/debug/a", 900),
            file("/Users/tester/code/other/target/a", 10),
            file("/Users/tester/code/js/package-lock.json", 1), file("/Users/tester/code/js/node_modules/a/node_modules/b", 40),
            file("/Users/tester/code/loose/node_modules/a", 20),
        ])
        let report = analyze(tree)
        XCTAssertEqual(tier(report, tree, "/Users/tester/code/rs/target"), .rebuild)
        XCTAssertEqual(tier(report, tree, "/Users/tester/code/other/target"), .unknown)
        XCTAssertEqual(tier(report, tree, "/Users/tester/code/js/node_modules"), .rebuild)
        XCTAssertEqual(tier(report, tree, "/Users/tester/code/js/node_modules/a/node_modules"), .rebuild, "nested folder stays in the same family")
        XCTAssertEqual(tier(report, tree, "/Users/tester/code/loose/node_modules"), .review, "no lockfile caps at review")
    }

    func testCargoKeepsCredentialsAndBin() {
        let tree = makeTree([file("/Users/tester/.cargo/registry/a", 5), file("/Users/tester/.cargo/bin/rustc", 5), file("/Users/tester/.cargo/credentials.toml", 1)])
        let report = analyze(tree)
        XCTAssertEqual(tier(report, tree, "/Users/tester/.cargo/registry"), .rebuild)
        XCTAssertEqual(tier(report, tree, "/Users/tester/.cargo/bin"), .never)
        XCTAssertEqual(tier(report, tree, "/Users/tester/.cargo/credentials.toml"), .never)
        XCTAssertEqual(tier(report, tree, "/Users/tester/.cargo"), .unknown)
    }

    func testRestrictedNodesAreNeverAndFamiliesAreOrdered() {
        let tree = makeTree([file("/System/Library/x", 1000, .restricted), file("/Users/tester/Library/Logs/a", 10),
                             file("/Users/tester/.npm/a", 5000), file("/Users/tester/.Trash/t", 1)])
        let report = analyze(tree)
        XCTAssertEqual(tier(report, tree, "/System/Library/x"), .never)
        let tiers = report.families.map(\.rule.tier.rawValue)
        XCTAssertEqual(tiers, tiers.sorted())
        XCTAssertEqual(report.families.first?.rule.id, "logs")
        XCTAssertEqual(report.nodeTier.count, tree.count)
    }

    func testNeverFamiliesReclaimNothingAndOthersReportBytes() {
        let tree = makeTree([file("/Users/tester/Library/Mail/m", 700), file("/Users/tester/.npm/a", 300)])
        let report = analyze(tree)
        XCTAssertEqual(report.families.first { $0.rule.id == "mail.store" }?.reclaimable, 0)
        let npm = report.families.first { $0.rule.id == "npm.cache" }!
        XCTAssertEqual(npm.bytes, 300)
        XCTAssertEqual(npm.reclaimable, 300)
        XCTAssertEqual(npm.newestModified, 1000)
    }

    func testCancellationReturnsNil() {
        let tree = makeTree([file("/Users/tester/.npm/a", 1)])
        let report = ReclaimEngine.analyze(lens: TreeLens(tree: tree), home: testHome, rules: ReclaimEngine.builtinRules, isCancelled: { true })
        XCTAssertNil(report)
    }

    func testRulesDoNotMatchOutsideScannedRoot() {
        let tree = makeTree([file("/opt/data/a", 1)])
        let report = analyze(tree)
        XCTAssertTrue(report.families.isEmpty)
    }
}

final class BuiltinRulesTests: XCTestCase {
    func testEveryRuleIsWellFormed() {
        let rules = ReclaimEngine.builtinRules
        XCTAssertEqual(Set(rules.map(\.id)).count, rules.count, "ids are unique")
        for rule in rules {
            XCTAssertFalse(rule.whatItIs.isEmpty)
            XCTAssertFalse(rule.consequence.isEmpty)
            XCTAssertNotEqual(rule.tier, .unknown)
            XCTAssertEqual(rule.consequence.filter { ".!?".contains($0) }.count, rule.consequence.hasSuffix(".") ? 1 : 0 + 1, rule.id + " is one sentence")
            for part in rule.pattern.components(separatedBy: " || ") {
                XCTAssertNotNil(CompiledPattern(pattern: part, home: testHome), rule.id + ": " + part)
            }
        }
    }

    func testNoTierUpgradesForKnownRisks() {
        let byID = Dictionary(uniqueKeysWithValues: ReclaimEngine.builtinRules.map { ($0.id, $0) })
        XCTAssertEqual(byID["mail.store"]?.tier, .never)
        XCTAssertEqual(byID["photos.library"]?.tier, .never)
        XCTAssertEqual(byID["docker.raw"]?.tier, .review)
        XCTAssertEqual(byID["xcode.archives"]?.tier, .review)
        XCTAssertEqual(byID["maven.repository"]?.tier, .review)
        XCTAssertEqual(byID["system.varfolders"]?.tier, .never)
        XCTAssertEqual(byID["logs"]?.tier, .safe)
        XCTAssertEqual(ReclaimEngine.builtinRules.filter { $0.tier == .safe }.count, 2)
    }

    func testGlobMatching() {
        XCTAssertTrue(PatternMatcher.matches(spec: "*.dmg|*.pkg", name: "Foo.PKG"))
        XCTAssertFalse(PatternMatcher.matches(spec: "*.dmg|*.pkg", name: "Foo.txt"))
        XCTAssertTrue(PatternMatcher.matches(spec: "*.sqlite&!*cache*", name: "a.sqlite"))
        XCTAssertFalse(PatternMatcher.matches(spec: "*.sqlite&!*cache*", name: "Cache.sqlite"))
    }
}

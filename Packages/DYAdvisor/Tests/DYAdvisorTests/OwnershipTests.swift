import DYCore
import XCTest
@testable import DYAdvisor

/// A catalog backed by tables, so no test depends on what is installed.
struct FakeCatalog: AppCatalog {
    var bundleIDs: [String: String] = [:]
    var names: [String: String] = [:]
    var teams: [String: String] = [:]

    func app(bundleID: String) -> AppIdentity? {
        bundleIDs[bundleID.lowercased()].map { AppIdentity(bundleID: bundleID, name: $0) }
    }
    func app(named name: String) -> AppIdentity? { names[name.lowercased()].map { AppIdentity(bundleID: nil, name: $0) } }
    func app(teamID: String) -> AppIdentity? { teams[teamID].map { AppIdentity(bundleID: nil, name: $0) } }
    func relatedApp(toBundleID id: String) -> AppIdentity? {
        let vendor = id.split(separator: ".").prefix(2).joined(separator: ".").lowercased()
        return bundleIDs.first { $0.key.hasPrefix(vendor + ".") }.map { AppIdentity(bundleID: $0.key, name: $0.value) }
    }
}

final class OwnershipTests: XCTestCase {
    private let lib = testHome + "/Library"
    private let catalog = FakeCatalog(
        bundleIDs: ["com.foo.here": "Here", "com.vendor.app": "Vendor App"],
        names: ["here": "Here", "my editor": "My Editor"], teams: ["TEAM123456": "Teamed"])

    private func analyze(_ entries: [(String, UInt64, NodeFlags)], root: String = "/") throws -> (FileTree, OwnershipReport) {
        let tree = makeTree(entries, root: root)
        let report = OwnershipEngine.analyze(lens: TreeLens(tree: tree), home: testHome, catalog: catalog, isCancelled: { false })
        return (tree, try XCTUnwrap(report))
    }

    private func ownership(_ path: String, _ tree: FileTree, _ report: OwnershipReport) -> Ownership? {
        report.owner(of: tree.find(path: path)!, tree: tree)?.ownership
    }

    /// Bundle-id-shaped names with no matching app are `notInstalled`; installed apps and related ones are not.
    func testBundleIdentifiers() throws {
        let (tree, report) = try analyze([
            file(lib + "/Containers/com.gone.app/Data/x", 5_000), file(lib + "/Containers/com.foo.here/Data/x", 4_000),
            file(lib + "/Caches/com.foo.here.helper/x", 3_000), file(lib + "/Caches/com.vendor.updater/x", 2_000),
            file(lib + "/Caches/com.apple.Safari/x", 9_000), file(lib + "/Preferences/com.gone.app.plist", 100),
            file(lib + "/Saved Application State/com.gone.app.savedState/x", 100),
        ])
        XCTAssertEqual(ownership(lib + "/Containers/com.gone.app", tree, report), .notInstalled(bundleID: "com.gone.app"))
        XCTAssertEqual(ownership(lib + "/Preferences/com.gone.app.plist", tree, report), .notInstalled(bundleID: "com.gone.app"))
        XCTAssertEqual(ownership(lib + "/Saved Application State/com.gone.app.savedState", tree, report), .notInstalled(bundleID: "com.gone.app"))
        XCTAssertEqual(ownership(lib + "/Containers/com.foo.here", tree, report), .installed(AppIdentity(bundleID: "com.foo.here", name: "Here")))
        XCTAssertEqual(ownership(lib + "/Caches/com.foo.here.helper", tree, report), .installed(AppIdentity(bundleID: "com.foo.here", name: "Here")))
        XCTAssertNil(ownership(lib + "/Caches/com.vendor.updater", tree, report),
                     "another app from the same vendor is installed, so no verdict")
        XCTAssertNil(ownership(lib + "/Caches/com.apple.Safari", tree, report), "Apple's own folders get no verdict")
    }

    /// Group containers are judged by their suffix and team id.
    func testGroupContainers() throws {
        let (tree, report) = try analyze([
            file(lib + "/Group Containers/ABCDE12345.com.gone.app/x", 5_000),
            file(lib + "/Group Containers/group.com.gone.other/x", 5_000),
            file(lib + "/Group Containers/ABCDE12345.com.foo.here/x", 5_000),
            file(lib + "/Group Containers/TEAM123456.com.new.thing/x", 5_000),
            file(lib + "/Group Containers/group.com.apple.notes/x", 5_000),
        ])
        XCTAssertEqual(ownership(lib + "/Group Containers/ABCDE12345.com.gone.app", tree, report), .notInstalled(bundleID: "com.gone.app"))
        XCTAssertEqual(ownership(lib + "/Group Containers/group.com.gone.other", tree, report), .notInstalled(bundleID: "com.gone.other"))
        guard case .installed = ownership(lib + "/Group Containers/ABCDE12345.com.foo.here", tree, report) else { return XCTFail("suffix matches") }
        guard case .installed = ownership(lib + "/Group Containers/TEAM123456.com.new.thing", tree, report) else { return XCTFail("team matches") }
        XCTAssertNil(ownership(lib + "/Group Containers/group.com.apple.notes", tree, report))
    }

    /// Plain names count only in Application Support, and only as a guess.
    func testPlainNames() throws {
        let (tree, report) = try analyze([
            file(lib + "/Application Support/Forgotten Tool/x", 5_000), file(lib + "/Application Support/Here/x", 5_000),
            file(lib + "/Application Support/My Editor/x", 5_000), file(lib + "/Caches/Some Tool/x", 5_000),
            file(lib + "/Application Support/CloudDocs/x", 5_000), file(lib + "/Application Support/empty/", 0),
        ])
        XCTAssertEqual(ownership(lib + "/Application Support/Forgotten Tool", tree, report), .possiblyNotInstalled(name: "Forgotten Tool"))
        guard case .installed = ownership(lib + "/Application Support/Here", tree, report) else { return XCTFail("installed by name") }
        guard case .installed = ownership(lib + "/Application Support/My Editor", tree, report) else { return XCTFail("installed by name") }
        XCTAssertNil(ownership(lib + "/Caches/Some Tool", tree, report))
        XCTAssertNil(ownership(lib + "/Application Support/CloudDocs", tree, report), "system folder")
    }

    /// Only direct children count, files inside resolve to their owner, and sizes and dates come from the lens.
    func testOwnerLookupAndTotals() throws {
        let builder = TreeBuilder(rootPath: "/")
        var ids: [String: NodeID] = ["": 0]
        func add(_ path: String, bytes: UInt64 = 0, modified: Int32 = 0, directory: Bool = false) {
            let parent = (path as NSString).deletingLastPathComponent
            var ancestors: [String] = []
            var current = parent
            while ids[current] == nil, current != "/" { ancestors.append(current); current = (current as NSString).deletingLastPathComponent }
            for dirPath in ancestors.reversed() {
                ids[dirPath] = builder.add(parent: ids[(dirPath as NSString).deletingLastPathComponent] ?? 0,
                                           name: (dirPath as NSString).lastPathComponent, record: NodeRecord(flags: .directory))
            }
            ids[path] = builder.add(parent: ids[parent] ?? 0, name: (path as NSString).lastPathComponent,
                                    record: NodeRecord(allocated: bytes, logical: bytes, modified: modified, flags: directory ? .directory : []))
        }
        ids["/"] = 0
        add(lib + "/Containers/com.gone.app/Data/a", bytes: 1_000, modified: 50)
        add(lib + "/Containers/com.gone.app/Data/deep/b", bytes: 2_000, modified: 90)
        let tree = builder.freeze()
        let report = try XCTUnwrap(OwnershipEngine.analyze(lens: TreeLens(tree: tree), home: testHome, catalog: catalog, isCancelled: { false }))
        let deep = tree.find(path: lib + "/Containers/com.gone.app/Data/deep/b")!
        let folder = try XCTUnwrap(report.owner(of: deep, tree: tree))
        XCTAssertEqual(folder.bytes, 3_000)
        XCTAssertEqual(folder.newestModified, 90)
        XCTAssertEqual(tree.path(folder.node), lib + "/Containers/com.gone.app")
        XCTAssertNil(report.owner(of: tree.find(path: lib + "/Containers")!, tree: tree), "the parent folder itself has no owner")
        XCTAssertEqual(report.folders.count, 1)
    }

    /// Ownership never changes a tier and cancelling returns nil.
    func testCancelAndNoTierChange() throws {
        let tree = makeTree([file(lib + "/Caches/com.gone.app/x", 5_000)])
        XCTAssertNil(OwnershipEngine.analyze(lens: TreeLens(tree: tree), home: testHome, catalog: catalog, isCancelled: { true }))
        let rules = ReclaimEngine.builtinRules
        let before = ReclaimEngine.analyze(lens: TreeLens(tree: tree), home: testHome, rules: rules, isCancelled: { false })?.nodeTier
        _ = OwnershipEngine.analyze(lens: TreeLens(tree: tree), home: testHome, catalog: catalog, isCancelled: { false })
        XCTAssertEqual(before, ReclaimEngine.analyze(lens: TreeLens(tree: tree), home: testHome, rules: rules, isCancelled: { false })?.nodeTier)
    }
}

final class SystemAppCatalogTests: XCTestCase {
    /// Writes a minimal app bundle with an Info.plist into `directory`.
    private func makeApp(_ name: String, bundleID: String, in directory: String, display: String? = nil) throws {
        let contents = directory + "/" + name + ".app/Contents"
        try FileManager.default.createDirectory(atPath: contents, withIntermediateDirectories: true)
        var plist: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleName": name]
        if let display { plist["CFBundleDisplayName"] = display }
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: URL(fileURLWithPath: contents + "/Info.plist"))
    }

    /// Apps are found by bundle id and by name, including one folder down and by display name.
    func testFindsInstalledApps() throws {
        let root = NSTemporaryDirectory() + "dyadvisor-apps-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: root) }
        try makeApp("Alpha", bundleID: "com.vendor.alpha", in: root)
        try makeApp("Beta", bundleID: "org.other.beta", in: root + "/Suite", display: "Beta Pro")
        let catalog = SystemAppCatalog(searchDirectories: [root], usesLaunchServices: false)
        XCTAssertEqual(catalog.app(bundleID: "COM.vendor.Alpha")?.name, "Alpha")
        XCTAssertEqual(catalog.app(named: "beta pro")?.bundleID, "org.other.beta")
        XCTAssertEqual(catalog.app(named: "Alpha")?.bundleID, "com.vendor.alpha")
        XCTAssertNil(catalog.app(bundleID: "com.vendor.missing"))
        XCTAssertNil(catalog.app(named: "Nothing Here"))
        XCTAssertEqual(catalog.relatedApp(toBundleID: "com.vendor.updater")?.bundleID, "com.vendor.alpha")
        XCTAssertNil(catalog.relatedApp(toBundleID: "net.nobody.thing"))
    }

    /// A short folder name is matched against the start of an app's name, not against unrelated apps.
    func testNameMatchingIsCautiousButGenerous() throws {
        let root = NSTemporaryDirectory() + "dyadvisor-apps-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: root) }
        try makeApp("Adobe Photoshop 2024", bundleID: "com.adobe.Photoshop", in: root)
        let catalog = SystemAppCatalog(searchDirectories: [root], usesLaunchServices: false)
        XCTAssertNotNil(catalog.app(named: "Adobe"))
        XCTAssertNotNil(catalog.app(named: "Photoshop"))
        XCTAssertNil(catalog.app(named: "Ado"))
    }
}

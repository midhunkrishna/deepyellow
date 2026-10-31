import DYCore
import XCTest
@testable import DYAdvisor

final class WorklistTests: XCTestCase {
    private let day: Int32 = 86_400
    private let now: Int32 = 1_800_000_000
    private let mb: UInt64 = 1_000_000

    /// Builds a tree from (absolute path, bytes, modified) files, creating the folders between.
    private func tree(_ files: [(String, UInt64, Int32)], flags: [String: NodeFlags] = [:]) -> FileTree {
        let builder = TreeBuilder(rootPath: "/")
        var ids: [String: NodeID] = ["/": 0]
        func directory(_ path: String) -> NodeID {
            if let id = ids[path] { return id }
            let parent = directory((path as NSString).deletingLastPathComponent)
            let id = builder.add(parent: parent, name: (path as NSString).lastPathComponent, record: NodeRecord(flags: .directory))
            ids[path] = id
            return id
        }
        for (path, bytes, modified) in files {
            let parent = directory((path as NSString).deletingLastPathComponent)
            ids[path] = builder.add(parent: parent, name: (path as NSString).lastPathComponent,
                                    record: NodeRecord(allocated: bytes, logical: bytes, modified: modified, flags: flags[path] ?? []))
        }
        return builder.freeze()
    }

    private func compute(_ tree: FileTree, duplicates: DuplicateReport? = nil, ownership: OwnershipReport? = nil,
                         decisions: [UInt8]? = nil, rules: [ReclaimRule]? = nil) throws -> [Worklist] {
        let lens = TreeLens(tree: tree)
        let report = try XCTUnwrap(ReclaimEngine.analyze(lens: lens, home: testHome, rules: rules ?? [], isCancelled: { false }))
        return WorklistEngine.compute(lens: lens, report: report, ownership: ownership ?? OwnershipReport(folders: []),
                                      duplicates: duplicates, decisions: decisions ?? [UInt8](repeating: 0, count: tree.count), now: now)
    }

    private func list(_ kind: WorklistKind, _ lists: [Worklist]) -> Worklist? { lists.first { $0.kind == kind } }

    /// Big old things are forgotten; big recent ones and small old ones are not. Files and folders are peers.
    func testForgotten() throws {
        let old = now - 400 * day, recent = now - 10 * day
        let t = tree([("/u/old.mov", 500 * mb, old), ("/u/new.mov", 500 * mb, recent), ("/u/tiny.txt", 1 * mb, old),
                      ("/u/proj/a.bin", 150 * mb, old), ("/u/proj/b.bin", 10 * mb, old),
                      ("/u/mixed/a.bin", 300 * mb, old), ("/u/mixed/b.bin", 300 * mb, recent)])
        let forgotten = try XCTUnwrap(list(.forgotten, try compute(t)))
        let paths = Set(forgotten.nodes.map { t.path($0) })
        XCTAssertTrue(paths.contains("/u/old.mov"))
        XCTAssertTrue(paths.contains("/u/proj/a.bin"), "the big file is the thing; the small remainder is not listed")
        XCTAssertFalse(paths.contains("/u/proj/b.bin"))
        XCTAssertTrue(paths.contains("/u/mixed/a.bin"))
        XCTAssertFalse(paths.contains("/u/new.mov"))
        XCTAssertFalse(paths.contains("/u/tiny.txt"))
        XCTAssertFalse(paths.contains("/u/mixed/b.bin"))
        XCTAssertFalse(paths.contains("/u/mixed"))
        XCTAssertEqual(forgotten.bytes, 500 * mb + 150 * mb + 300 * mb)
        XCTAssertEqual(forgotten.files, 3)
        XCTAssertFalse(forgotten.why.isEmpty)
    }

    /// Never-tier, protected and decided items are left out of every list.
    func testExclusions() throws {
        let old = now - 800 * day
        let t = tree([("/u/keepsake.mov", 500 * mb, old), ("/u/sip.bin", 400 * mb, old), ("/u/chosen.mov", 300 * mb, old),
                      ("/u/ok.mov", 200 * mb, old), ("/u/vault/x.bin", 600 * mb, old)], flags: ["/u/sip.bin": .restricted])
        let never = ReclaimRule(id: "never", title: "Vault", pattern: "/u/vault", tier: .never, whatItIs: "w", consequence: "c")
        var decisions = [UInt8](repeating: 0, count: t.count)
        decisions[Int(t.find(path: "/u/chosen.mov")!)] = Decision.keep.rawValue
        let lists = try compute(t, decisions: decisions, rules: [never])
        for kind in [WorklistKind.forgotten, .largestUndecided] {
            let paths = Set((list(kind, lists)?.nodes ?? []).map { t.path($0) })
            XCTAssertEqual(paths.contains("/u/ok.mov"), true, "\(kind)")
            for excluded in ["/u/sip.bin", "/u/chosen.mov", "/u/vault", "/u/vault/x.bin"] {
                XCTAssertFalse(paths.contains(excluded), "\(excluded) in \(kind)")
            }
        }
    }

    /// Largest undecided is the top of the cut, biggest first, capped at a screenful.
    func testLargestUndecided() throws {
        let files = (1...40).map { ("/u/f\($0).bin", UInt64($0) * 10 * mb, now - day) }
        let t = tree(files)
        let largest = try XCTUnwrap(list(.largestUndecided, try compute(t)))
        XCTAssertLessThanOrEqual(largest.nodes.count, 25)
        XCTAssertEqual(t.path(largest.nodes[0]), "/u/f40.bin")
        XCTAssertEqual(largest.nodes.map { t.allocated($0) }, largest.nodes.map { t.allocated($0) }.sorted(by: >))
        XCTAssertEqual(largest.bytes, largest.nodes.reduce(0) { $0 + t.allocated($1) })
    }

    /// Duplicates list the copies beyond the oldest one in each set, and count only their bytes.
    func testDuplicates() throws {
        let t = tree([("/u/a.bin", 50 * mb, 100), ("/u/b.bin", 50 * mb, 200), ("/u/c.bin", 50 * mb, 300), ("/u/solo.bin", 1, 1)])
        let ids = ["/u/a.bin", "/u/b.bin", "/u/c.bin"].map { t.find(path: $0)! }
        let report = DuplicateReport(sets: [DuplicateSet(id: "x", nodes: ids, size: 50 * mb)], bytesHashed: 0, skippedDataless: 0)
        let lists = try compute(t, duplicates: report)
        let duplicates = try XCTUnwrap(list(.duplicates, lists))
        XCTAssertEqual(Set(duplicates.nodes.map { t.path($0) }), ["/u/b.bin", "/u/c.bin"])
        XCTAssertEqual(duplicates.bytes, 100 * mb)
        XCTAssertEqual(duplicates.files, 2)
        XCTAssertNil(list(.duplicates, try compute(t)), "no duplicate report, no list")
    }

    /// Leftovers combine both kinds of unowned folder, biggest first, and say that some are guesses.
    func testLeftovers() throws {
        let t = tree([("/u/Library/Containers/com.gone.app/x", 5 * mb, 1), ("/u/Library/Application Support/Old Tool/x", 9 * mb, 1),
                      ("/u/Library/Containers/com.here.app/x", 7 * mb, 1)])
        func folder(_ path: String, _ ownership: Ownership) -> OwnedFolder {
            let node = t.find(path: path)!
            return OwnedFolder(node: node, ownership: ownership, bytes: t.allocated(node), newestModified: 1)
        }
        let report = OwnershipReport(folders: [
            folder("/u/Library/Containers/com.gone.app", .notInstalled(bundleID: "com.gone.app")),
            folder("/u/Library/Application Support/Old Tool", .possiblyNotInstalled(name: "Old Tool")),
            folder("/u/Library/Containers/com.here.app", .installed(AppIdentity(bundleID: "com.here.app", name: "Here"))),
        ])
        let leftovers = try XCTUnwrap(list(.leftovers, try compute(t, ownership: report)))
        XCTAssertEqual(leftovers.nodes.map { t.path($0) }, ["/u/Library/Application Support/Old Tool", "/u/Library/Containers/com.gone.app"])
        XCTAssertEqual(leftovers.bytes, 14 * mb)
        XCTAssertTrue(leftovers.why.contains("guess"))
    }

    /// The leftovers sentence reads correctly for one and for many.
    func testLeftoversWording() {
        XCTAssertEqual(WorklistEngine.leftoversWhy(sure: 1, guesses: 0, bytes: 5_000_000),
                       "1 folder in your Library is named for an app that isn't installed. 5.00 MB in all.")
        XCTAssertEqual(WorklistEngine.leftoversWhy(sure: 3, guesses: 1, bytes: 5_000_000),
                       "3 folders in your Library are named for an app that isn't installed, and 1 more looks like it but that is a guess. 5.00 MB in all.")
        XCTAssertEqual(WorklistEngine.leftoversWhy(sure: 2, guesses: 4, bytes: 5_000_000),
                       "2 folders in your Library are named for an app that isn't installed, and 4 more look like that but that is a guess. 5.00 MB in all.")
        XCTAssertTrue(WorklistEngine.leftoversWhy(sure: 0, guesses: 1, bytes: 1).hasPrefix("1 folder in your Library looks like it belongs"))
        XCTAssertTrue(WorklistEngine.leftoversWhy(sure: 0, guesses: 2, bytes: 1).hasPrefix("2 folders in your Library look like they belong"))
    }

    /// Lists with nothing to say are left out.
    func testEmptyListsAreOmitted() throws {
        let t = tree([("/u/a.txt", 10, now)])
        XCTAssertEqual(try compute(t).map(\.kind), [.largestUndecided])
    }
}

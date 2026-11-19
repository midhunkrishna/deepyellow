import DYCore
import DYAdvisor
import Foundation

let testHome = "/Users/tester"

/// Builds a tree from slash paths under `/`, creating missing folders. Each entry is (path, bytes, extra flags).
/// Paths ending in `/` are directories. Bytes of files roll up into their folders.
func makeTree(_ entries: [(String, UInt64, NodeFlags)], root: String = "/") -> FileTree {
    let builder = TreeBuilder(rootPath: root)
    var ids: [String: NodeID] = ["": 0]
    for (path, bytes, flags) in entries {
        let isDir = path.hasSuffix("/")
        let parts = path.split(separator: "/").map(String.init)
        var prefix = ""
        for (offset, part) in parts.enumerated() {
            let parent = ids[prefix]!
            prefix += "/" + part
            let last = offset == parts.count - 1
            if ids[prefix] == nil {
                let dir = !last || isDir
                let record = last
                    ? NodeRecord(allocated: dir ? 0 : bytes, logical: dir ? 0 : bytes, modified: 1000,
                                 flags: dir ? flags.union(.directory) : flags, inode: 0)
                    : NodeRecord(flags: .directory)
                ids[prefix] = builder.add(parent: parent, name: part, record: record)
            } else if last {
                builder.insertFlags(flags, on: ids[prefix]!)
            }
        }
    }
    return builder.freeze()
}

/// A file entry shorthand.
func file(_ path: String, _ bytes: UInt64, _ flags: NodeFlags = []) -> (String, UInt64, NodeFlags) { (path, bytes, flags) }
/// A directory entry shorthand.
func dir(_ path: String, _ flags: NodeFlags = []) -> (String, UInt64, NodeFlags) { (path + "/", 0, flags) }

/// Content store keyed by path. Counts reads and can fail on chosen paths.
final class FakeReader: FileReading, @unchecked Sendable {
    private let lock = NSLock()
    private var contents: [String: Data]
    private var failing: Set<String> = []
    private(set) var reads: [String] = []
    private(set) var maxLength = 0
    private(set) var opens: [String: Int] = [:]
    var onRead: (() -> Void)?

    /// Creates a reader serving `contents`.
    init(_ contents: [String: Data]) { self.contents = contents }

    /// Serves the requested range from the stored content.
    func read(path: String, offset: UInt64, length: Int) throws -> Data {
        lock.lock()
        reads.append(path)
        maxLength = max(maxLength, length)
        let data = contents[path]
        let fails = failing.contains(path)
        lock.unlock()
        onRead?()
        guard let data, !fails else { throw CocoaError(.fileReadNoSuchFile) }
        let start = min(Int(offset), data.count)
        return data.subdata(in: start..<min(start + length, data.count))
    }

    /// Counts one open for `path`, then serves chunks through `read` so reads and limits are still recorded.
    func readChunks(path: String, chunkSize: Int, _ body: (Data) -> Bool) throws {
        lock.withLock { opens[path, default: 0] += 1 }
        var offset: UInt64 = 0
        while true {
            let data = try read(path: path, offset: offset, length: chunkSize)
            if data.isEmpty || !body(data) { return }
            offset += UInt64(data.count)
        }
    }
}

/// The repo's `rules/` folder, found from this file.
let repoRulesDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("rules", isDirectory: true)

/// Every section of the repo's rules, in file order. Fails the test run if the files do not load.
let repoSections: [RuleSection] = try! RuleFiles.load(directory: repoRulesDirectory, home: testHome)

/// Every rule of the repo's rules, in file order.
let repoRules: [ReclaimRule] = repoSections.flatMap(\.rules)

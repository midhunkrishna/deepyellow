import Darwin
import DYCore
import DYScan
import Foundation
import XCTest

/// A private temp directory for one test. Removes only what it created, restoring permissions first.
final class Fixture {
    let root: String
    private var lockedDirectories: [String] = []

    /// Creates an empty directory under the system temp location, resolved so it has no symlink components.
    init() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath().path
        root = base + "/dyscan-test-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    }

    /// The absolute path of a child of the fixture root.
    func path(_ relative: String) -> String { root + "/" + relative }

    /// Creates a directory (and parents) under the fixture root.
    @discardableResult
    func makeDirectory(_ relative: String) throws -> String {
        try FileManager.default.createDirectory(atPath: path(relative), withIntermediateDirectories: true)
        return path(relative)
    }

    /// Writes `count` pseudo-random bytes to a file, creating parent directories.
    @discardableResult
    func writeFile(_ relative: String, count: Int) throws -> String {
        let full = path(relative)
        try FileManager.default.createDirectory(atPath: (full as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        var bytes = [UInt8](repeating: 0, count: count)
        for index in 0..<count { bytes[index] = UInt8.random(in: 0...255) }
        guard FileManager.default.createFile(atPath: full, contents: Data(bytes)) else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        return full
    }

    /// Makes a directory unreadable and remembers to restore it.
    func lock(_ relative: String) {
        chmod(path(relative), 0o000)
        lockedDirectories.append(path(relative))
    }

    /// Restores permissions, then deletes the fixture directory.
    func tearDown() {
        for directory in lockedDirectories { chmod(directory, 0o755) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/rm")
        process.arguments = ["-rf", root]
        try? process.run()
        process.waitUntilExit()
    }

    /// Bytes the filesystem reports as allocated for a path, from `stat`.
    func allocated(_ relative: String) -> UInt64 {
        var info = stat()
        guard lstat(path(relative), &info) == 0 else { return 0 }
        return UInt64(info.st_blocks) * 512
    }
}

/// Runs a scan to completion and returns its final tree, plus every event seen.
func runScan(root: String, workers: Int? = nil, interval: TimeInterval? = nil) async -> (tree: FileTree, events: [ScanEvent]) {
    var options = ScanOptions(root: root)
    if let workers { options.workers = workers }
    if let interval { options.snapshotInterval = interval }
    var events: [ScanEvent] = []
    var final: FileTree?
    for await event in DiskScanner(options: options).start() {
        events.append(event)
        if case .finished(let tree) = event { final = tree }
    }
    return (final!, events)
}

extension FileTree {
    /// The node at a path relative to the tree's root, failing the test if absent.
    func node(_ relative: String, file: StaticString = #filePath, line: UInt = #line) -> NodeID {
        let rootPath = name(0)
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard let id = find(path: prefix + relative) else {
            XCTFail("missing node \(relative)", file: file, line: line)
            return 0
        }
        return id
    }
}

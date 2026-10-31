import Foundation
import XCTest
import DYCore
@testable import DYDecide

/// A sandbox directory that tests may freely create files in. Everything the tests touch lives under it.
final class Sandbox {
    let root: URL

    /// Creates a unique directory under the system temp directory.
    init() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("dydecide-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// Deletes the sandbox. Only ever removes the directory this object created.
    func tearDown() {
        guard root.lastPathComponent.hasPrefix("dydecide-") else { return }
        try? FileManager.default.removeItem(at: root)
    }

    /// A path inside the sandbox.
    func path(_ relative: String) -> String { root.appendingPathComponent(relative).path }

    /// Creates a directory inside the sandbox.
    func directory(_ relative: String) throws {
        try FileManager.default.createDirectory(atPath: path(relative), withIntermediateDirectories: true)
    }

    /// Writes a file inside the sandbox, creating parents.
    @discardableResult
    func file(_ relative: String, _ text: String = "data") throws -> String {
        let full = path(relative)
        try FileManager.default.createDirectory(atPath: (full as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: URL(fileURLWithPath: full))
        return full
    }

    /// Reads a file's text, or nil if it can't be read.
    func read(_ relative: String) -> String? { try? String(contentsOfFile: path(relative), encoding: .utf8) }

    /// Whether anything exists at the path, not following symlinks.
    func exists(_ relative: String) -> Bool { PathProbe.exists(path(relative)) }
}

/// Describes one node for `makeTree`.
struct Spec {
    var size: UInt64 = 1_000
    var flags: NodeFlags = []
    var modified: Int32 = 100
    var inode: UInt64 = 0
}

/// Builds a tree from absolute paths. Missing parent directories are created. Files get their size from the spec.
func makeTree(root: String = "/", _ nodes: [(String, Spec)]) -> FileTree {
    let builder = TreeBuilder(rootPath: root)
    var ids: [String: NodeID] = [root: 0]
    let prefix = root.hasSuffix("/") ? root : root + "/"
    var nextInode: UInt64 = 1
    func ensureDirectory(_ path: String) -> NodeID {
        if let id = ids[path] { return id }
        let parentPath = (path as NSString).deletingLastPathComponent
        let parent = ensureDirectory(parentPath.isEmpty ? "/" : parentPath)
        nextInode += 1
        let id = builder.add(parent: parent, name: (path as NSString).lastPathComponent,
                             record: NodeRecord(flags: .directory, inode: nextInode))
        ids[path] = id
        return id
    }
    for (path, spec) in nodes {
        precondition(path.hasPrefix(prefix))
        let isDirectory = spec.flags.contains(.directory)
        if isDirectory { _ = ensureDirectory(path); builder.insertFlags(spec.flags, on: ids[path]!); continue }
        let parentPath = (path as NSString).deletingLastPathComponent
        let parent = ensureDirectory(parentPath.isEmpty ? "/" : parentPath)
        nextInode += 1
        let id = builder.add(parent: parent, name: (path as NSString).lastPathComponent,
                             record: NodeRecord(allocated: spec.size, logical: spec.size, modified: spec.modified,
                                                flags: spec.flags, inode: spec.inode == 0 ? nextInode : spec.inode))
        ids[path] = id
    }
    return builder.freeze()
}

/// Shorthand for a file spec.
func file(_ size: UInt64 = 1_000, flags: NodeFlags = [], modified: Int32 = 100) -> Spec {
    Spec(size: size, flags: flags, modified: modified)
}

/// Shorthand for a directory spec carrying extra flags.
func dir(_ flags: NodeFlags = []) -> Spec { Spec(flags: flags.union(.directory)) }

/// Builds a tree that mirrors a real directory by walking it with `lstat`, so fingerprints match the disk.
func mirrorTree(of directory: String) throws -> FileTree {
    let builder = TreeBuilder(rootPath: directory)
    func visit(_ path: String, parent: NodeID) throws {
        for name in try FileManager.default.contentsOfDirectory(atPath: path).sorted() {
            let full = path + "/" + name
            var info = stat()
            XCTAssertEqual(lstat(full, &info), 0)
            let isDirectory = (info.st_mode & S_IFMT) == S_IFDIR
            let isLink = (info.st_mode & S_IFMT) == S_IFLNK
            var flags: NodeFlags = isDirectory ? .directory : []
            if isLink { flags.insert(.symlink) }
            let size = isDirectory ? 0 : UInt64(info.st_size)
            let id = builder.add(parent: parent, name: name, record: NodeRecord(
                allocated: size, logical: size, modified: Int32(info.st_mtimespec.tv_sec), flags: flags, inode: UInt64(info.st_ino)))
            if isDirectory { try visit(full, parent: id) }
        }
    }
    try visit(directory, parent: 0)
    return builder.freeze()
}

/// A mover that moves between directories inside a sandbox. It is the only mover the tests ever use.
final class FakeTrash: TrashMoving, @unchecked Sendable {
    let trashDirectory: String
    private let sandboxRoot: String
    private let lock = NSLock()
    private var counter = 0
    private(set) var moveCalls: [String] = []
    var beforeMove: (@Sendable (String) -> Void)?
    var failPaths: Set<String> = []

    /// Creates the fake, with its Trash directory inside `sandbox`.
    init(sandbox: Sandbox) throws {
        sandboxRoot = sandbox.root.path
        trashDirectory = sandbox.path("fake-trash")
        try FileManager.default.createDirectory(atPath: trashDirectory, withIntermediateDirectories: true)
    }

    /// Moves `path` into the fake Trash under a unique name.
    func moveToTrash(path: String) throws -> String {
        let slot = lock.withLock { () -> Int in counter += 1; moveCalls.append(path); return counter }
        beforeMove?(path)
        if failPaths.contains(path) { throw CocoaError(.fileWriteNoPermission) }
        precondition(path.hasPrefix(sandboxRoot + "/"), "move outside the sandbox")
        let target = trashDirectory + "/\(slot)-" + (path as NSString).lastPathComponent
        try FileManager.default.moveItem(atPath: path, toPath: target)
        return target
    }

    /// Moves back with `moveItem`, which refuses to overwrite.
    func moveBack(from: String, to: String) throws {
        try FileManager.default.moveItem(atPath: from, toPath: to)
    }

    /// The real fingerprint of the path.
    func currentFingerprint(path: String) throws -> Fingerprint { try Fingerprint.current(path: path) }
}

/// A mover that records calls and touches nothing. Used where the file system must not be involved.
final class RecordingMover: TrashMoving, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var moved: [String] = []
    var fingerprints: [String: Fingerprint] = [:]

    func moveToTrash(path: String) throws -> String {
        lock.withLock { moved.append(path) }
        return "/fake/trash/" + (path as NSString).lastPathComponent
    }
    func moveBack(from: String, to: String) throws {}
    func currentFingerprint(path: String) throws -> Fingerprint {
        guard let found = fingerprints[path] else { throw CocoaError(.fileNoSuchFile) }
        return found
    }
}

import DYCore
import Foundation

/// Builds small hand-made trees for tests.
final class TreeSketch {
    let builder: TreeBuilder

    init(root: String = "/") { builder = TreeBuilder(rootPath: root) }

    /// Adds a directory.
    @discardableResult
    func dir(_ parent: NodeID, _ name: String, flags: NodeFlags = []) -> NodeID {
        builder.add(parent: parent, name: name, record: NodeRecord(allocated: 0, flags: flags.union(.directory)))
    }

    /// Adds a file.
    @discardableResult
    func file(_ parent: NodeID, _ name: String, _ size: UInt64, modified: Int32 = 0, accessed: Int32 = 0,
              flags: NodeFlags = [], kind: FileKind? = nil) -> NodeID {
        builder.add(parent: parent, name: name, record: NodeRecord(allocated: size, logical: size, modified: modified, accessed: accessed,
                                                                    flags: flags, kind: kind ?? FileKindClassifier.classify(name)))
    }

    /// Freezes the tree.
    func tree() -> FileTree {
        builder.freeze(meta: ScanMeta(rootPath: "/", scannedAt: Date(timeIntervalSince1970: TimeInterval(SyntheticTree.referenceNow))))
    }
}

let megabyte: UInt64 = 1_000_000

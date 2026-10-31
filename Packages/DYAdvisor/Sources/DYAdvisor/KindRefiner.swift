import DYCore
import Foundation

/// The outcome of a kind refinement pass.
public struct KindRefinement: Sendable {
    /// One `FileKind` raw value per node, ready for `FileTree.replacingKinds`.
    public let kinds: [UInt8]
    /// Files whose kind changed.
    public let refinedFiles: Int
    /// Bytes on disk of the files whose kind changed.
    public let refinedBytes: UInt64

    /// Creates a refinement.
    public init(kinds: [UInt8], refinedFiles: Int, refinedBytes: UInt64) {
        self.kinds = kinds
        self.refinedFiles = refinedFiles
        self.refinedBytes = refinedBytes
    }
}

/// Gives files better kinds than their name alone allows, using facts only: the type database, then file signatures.
public enum KindRefiner {
    /// Files read between cancellation checks and yields.
    private static let batch = 64

    /// Refines the kinds of the files visible through `lens`.
    ///
    /// First pass, no reading: a name the extension table couldn't place goes to the type database, and a large `.raw`
    /// becomes an archive. Second pass: files still `other` that are at least `minimumSize` bytes have their first
    /// `SignatureSniffer.headerLength` bytes read and matched. Placeholders, protected files, symlinks and later links to
    /// an already counted file are never read, so nothing is downloaded. Returns nil if `isCancelled` becomes true.
    public static func refine(lens: TreeLens, reader: FileReading, minimumSize: UInt64,
                              isCancelled: @Sendable () -> Bool) async -> KindRefinement? {
        let tree = lens.tree
        var kinds = tree.columns.kind
        var files = 0
        var bytes: UInt64 = 0
        var toRead: [NodeID] = []

        func change(_ index: Int, to kind: FileKind) {
            guard kinds[index] != kind.rawValue else { return }
            kinds[index] = kind.rawValue
            files += 1
            bytes &+= lens.size[index]
        }

        for index in 0..<tree.count {
            if index & 4095 == 0, isCancelled() { return nil }
            guard lens.included[index], !tree.isDirectory(NodeID(index)), !tree.flags(NodeID(index)).contains(.symlink) else { continue }
            let id = NodeID(index)
            switch nameVerdict(tree: tree, id: id, current: kinds[index]) {
            case .change(let kind): change(index, to: kind)
            case .needsContent: if isReadable(tree: tree, id: id, minimumSize: minimumSize) { toRead.append(id) }
            case .keep: break
            }
        }

        for (position, id) in toRead.enumerated() {
            if position % batch == 0 {
                if isCancelled() { return nil }
                await Task.yield()
            }
            guard let header = try? reader.read(path: tree.path(id), offset: 0, length: SignatureSniffer.headerLength),
                  let kind = SignatureSniffer.kind(header: header) else { continue }
            change(Int(id), to: kind)
        }
        return KindRefinement(kinds: kinds, refinedFiles: files, refinedBytes: bytes)
    }

    /// What the name alone says about a file.
    private enum NameVerdict {
        case change(FileKind), needsContent, keep
    }

    /// Decides from the name whether a file's kind changes, needs its content read, or stays.
    private static func nameVerdict(tree: FileTree, id: NodeID, current: UInt8) -> NameVerdict {
        if current == FileKind.image.rawValue {
            let fixed = tree.withName(id) { FileKindClassifier.classify(name: $0, size: tree.logical(id)) }
            return fixed == .image ? .keep : .change(fixed)
        }
        guard current == FileKind.other.rawValue else { return .keep }
        if let ext = tree.withName(id, { FileKindClassifier.fileExtension(name: $0) }),
           let kind = TypeResolver.kind(forExtension: ext) {
            return .change(kind)
        }
        return .needsContent
    }

    /// Whether reading the file is allowed and worthwhile.
    private static func isReadable(tree: FileTree, id: NodeID, minimumSize: UInt64) -> Bool {
        let flags = tree.flags(id)
        guard flags.isDisjoint(with: [.dataless, .restricted, .hardlinkDuplicate, .cloneDuplicate, .unreadable]) else { return false }
        return tree.logical(id) >= max(minimumSize, 1)
    }
}

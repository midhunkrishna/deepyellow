import DYCore
import Foundation

/// Turns directory batches into tree nodes. Owns the `TreeBuilder`, so exactly one thread may call it.
final class TreeAssembler {
    let builder: TreeBuilder
    private(set) var files = 0
    private(set) var directories = 1
    private(set) var unreadable = 0
    private(set) var skippedDirectories = 0
    private(set) var permissionDenied = false
    private(set) var hardlinkBytesSaved: UInt64 = 0
    private(set) var cloneBytesSaved: UInt64 = 0
    private(set) var currentPath: [UInt8] = []

    private var links = LinkDeduper()
    private let packages = PackageExtensions()
    /// Per directory, the names an earlier pass created: a directory's node, or `noNode` for anything else.
    private var overlay: [NodeID: [[UInt8]: NodeID]] = [:]
    private var phase: ScanPhase
    /// Node ids by (worker, sequence), filled as each directory's parent is assembled.
    private var tokenNodes: [[NodeID]]

    /// Creates an assembler whose root node is named `rootPath`.
    init(rootPath: String, phase: ScanPhase, workers: Int, reserving capacity: Int = 1 << 20) {
        tokenNodes = Array(repeating: [], count: workers)
        builder = TreeBuilder(rootPath: rootPath, reserving: capacity)
        self.phase = phase
    }

    /// Switches to the next pass of a multi-pass scan.
    func begin(phase next: ScanPhase) { phase = next }

    /// Adds one directory's entries to the tree and returns how many subdirectory jobs the worker queued for it.
    ///
    /// A directory's batch must be applied before any batch of its subdirectories.
    func apply(_ batch: DirectoryBatch) -> Int {
        currentPath = batch.path
        let node = self.node(for: batch.token)
        if batch.skipped {
            builder.insertFlags(.unreadable, on: node)
            skippedDirectories += 1
            return 0
        }
        if batch.openError != 0 { recordOpenFailure(batch, node: node) }
        else if batch.listError != 0 { recordListFailure(batch, node: node) }
        guard !batch.entries.isEmpty else { return 0 }
        addEntries(of: batch, parent: node)
        return batch.subdirectoryPaths.count
    }

    /// The node a directory token was resolved to. The root token is always node 0.
    private func node(for token: DirectoryToken) -> NodeID {
        token == .root ? 0 : tokenNodes[token.worker][token.sequence]
    }

    /// Records which node a subdirectory token stands for.
    private func bind(_ token: DirectoryToken, to node: NodeID) {
        let worker = token.worker, sequence = token.sequence
        if tokenNodes[worker].count <= sequence {
            tokenNodes[worker].append(contentsOf: repeatElement(noNode, count: sequence + 1 - tokenNodes[worker].count))
        }
        tokenNodes[worker][sequence] = node
    }

    /// Flags a directory that could not be opened, except one that vanished mid-scan.
    private func recordOpenFailure(_ batch: DirectoryBatch, node: NodeID) {
        guard batch.openError != ENOENT || node == 0 else { return }
        builder.insertFlags(.unreadable, on: node)
        unreadable += 1
        if batch.openError == EPERM { permissionDenied = true }
    }

    /// Flags a directory whose listing failed part-way, so its size is known to be incomplete.
    private func recordListFailure(_ batch: DirectoryBatch, node: NodeID) {
        builder.insertFlags(.unreadable, on: node)
        unreadable += 1
        if batch.listError == EPERM { permissionDenied = true }
    }

    /// Adds every entry with rollups deferred, then applies one rollup for the whole directory.
    private func addEntries(of batch: DirectoryBatch, parent: NodeID) {
        var allocated: UInt64 = 0, logical: UInt64 = 0, privateBytes: UInt64 = 0
        var fileCount: UInt32 = 0
        let merge = phase.usesOverlay ? overlay[parent] : nil
        batch.names.withUnsafeBufferPointer { names in
            for var entry in batch.entries {
                let name = UnsafeBufferPointer(rebasing: names[Int(entry.nameOffset)..<(Int(entry.nameOffset) + Int(entry.nameLength))])
                let isDirectory = entry.flags.contains(.directory)
                var node = noNode
                if let merge, let existing = merge[Array(name)] {
                    // The earlier pass already created this name: merge directories, and let it win otherwise.
                    if !isDirectory || existing == noNode { continue }
                    node = existing
                } else {
                    resolveDuplicates(&entry)
                    if isDirectory { prepareDirectory(&entry, name: name) }
                    node = builder.add(parent: parent, name: name, record: record(for: entry), rollup: false)
                    allocated &+= entry.allocated
                    logical &+= entry.logical
                    privateBytes &+= entry.privateBytes
                    if isDirectory { directories += 1 } else { fileCount += 1 }
                    if phase.recordsOverlay && (isDirectory || parent == 0) {
                        overlay[parent, default: [:]][Array(name)] = isDirectory ? node : noNode
                    }
                }
                if entry.subdirectoryIndex >= 0 {
                    bind(batch.firstSubdirectoryToken.advanced(by: Int(entry.subdirectoryIndex)), to: node)
                }
            }
        }
        files += Int(fileCount)
        builder.applyRollup(from: parent, allocated: allocated, logical: logical, privateBytes: privateBytes, files: fileCount)
    }

    /// Zeroes the bytes of a file already counted through another hard link or clone, and records what was saved.
    private func resolveDuplicates(_ entry: inout ScannedEntry) {
        switch entry.dedupe {
        case .none:
            break
        case .hardLink:
            if links.visitHardLink(device: entry.device, fileID: entry.fileID) == .duplicate {
                hardlinkBytesSaved &+= entry.allocated
                entry.allocated = 0
                entry.privateBytes = 0
                entry.flags.insert(.hardlinkDuplicate)
            }
        case .clone:
            if links.visitClone(device: entry.device, cloneID: entry.cloneID) == .duplicate {
                cloneBytesSaved &+= entry.allocated
                entry.allocated = 0
                entry.privateBytes = 0
                entry.flags.insert(.cloneDuplicate)
            }
        }
    }

    /// Marks directories whose extension makes them packages, and gives them the extension's category.
    private func prepareDirectory(_ entry: inout ScannedEntry, name: UnsafeBufferPointer<UInt8>) {
        guard packages.isPackage(name: name) else { return }
        entry.flags.insert(.package)
        entry.kind = FileKindClassifier.classify(name: name)
    }

    /// Builds the tree record for a measured entry.
    private func record(for entry: ScannedEntry) -> NodeRecord {
        NodeRecord(allocated: entry.allocated, logical: entry.logical, privateBytes: entry.privateBytes,
                   modified: entry.modified, accessed: entry.accessed, flags: entry.flags, kind: entry.kind,
                   inode: entry.fileID)
    }
}

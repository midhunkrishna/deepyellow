import CryptoKit
import DYCore
import Foundation

/// Files with identical content.
public struct DuplicateSet: Identifiable, Sendable {
    /// The SHA-256 of the content, in hex.
    public let id: String
    public let nodes: [NodeID]
    /// Size of each member in bytes.
    public let size: UInt64
    /// Bytes freed by keeping one member and removing the rest.
    public var wastedBytes: UInt64 { size &* UInt64(max(nodes.count - 1, 0)) }

    /// Creates a set.
    public init(id: String, nodes: [NodeID], size: UInt64) {
        self.id = id
        self.nodes = nodes
        self.size = size
    }
}

/// The outcome of a duplicate search.
public struct DuplicateReport: Sendable {
    /// Ordered by wasted bytes, largest first.
    public let sets: [DuplicateSet]
    /// Bytes actually read while comparing.
    public let bytesHashed: UInt64
    /// Placeholder files that were left alone because reading them would download them.
    public let skippedDataless: Int

    /// Creates a report.
    public init(sets: [DuplicateSet], bytesHashed: UInt64, skippedDataless: Int) {
        self.sets = sets
        self.bytesHashed = bytesHashed
        self.skippedDataless = skippedDataless
    }
}

/// Reads bytes from a file. A seam so tests never touch real files.
public protocol FileReading: Sendable {
    /// Reads up to `length` bytes starting at `offset`. Returns fewer at the end of the file.
    func read(path: String, offset: UInt64, length: Int) throws -> Data
}

/// Finds files with identical content: group by size, then by head and tail hash, then by full SHA-256.
public enum DuplicateFinder {
    /// The most that is read in one call.
    static let chunk = 1 << 20
    /// Bytes sampled from each end for the cheap comparison.
    static let sample = 64 << 10

    /// Searches `lens` for duplicate files of at least `minimumSize` bytes.
    ///
    /// Skips placeholders (`dataless`), later hard links and clones, protected files, symlinks and anything inside a
    /// package, so a set never counts the same blocks twice. Files sharing an inode count once. `progress` runs from 0
    /// to 1. If cancelled, returns a report with no sets, because an unfinished comparison proves nothing.
    public static func find(lens: TreeLens, minimumSize: UInt64, reader: FileReading,
                            progress: @Sendable (Double) -> Void, isCancelled: @Sendable () -> Bool) async -> DuplicateReport {
        let (candidates, dataless) = candidateGroups(lens: lens, minimumSize: minimumSize)
        var hashed: UInt64 = 0
        let planned = max(candidates.values.reduce(UInt64(0)) { $0 + $1.size * UInt64($1.nodes.count) }, 1)
        var done: UInt64 = 0
        var sets: [DuplicateSet] = []

        for size in candidates.keys.sorted() {
            guard let group = candidates[size] else { continue }
            var byEnds: [String: [NodeID]] = [:]
            for node in group.nodes {
                if isCancelled() { return DuplicateReport(sets: [], bytesHashed: hashed, skippedDataless: dataless) }
                await Task.yield()
                guard let key = endsKey(path: lens.tree.path(node), size: size, reader: reader, hashed: &hashed) else { continue }
                byEnds[key, default: []].append(node)
            }
            for (_, similar) in byEnds where similar.count > 1 {
                var byContent: [String: [NodeID]] = [:]
                for node in similar {
                    if isCancelled() { return DuplicateReport(sets: [], bytesHashed: hashed, skippedDataless: dataless) }
                    await Task.yield()
                    guard let digest = fullHash(path: lens.tree.path(node), size: size, reader: reader, hashed: &hashed,
                                                isCancelled: isCancelled) else { continue }
                    byContent[digest, default: []].append(node)
                }
                for (digest, nodes) in byContent where nodes.count > 1 {
                    sets.append(DuplicateSet(id: digest, nodes: nodes.sorted(), size: size))
                }
            }
            done += size * UInt64(group.nodes.count)
            progress(min(Double(done) / Double(planned), 1))
        }
        if isCancelled() { return DuplicateReport(sets: [], bytesHashed: hashed, skippedDataless: dataless) }
        sets.sort { $0.wastedBytes != $1.wastedBytes ? $0.wastedBytes > $1.wastedBytes : $0.id < $1.id }
        progress(1)
        return DuplicateReport(sets: sets, bytesHashed: hashed, skippedDataless: dataless)
    }

    /// Eligible files grouped by content size, keeping only sizes that more than one distinct file has.
    private static func candidateGroups(lens: TreeLens, minimumSize: UInt64) -> ([UInt64: (size: UInt64, nodes: [NodeID])], Int) {
        let tree = lens.tree
        var inPackage = [Bool](repeating: false, count: tree.count)
        var bySize: [UInt64: [NodeID]] = [:]
        var seenInodes = Set<UInt64>()
        var dataless = 0
        for index in 0..<tree.count {
            let id = NodeID(index)
            let flags = tree.flags(id)
            if index > 0 {
                inPackage[index] = inPackage[Int(tree.parent(id))] || tree.flags(tree.parent(id)).contains(.package)
            }
            guard lens.included[index], !flags.contains(.directory), !flags.contains(.symlink) else { continue }
            let size = tree.logical(id)
            guard size >= max(minimumSize, 1) else { continue }
            if flags.contains(.dataless) { dataless += 1; continue }
            if !flags.isDisjoint(with: [.hardlinkDuplicate, .cloneDuplicate, .restricted]) || inPackage[index] { continue }
            let inode = tree.inode(id)
            if inode != 0, !seenInodes.insert(inode).inserted { continue }
            bySize[size, default: []].append(id)
        }
        var groups: [UInt64: (size: UInt64, nodes: [NodeID])] = [:]
        for (size, nodes) in bySize where nodes.count > 1 { groups[size] = (size, nodes) }
        return (groups, dataless)
    }

    /// A cheap fingerprint from the start and end of a file, or nil if it can't be read.
    private static func endsKey(path: String, size: UInt64, reader: FileReading, hashed: inout UInt64) -> String? {
        let length = Int(min(UInt64(sample), size))
        guard let head = try? reader.read(path: path, offset: 0, length: length),
              let tail = try? reader.read(path: path, offset: size - UInt64(length), length: length) else { return nil }
        hashed &+= UInt64(head.count + tail.count)
        var hasher = SHA256()
        hasher.update(data: head)
        hasher.update(data: tail)
        return hex(hasher.finalize())
    }

    /// The SHA-256 of a whole file, read in chunks, or nil if it can't be read or the search is cancelled.
    private static func fullHash(path: String, size: UInt64, reader: FileReading, hashed: inout UInt64,
                                 isCancelled: @Sendable () -> Bool) -> String? {
        var hasher = SHA256()
        var offset: UInt64 = 0
        while offset < size {
            if isCancelled() { return nil }
            let length = Int(min(UInt64(chunk), size - offset))
            guard let data = try? reader.read(path: path, offset: offset, length: length), !data.isEmpty else { return nil }
            hasher.update(data: data)
            hashed &+= UInt64(data.count)
            offset += UInt64(data.count)
        }
        return hex(hasher.finalize())
    }

    /// Lowercase hex of a digest.
    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}

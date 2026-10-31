import Darwin
import Foundation

/// Measures the bytes that deleting a file or folder would free right now, by asking the kernel for each file's private size.
///
/// Read-only. A file that shares blocks with a clone or snapshot reports only the blocks it owns alone. A hard-linked file
/// counts only when every link to it is inside the measured folder, because otherwise deleting frees nothing.
public struct PrivateSizeProbe: Sendable {
    /// Creates a probe.
    public init() {}

    /// The private bytes under `path`, or nil when anything beneath it can't be read, so a partial sum is never reported.
    public func privateBytes(path: String) -> UInt64? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        var tally = Tally()
        let isDirectory = (info.st_mode & S_IFMT) == S_IFDIR
        if isDirectory {
            guard walk(directory: path, into: &tally) else { return nil }
        } else if (info.st_mode & S_IFMT) == S_IFREG {
            guard let size = Self.privateSize(ofFile: path) else { return nil }
            if info.st_nlink > 1 {
                tally.hardLinks[UInt64(info.st_ino)] = HardLinkTally(links: UInt32(info.st_nlink), seen: 1, size: size)
            } else {
                tally.exact = size
            }
        }
        return tally.total
    }

    /// Bytes counted so far, and hard-linked files waiting to see whether all their links are inside.
    private struct Tally {
        var exact: UInt64 = 0
        var hardLinks: [UInt64: HardLinkTally] = [:]

        /// Exact bytes plus those hard-linked files whose every link was seen.
        var total: UInt64 {
            hardLinks.values.reduce(exact) { $0 &+ ($1.seen >= $1.links ? $1.size : 0) }
        }
    }

    /// The links seen for one inode.
    private struct HardLinkTally {
        var links: UInt32
        var seen: UInt32 = 0
        var size: UInt64 = 0

        /// Records one more link.
        mutating func add(_ bytes: UInt64) { seen += 1; size = bytes }
    }

    /// Reads one directory with `getattrlistbulk` and recurses. Returns false when any part can't be read.
    private func walk(directory: String, into tally: inout Tally) -> Bool {
        let descriptor = open(directory, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        var request = Bulk.makeRequest(includePrivateSize: true)
        let capacity = 128 * 1024
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: 8)
        defer { buffer.deallocate() }
        var subdirectories: [String] = []
        while true {
            let count = getattrlistbulk(descriptor, &request, buffer, capacity, Bulk.optionExtendedCommon)
            if count < 0 { if errno == EINTR { continue }; return false }
            if count == 0 { break }
            var cursor = UnsafeRawPointer(buffer)
            for _ in 0..<count {
                let length = Int(cursor.load(as: UInt32.self))
                guard let entry = BulkEntryParser.parse(cursor, length: length), entry.error == 0 else { return false }
                cursor += length
                let name = String(decoding: entry.name, as: UTF8.self)
                if entry.isDirectory { subdirectories.append(directory + "/" + name) } else { record(entry, into: &tally) }
            }
        }
        for sub in subdirectories where !walk(directory: sub, into: &tally) { return false }
        return true
    }

    /// Adds one non-directory entry to the tally. Symlinks and placeholders own no local bytes.
    private func record(_ entry: ParsedEntry, into tally: inout Tally) {
        guard entry.objectType != Bulk.objectSymlink, entry.fsFlags & Bulk.sfDataless == 0 else { return }
        let size = entry.hasPrivateSize ? entry.privateSize : entry.allocated
        if entry.linkCount > 1 {
            tally.hardLinks[entry.fileID, default: HardLinkTally(links: entry.linkCount)].add(size)
        } else {
            tally.exact &+= size
        }
    }

    /// The private size of one regular file, or nil when the kernel won't say.
    private static func privateSize(ofFile path: String) -> UInt64? {
        var request = Bulk.makePrivateSizeRequest()
        var scratch = [UInt8](repeating: 0, count: 64)
        let status = scratch.withUnsafeMutableBytes {
            getattrlist(path, &request, $0.baseAddress, $0.count, UInt32(FSOPT_NOFOLLOW) | UInt32(Bulk.optionExtendedCommon))
        }
        guard status == 0, scratch.withUnsafeBytes({ $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self) }) >= 32 else { return nil }
        return UInt64(clamping: scratch.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 24, as: Int64.self) })
    }
}

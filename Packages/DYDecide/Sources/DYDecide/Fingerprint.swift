import Foundation
import DYCore

/// Identifies one version of a file or directory, so a verdict or a plan can tell that the path now holds something else.
///
/// For a directory `size` is always 0, because a directory's own size says nothing stable about its contents.
/// For everything else it is the total size of all forks, which is what the scanner records, so a file with a resource
/// fork still matches its scan.
public struct Fingerprint: Codable, Sendable, Equatable, Hashable {
    public var size: UInt64
    public var modified: Int32
    public var inode: UInt64

    /// Creates a fingerprint from its three parts.
    public init(size: UInt64, modified: Int32, inode: UInt64) {
        self.size = size
        self.modified = modified
        self.inode = inode
    }

    /// The fingerprint a scan recorded for `node`.
    public init(tree: FileTree, node: NodeID) {
        self.size = tree.isDirectory(node) ? 0 : tree.logical(node)
        self.modified = tree.modified(node)
        self.inode = tree.inode(node)
    }

    /// The fingerprint of whatever is at `path` right now. Uses `lstat`, so a symlink describes itself, never its target.
    public static func current(path: String) throws -> Fingerprint {
        var info = stat()
        guard lstat(path, &info) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let isDirectory = (info.st_mode & S_IFMT) == S_IFDIR
        return Fingerprint(size: isDirectory ? 0 : totalSize(path: path, fallback: UInt64(max(0, info.st_size))),
                           modified: Int32(clamping: Int64(info.st_mtimespec.tv_sec)),
                           inode: UInt64(info.st_ino))
    }
}

extension Fingerprint {
    /// The size of every fork of a file (`ATTR_FILE_TOTALSIZE`, as the scanner records), or `fallback` if the call fails.
    static func totalSize(path: String, fallback: UInt64) -> UInt64 {
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.fileattr = attrgroup_t(ATTR_FILE_TOTALSIZE)
        // Layout: a 4-byte length, then one off_t.
        var buffer = [UInt8](repeating: 0, count: 16)
        let status = buffer.withUnsafeMutableBytes { getattrlist(path, &request, $0.baseAddress, $0.count, UInt32(FSOPT_NOFOLLOW)) }
        guard status == 0 else { return fallback }
        let length = buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self) }
        guard length >= 12 else { return fallback }
        return UInt64(clamping: buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: Int64.self) })
    }
}

/// Existence checks that never follow symlinks.
enum PathProbe {
    /// Whether anything, including a dangling symlink, exists at `path`.
    static func exists(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }
}

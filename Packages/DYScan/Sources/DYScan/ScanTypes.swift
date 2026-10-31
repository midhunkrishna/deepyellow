import DYCore
import Foundation

/// What to scan and how often to report.
public struct ScanOptions: Sendable {
    /// Absolute path of the directory to scan. `/` scans the whole disk with the Data volume merged in.
    public var root: String
    /// Number of directory-reading threads.
    public var workers: Int
    /// Minimum seconds between progress and snapshot events.
    public var snapshotInterval: TimeInterval
    /// Upper bound on the nodes in a live snapshot.
    public var snapshotMaxNodes: Int
    /// Query every file's private size from the kernel instead of only files that may share blocks.
    ///
    /// Slower by roughly half, but also accounts for blocks held by snapshots, which otherwise count as freeable.
    public var exactReclaimable = false

    /// Creates options with one worker per processor core.
    public init(root: String) {
        self.root = root
        self.workers = ProcessInfo.processInfo.activeProcessorCount
        self.snapshotInterval = 0.25
        self.snapshotMaxNodes = 200_000
    }
}

/// A cheap running tally, emitted while a scan is in flight.
public struct ScanProgress: Sendable {
    public var files: Int
    public var directories: Int
    public var bytes: UInt64
    public var unreadable: Int
    public var elapsed: TimeInterval
    public var currentPath: String

    /// Creates a progress value.
    public init(files: Int, directories: Int, bytes: UInt64, unreadable: Int, elapsed: TimeInterval, currentPath: String) {
        self.files = files
        self.directories = directories
        self.bytes = bytes
        self.unreadable = unreadable
        self.elapsed = elapsed
        self.currentPath = currentPath
    }
}

/// Everything a scan reports to its consumer.
public enum ScanEvent: Sendable {
    case progress(ScanProgress)
    case snapshot(FileTree)
    case finished(FileTree)
}

import DYAdvisor
import DYCore
import DYDecide
import DYScan
import Foundation

/// A running scan: its events, and a way to stop it.
public struct ScanHandle: Sendable {
    public var events: AsyncStream<ScanEvent>
    public var cancel: @Sendable () -> Void

    /// Wraps an event stream and its cancel function.
    public init(events: AsyncStream<ScanEvent>, cancel: @escaping @Sendable () -> Void) {
        self.events = events
        self.cancel = cancel
    }
}

/// Explicit sample figures for the ledger in demo mode, where there is no real volume to ask.
public struct SampleLedger: Sendable {
    public var hardlinkBytesSaved: UInt64
    public var cloneBytesSaved: UInt64
    public var unreadableDirectories: Int
    public var volume: VolumeInfo

    /// Creates sample ledger figures.
    public init(hardlinkBytesSaved: UInt64, cloneBytesSaved: UInt64, unreadableDirectories: Int, volume: VolumeInfo) {
        self.hardlinkBytesSaved = hardlinkBytesSaved
        self.cloneBytesSaved = cloneBytesSaved
        self.unreadableDirectories = unreadableDirectories
        self.volume = volume
    }
}

/// Everything the workspace reaches outside itself for. Tests and demo mode swap each piece for a fake.
///
/// The workspace never constructs a Trash mover: the app's entry point passes the real one to `live(mover:)`.
public struct WorkspaceEnvironment: Sendable {
    public var homePath: String
    /// Where decisions, ignore rules, the undo journal and cached scans are stored.
    public var dataDirectory: URL
    public var mover: TrashMoving
    public var appCatalog: AppCatalog
    public var reader: FileReading
    public var probe: ReclaimProbing
    public var clock: @Sendable () -> Date
    /// Starts a scan of a root path.
    public var startScan: @Sendable (String) -> ScanHandle
    /// The mounted volume whose mount point is exactly this root, or nil when the root isn't a volume.
    public var volumeForRoot: @Sendable (String) -> VolumeInfo?
    public var volumes: @Sendable () -> [VolumeInfo]
    /// Builds the sample disk for demo mode. Nil outside demo mode.
    public var sampleDisk: (@Sendable () -> FileTree)?
    /// Sample ledger figures. When set, the ledger is flagged as sample data.
    public var sampleLedger: SampleLedger?
    /// Whether the Trash undo journal is written to the data directory.
    public var keepsTrashJournal = true
    /// Whether finished scans are cached in the data directory.
    public var savesScanCache = true
    /// Files at least this large that are still `other` get their header read during kind refinement.
    public var kindRefinementMinimumSize: UInt64 = 1_000_000
    /// Smallest file the duplicate search considers.
    public var duplicateMinimumSize: UInt64 = 1_000_000
    /// Where to read preview content for a file whose own path doesn't exist, as in the sample disk. Nil (the default) previews the file at its own path.
    public var previewLocation: (@Sendable (_ path: String, _ kind: FileKind) -> URL?)?

    /// Creates an environment from explicit pieces.
    public init(homePath: String, dataDirectory: URL, mover: TrashMoving, appCatalog: AppCatalog, reader: FileReading,
                probe: ReclaimProbing, clock: @escaping @Sendable () -> Date,
                startScan: @escaping @Sendable (String) -> ScanHandle,
                volumeForRoot: @escaping @Sendable (String) -> VolumeInfo? = { _ in nil },
                volumes: @escaping @Sendable () -> [VolumeInfo] = { [] }) {
        self.homePath = homePath
        self.dataDirectory = dataDirectory
        self.mover = mover
        self.appCatalog = appCatalog
        self.reader = reader
        self.probe = probe
        self.clock = clock
        self.startScan = startScan
        self.volumeForRoot = volumeForRoot
        self.volumes = volumes
    }

    /// The data directory: `DEEPYELLOW_HOME` when set and non-empty, else `~/Library/Application Support/DeepYellow`.
    public static func defaultDataDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: String = NSHomeDirectory()
    ) -> URL {
        if let override = environment["DEEPYELLOW_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return URL(fileURLWithPath: home, isDirectory: true).appendingPathComponent("Library/Application Support/DeepYellow", isDirectory: true)
    }

    /// The environment for a real session. `mover` is supplied by the app's entry point.
    public static func live(mover: TrashMoving, home: String = NSHomeDirectory(),
                            dataDirectory: URL = WorkspaceEnvironment.defaultDataDirectory()) -> WorkspaceEnvironment {
        WorkspaceEnvironment(
            homePath: home, dataDirectory: dataDirectory, mover: mover, appCatalog: SystemAppCatalog(),
            reader: LocalFileReader(), probe: LiveReclaimProbe(), clock: { Date() },
            startScan: { root in
                let scanner = DiskScanner(options: ScanOptions(root: root))
                return ScanHandle(events: scanner.start(), cancel: { scanner.cancel() })
            },
            volumeForRoot: { root in VolumeInfo.mounted().first { $0.path == root } },
            volumes: { VolumeInfo.mounted() })
    }
}

/// Adapts the scanner's directory-walking probe to the plan refiner's protocol.
struct LiveReclaimProbe: ReclaimProbing {
    private let probe = PrivateSizeProbe()

    /// The bytes deleting `path` would free, measured on disk, or nil.
    func privateBytes(path: String) -> UInt64? { probe.privateBytes(path: path) }
}

/// Reads bytes from local files, read-only.
public struct LocalFileReader: FileReading {
    /// Creates a reader.
    public init() {}

    /// Reads up to `length` bytes at `offset`. Returns fewer at the end of the file.
    public func read(path: String, offset: UInt64, length: Int) throws -> Data {
        guard let handle = FileHandle(forReadingAtPath: path) else { throw CocoaError(.fileReadNoSuchFile) }
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)
        return try handle.read(upToCount: length) ?? Data()
    }
}

/// A flag a background job checks to stop early. Safe to share across threads.
final class CancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    /// Asks the job to stop.
    func cancel() { lock.withLock { cancelled = true } }

    /// Whether the job should stop.
    var isCancelled: Bool { lock.withLock { cancelled } }
}

import Foundation

/// Index of a node in a `FileTree`. The root is always 0.
public typealias NodeID = Int32

/// Sentinel meaning "no node".
public let noNode: NodeID = -1

/// Per-node facts recorded by the scanner.
public struct NodeFlags: OptionSet, Sendable, Hashable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    public static let directory = NodeFlags(rawValue: 1 << 0)
    /// A macOS package or semantic bundle such as `.app`. Displayed as one thing.
    public static let package = NodeFlags(rawValue: 1 << 1)
    public static let symlink = NodeFlags(rawValue: 1 << 2)
    /// A later hard link to an already-counted inode. `allocated` is 0.
    public static let hardlinkDuplicate = NodeFlags(rawValue: 1 << 3)
    /// A later full clone of an already-counted clone family. `allocated` is 0.
    public static let cloneDuplicate = NodeFlags(rawValue: 1 << 4)
    /// May share blocks with a clone or snapshot, so `allocated` can overstate what deletion frees.
    public static let mayShareBlocks = NodeFlags(rawValue: 1 << 5)
    /// An iCloud placeholder whose content isn't local. Never read it, because that downloads it.
    public static let dataless = NodeFlags(rawValue: 1 << 6)
    public static let sparse = NodeFlags(rawValue: 1 << 7)
    /// A directory the scanner couldn't read. Its size is unknown, not zero.
    public static let unreadable = NodeFlags(rawValue: 1 << 8)
    /// A mount point or device boundary the scanner did not cross.
    public static let mountBoundary = NodeFlags(rawValue: 1 << 9)
    /// SIP-protected. Shown and sized, never actionable.
    public static let restricted = NodeFlags(rawValue: 1 << 10)
    /// `privateBytes` wasn't reported by this filesystem and is a copy of `allocated`.
    public static let privateUnknown = NodeFlags(rawValue: 1 << 11)
}

/// The eight file categories used for colour. Extensions are never coloured individually.
public enum FileKind: UInt8, CaseIterable, Sendable {
    case video, image, audio, document, code, application, archive, other

    public var title: String {
        switch self {
        case .video: "Video"
        case .image: "Images"
        case .audio: "Audio"
        case .document: "Documents"
        case .code: "Code & data"
        case .application: "Apps & libraries"
        case .archive: "Archives & disks"
        case .other: "Other"
        }
    }
}

/// A user's staged verdict on a node. Nothing touches the disk until a plan is applied.
public enum Decision: UInt8, CaseIterable, Sendable, Codable {
    case none = 0, keep, remove, later
}

/// How safe an item is to remove. Uncertain items are `review`, never rounded up to `safe`.
public enum SafetyTier: UInt8, CaseIterable, Sendable, Codable {
    /// No advice applies to this node.
    case unknown = 0
    /// Regenerates automatically with no user-visible loss.
    case safe
    /// Recoverable, at the cost of time, network or a re-login.
    case rebuild
    /// May hold personal or unique data, so the user must look.
    case review
    /// Must not be offered for removal.
    case never
}

/// What a size-driven view measures.
public enum Metric: UInt8, Sendable {
    /// Bytes allocated on disk, after hard-link and clone dedupe.
    case bytes
    /// Number of files, which exposes swarms of tiny files.
    case files
}

/// What a tile's fill colour encodes.
public enum ColorMode: UInt8, CaseIterable, Sendable {
    case kind, age, safety, decision
}

/// Per-node visual state handed to renderers. Every array is empty or has `tree.count` elements.
public struct NodeStyle: Sendable {
    public var colorMode: ColorMode
    /// Effective decision raw values, with inheritance already resolved.
    public var decisions: [UInt8]
    /// `SafetyTier` raw values.
    public var safety: [UInt8]
    /// `FileKind` raw value of the kind that dominates each directory.
    public var dominantKind: [UInt8]
    /// Reference time for `ColorMode.age`, in seconds since 1970.
    public var now: Int32

    /// Creates a style. Any array may be left empty to mean "no data".
    public init(colorMode: ColorMode = .kind, decisions: [UInt8] = [], safety: [UInt8] = [],
                dominantKind: [UInt8] = [], now: Int32 = Int32(Date().timeIntervalSince1970)) {
        self.colorMode = colorMode
        self.decisions = decisions
        self.safety = safety
        self.dominantKind = dominantKind
        self.now = now
    }
}

/// Totals describing how a scan went. Stored with the tree so the UI never hides a partial scan.
public struct ScanMeta: Sendable, Codable, Equatable {
    public var rootPath: String
    public var scannedAt: Date
    public var duration: TimeInterval
    public var unreadableDirectories: Int
    /// True when Full Disk Access was missing, so `unreadableDirectories` is likely undercounted.
    public var limitedByPermissions: Bool
    public var hardlinkBytesSaved: UInt64
    public var cloneBytesSaved: UInt64

    /// Creates scan metadata with zeroed counters.
    public init(rootPath: String, scannedAt: Date = Date(), duration: TimeInterval = 0,
                unreadableDirectories: Int = 0, limitedByPermissions: Bool = false,
                hardlinkBytesSaved: UInt64 = 0, cloneBytesSaved: UInt64 = 0) {
        self.rootPath = rootPath
        self.scannedAt = scannedAt
        self.duration = duration
        self.unreadableDirectories = unreadableDirectories
        self.limitedByPermissions = limitedByPermissions
        self.hardlinkBytesSaved = hardlinkBytesSaved
        self.cloneBytesSaved = cloneBytesSaved
    }
}

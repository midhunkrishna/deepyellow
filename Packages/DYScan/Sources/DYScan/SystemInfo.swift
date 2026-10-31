import AppKit
import Foundation

/// A mounted volume and its capacity.
public struct VolumeInfo: Sendable, Identifiable {
    public var id: String
    public var name: String
    public var path: String
    public var total: UInt64
    /// Free space excluding purgeable.
    public var available: UInt64
    /// Free space including purgeable, which is what an app can actually obtain for user-initiated work.
    public var availableForImportantUsage: UInt64
    public var isInternal: Bool

    /// Creates a volume description. `id` is the mount path.
    public init(name: String, path: String, total: UInt64, available: UInt64, availableForImportantUsage: UInt64, isInternal: Bool) {
        self.id = path
        self.name = name
        self.path = path
        self.total = total
        self.available = available
        self.availableForImportantUsage = availableForImportantUsage
        self.isInternal = isInternal
    }

    /// The visible mounted volumes. Hidden system plumbing volumes are left out.
    public static func mounted() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
                                      .volumeAvailableCapacityForImportantUsageKey, .volumeIsInternalKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)), let total = values.volumeTotalCapacity else { return nil }
            let available = UInt64(max(0, values.volumeAvailableCapacity ?? 0))
            let important = UInt64(max(0, values.volumeAvailableCapacityForImportantUsage ?? Int64(available)))
            return VolumeInfo(name: values.volumeName ?? url.lastPathComponent, path: url.path, total: UInt64(max(0, total)),
                              available: available, availableForImportantUsage: important,
                              isInternal: values.volumeIsInternal ?? false)
        }
    }
}

/// Whether the app can read directories that macOS protects behind Full Disk Access.
public enum FullDiskAccess: Sendable {
    case granted, denied, unknown

    private static let settingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"

    /// Opens a protected directory that does not prompt. EPERM means not granted or blocked; anything else is inconclusive.
    public static func probe() -> FullDiskAccess {
        let candidates = [NSHomeDirectory() + "/Library/Safari", "/Library/Application Support/com.apple.TCC"]
        for path in candidates {
            let descriptor = open(path, O_RDONLY | O_DIRECTORY)
            if descriptor >= 0 { close(descriptor); return .granted }
            if errno == EPERM { return .denied }
        }
        return .unknown
    }

    /// Opens the Full Disk Access pane of System Settings.
    public static func openSettings() {
        if let url = URL(string: settingsURL) { NSWorkspace.shared.open(url) }
    }
}

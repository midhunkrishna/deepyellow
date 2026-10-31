import Foundation

/// Reads file flags without opening the file, so it is safe on iCloud placeholders.
public enum DatalessGuard {
    private static let datalessFlag: UInt32 = 0x4000_0000 // SF_DATALESS

    /// True when the path is an iCloud placeholder. Uses `lstat`, which never triggers a download.
    public static func isDataless(_ url: URL) -> Bool {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return false }
        return info.st_flags & datalessFlag != 0
    }
}

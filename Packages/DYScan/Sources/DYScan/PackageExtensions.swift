import Foundation
import UniformTypeIdentifiers

/// Decides whether a directory name denotes a macOS package, caching the answer per extension.
///
/// Not thread-safe: the aggregator thread is its only user.
final class PackageExtensions {
    private var cache: [[UInt8]: Bool] = [:]

    private static let known = [
        "app", "bundle", "plugin", "kext", "appex", "prefpane", "qlgenerator", "mdimporter", "photoslibrary",
        "musiclibrary", "tvlibrary", "imovielibrary", "photolibrary", "aplibrary", "xcarchive", "xcodeproj",
        "xcworkspace", "playground", "dsym", "mlmodelc", "rtfd", "logicx", "band", "sparsebundle", "numbers",
        "pages", "key",
    ]

    /// Creates a lookup seeded with the common package extensions, so most answers never reach the type system.
    init() {
        for ext in Self.known { cache[Array(ext.utf8)] = true }
    }

    /// Whether a directory with this name is a package. Names without an extension of 1 to 32 bytes are not.
    func isPackage(name: UnsafeBufferPointer<UInt8>) -> Bool {
        guard let dot = name.lastIndex(of: UInt8(ascii: ".")), dot > 0, name.count - dot > 1, name.count - dot - 1 <= 32 else {
            return false
        }
        let key = name[(dot + 1)...].map(Self.lowercase)
        if let known = cache[key] { return known }
        let answer = Self.conformsToPackage(key: key)
        cache[key] = answer
        return answer
    }

    /// Asks the type system whether an extension conforms to `.package`.
    private static func conformsToPackage(key: [UInt8]) -> Bool {
        UTType(filenameExtension: String(decoding: key, as: UTF8.self))?.conforms(to: .package) ?? false
    }

    /// Lowercases an ASCII byte.
    private static func lowercase(_ byte: UInt8) -> UInt8 { (byte >= 65 && byte <= 90) ? byte + 32 : byte }
}

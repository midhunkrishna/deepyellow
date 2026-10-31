import Foundation
import UniformTypeIdentifiers

/// Asks the system's type database which category an extension belongs to, caching each answer.
///
/// The extension table in `FileKindClassifier` is consulted first on the hot path. This is the fallback for
/// extensions the table doesn't list, so a lookup that costs microseconds happens once per distinct extension.
public enum TypeResolver {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: FileKind?] = [:]

    /// The category for a file extension (without the dot, any case), or nil when the type database has no useful answer.
    public static func kind(forExtension ext: String) -> FileKind? {
        let key = ext.lowercased()
        guard !key.isEmpty, key.utf8.count <= 16 else { return nil }
        lock.lock()
        if let cached = cache[key] { lock.unlock(); return cached }
        lock.unlock()
        let answer = UTType(filenameExtension: key).flatMap(category(of:))
        lock.lock()
        cache[key] = .some(answer)
        lock.unlock()
        return answer
    }

    /// Maps a type to a category by what it conforms to. Types that are only generic data give nil.
    private static func category(of type: UTType) -> FileKind? {
        if type.isDynamic { return nil }
        let groups: [(FileKind, [UTType])] = [
            (.video, [.movie, .video]),
            (.audio, [.audio]),
            (.image, [.image]),
            (.archive, [.archive, .diskImage]),
            (.application, [.executable, .application, .bundle, .framework]),
            (.code, [.sourceCode, .script, .json, .xml, .yaml, .propertyList, .database]),
            (.document, [.pdf, .presentation, .spreadsheet, .rtf, .epub, .text, .emailMessage]),
        ]
        for (kind, types) in groups where types.contains(where: { type.conforms(to: $0) }) { return kind }
        return nil
    }
}

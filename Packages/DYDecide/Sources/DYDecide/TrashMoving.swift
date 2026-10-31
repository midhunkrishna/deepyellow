import Foundation

/// The only operations the executor may perform on the file system. None of them deletes anything.
public protocol TrashMoving: Sendable {
    /// Moves the item at `path` into the Trash and returns where it ended up. A symlink moves itself, not its target.
    func moveToTrash(path: String) throws -> String
    /// Puts a trashed item back at `to`. Must fail if anything already exists at `to`, and never overwrite.
    func moveBack(from: String, to: String) throws
    /// The fingerprint of whatever is at `path` right now, without following symlinks.
    func currentFingerprint(path: String) throws -> Fingerprint
    /// Whether anything, including a dangling symlink, exists at `path`. The executor asks the mover, never the disk directly.
    func exists(path: String) -> Bool
}

extension TrashMoving {
    /// Checks the real file system with `lstat`. Movers that don't use the disk override this.
    public func exists(path: String) -> Bool { PathProbe.exists(path) }
}

/// Why a Trash operation could not be carried out.
public enum TrashError: Error, Equatable, CustomStringConvertible {
    case noResultingLocation(String)
    case destinationExists(String)

    public var description: String {
        switch self {
        case .noResultingLocation(let path): "The system gave no Trash location for \(path)"
        case .destinationExists(let path): "Something already exists at \(path)"
        }
    }
}

/// Moves items to the user's real Trash with `FileManager.trashItem`, which also lets Finder offer "Put Back".
public struct SystemTrash: TrashMoving {
    /// Creates the system Trash mover.
    public init() {}

    /// Moves `path` to the Trash and returns the path it now has there.
    public func moveToTrash(path: String) throws -> String {
        var resulting: NSURL?
        try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &resulting)
        guard let trashed = (resulting as URL?)?.path else { throw TrashError.noResultingLocation(path) }
        return trashed
    }

    /// Moves a trashed item back, refusing when `to` is already taken.
    public func moveBack(from: String, to: String) throws {
        guard !PathProbe.exists(to) else { throw TrashError.destinationExists(to) }
        try FileManager.default.moveItem(at: URL(fileURLWithPath: from), to: URL(fileURLWithPath: to))
    }

    /// The fingerprint of `path` as it is now.
    public func currentFingerprint(path: String) throws -> Fingerprint {
        try Fingerprint.current(path: path)
    }
}

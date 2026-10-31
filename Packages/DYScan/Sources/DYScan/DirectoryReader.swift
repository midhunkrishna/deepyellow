import DYCore
import Darwin
import Foundation

/// Reads one directory at a time with `getattrlistbulk`. One instance per worker thread: it owns its read buffer.
final class DirectoryReader {
    private let buffer: UnsafeMutableRawPointer
    private let capacity: Int
    private var request = Bulk.makeRequest()
    private var exactRequest = Bulk.makeRequest(includePrivateSize: true)
    private var privateRequest = Bulk.makePrivateSizeRequest()
    private var openDescriptor: Int32 = -1
    private var privateScratch = [UInt8](repeating: 0, count: 64)

    private let workerIndex: Int
    private var nextSequence: UInt64 = 0

    /// Allocates an 8-byte-aligned read buffer. `workerIndex` keeps the tokens this reader hands out unique.
    init(workerIndex: Int, capacity: Int = 256 * 1024) {
        self.workerIndex = workerIndex
        self.capacity = capacity
        buffer = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: 8)
    }

    deinit { buffer.deallocate() }

    /// Lists a directory and measures every entry. Never throws: failures are recorded in the batch.
    func read(_ job: ScanJob) -> DirectoryBatch {
        var batch = DirectoryBatch(token: job.token, path: job.path, context: job.context)
        if job.expectedEntries == 0 { return batch }
        let descriptor = DirectoryOpener.open(path: job.path, followSymlink: job.followSymlink)
        guard descriptor >= 0 else {
            batch.openError = errno
            return batch
        }
        openDescriptor = descriptor
        defer { close(descriptor); openDescriptor = -1 }
        batch.listError = drain(descriptor, into: &batch, job: job)
        reserveTokens(for: &batch)
        return batch
    }

    /// Gives the batch's subdirectories consecutive tokens, so the jobs for them can be queued without the aggregator.
    private func reserveTokens(for batch: inout DirectoryBatch) {
        guard !batch.subdirectoryPaths.isEmpty else { return }
        batch.firstSubdirectoryToken = DirectoryToken(worker: workerIndex, sequence: nextSequence)
        nextSequence += UInt64(batch.subdirectoryPaths.count)
    }

    /// The jobs for a batch's subdirectories, in token order.
    static func childJobs(of batch: DirectoryBatch) -> [ScanJob] {
        var jobs = [ScanJob?](repeating: nil, count: batch.subdirectoryPaths.count)
        for entry in batch.entries where entry.subdirectoryIndex >= 0 {
            let index = Int(entry.subdirectoryIndex)
            jobs[index] = ScanJob(token: batch.firstSubdirectoryToken.advanced(by: index), path: batch.subdirectoryPaths[index],
                                  context: batch.context, followSymlink: false, expectedEntries: entry.entryCount)
        }
        return jobs.compactMap { $0 }
    }

    /// Calls `getattrlistbulk` until the directory is exhausted, returning the `errno` of a failed call or 0.
    private func drain(_ descriptor: Int32, into batch: inout DirectoryBatch, job: ScanJob) -> Int32 {
        var sawEntries = false
        var collected = 0
        while true {
            let count = job.context.exactPrivateSize
                ? getattrlistbulk(descriptor, &exactRequest, buffer, capacity, Bulk.optionExtendedCommon)
                : getattrlistbulk(descriptor, &request, buffer, capacity, Bulk.optionExtendedCommon)
            if count < 0 {
                let failure = errno
                if failure == EINTR { continue }
                // A buffer that was exactly full can make the next call fail with ERANGE instead of returning 0.
                if failure == ERANGE && sawEntries { return 0 }
                return failure
            }
            if count == 0 { return 0 }
            sawEntries = true
            consume(Int(count), into: &batch, job: job)
            collected += Int(count)
            // The parent told us how many entries to expect, so the call that would return 0 can be skipped.
            if job.expectedEntries > 0 && collected >= Int(job.expectedEntries) { return 0 }
        }
    }

    /// Walks `count` packed entries in the buffer, turning each into a `ScannedEntry`.
    private func consume(_ count: Int, into batch: inout DirectoryBatch, job: ScanJob) {
        var cursor = UnsafeRawPointer(buffer)
        for _ in 0..<count {
            let length = Int(cursor.load(as: UInt32.self))
            if let parsed = BulkEntryParser.parse(cursor, length: length) {
                append(parsed, to: &batch, job: job)
            }
            cursor += length
        }
    }

    /// Classifies a parsed entry and appends it, skipping entries the pass excludes.
    private func append(_ parsed: ParsedEntry, to batch: inout DirectoryBatch, job: ScanJob) {
        let name = parsed.name
        if name.isEmpty || (name.count <= 2 && name.allSatisfy { $0 == UInt8(ascii: ".") }) { return }
        if job.context.policy.skips(directory: job.path, name: name, fsFlags: parsed.fsFlags) { return }
        var entry = EntryClassifier.classify(parsed, rootDevice: job.context.rootDevice)
        if entry.flags.contains(.mayShareBlocks) && !parsed.hasPrivateSize { entry.privateBytes = privateSize(of: parsed, fallback: entry) }
        entry.nameOffset = Int32(batch.names.count)
        entry.nameLength = UInt16(clamping: name.count)
        batch.names.append(contentsOf: name)
        if EntryClassifier.shouldDescend(parsed, flags: entry.flags) {
            entry.subdirectoryIndex = Int32(batch.subdirectoryPaths.count)
            batch.subdirectoryPaths.append(Self.childPath(of: job.path, name: name))
        }
        batch.entries.append(entry)
    }

    /// Asks the kernel for one file's private size, which differs from its allocated size only when blocks are shared.
    ///
    /// Falls back to the allocated size when the call fails. Directories, symlinks and dataless files are not asked.
    private func privateSize(of parsed: ParsedEntry, fallback entry: ScannedEntry) -> UInt64 {
        guard openDescriptor >= 0, !parsed.isDirectory, parsed.objectType != Bulk.objectSymlink,
              !entry.flags.contains(.dataless), let name = parsed.name.baseAddress else { return entry.privateBytes }
        let status = privateScratch.withUnsafeMutableBytes { scratch in
            name.withMemoryRebound(to: CChar.self, capacity: parsed.name.count + 1) {
                getattrlistat(openDescriptor, $0, &privateRequest, scratch.baseAddress, scratch.count,
                              UInt(Bulk.optionExtendedCommon) | UInt(FSOPT_NOFOLLOW))
            }
        }
        // Layout: length, the 20-byte returned set, then the single off_t.
        guard status == 0, privateScratch.withUnsafeBytes({ $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self) }) >= 32 else {
            return entry.privateBytes
        }
        return UInt64(clamping: privateScratch.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 24, as: Int64.self) })
    }

    /// Joins a NUL-terminated directory path and an entry name into a NUL-terminated path.
    static func childPath(of parent: [UInt8], name: UnsafeBufferPointer<UInt8>) -> [UInt8] {
        var path: [UInt8] = []
        path.reserveCapacity(parent.count + name.count + 1)
        path.append(contentsOf: parent.dropLast())
        if path.last != UInt8(ascii: "/") { path.append(UInt8(ascii: "/")) }
        path.append(contentsOf: name)
        path.append(0)
        return path
    }
}

/// Turns parsed attributes into the facts the tree records.
enum EntryClassifier {
    /// Builds a `ScannedEntry` with everything except the name location and descent index.
    static func classify(_ parsed: ParsedEntry, rootDevice: UInt32?) -> ScannedEntry {
        var flags = nodeFlags(for: parsed)
        let isDirectory = parsed.isDirectory
        let isDataless = flags.contains(.dataless)
        var allocated = (isDirectory || isDataless) ? 0 : parsed.allocated
        var privateBytes = parsed.hasPrivateSize ? parsed.privateSize : allocated
        if isDirectory || isDataless { privateBytes = 0 }
        if !parsed.hasExtFlags && !isDirectory { flags.insert(.privateUnknown) }
        if parsed.error != 0 { flags.insert(.unreadable); allocated = 0; privateBytes = 0 }
        if isDirectory, isBoundary(parsed, rootDevice: rootDevice) { flags.insert(.mountBoundary) }
        let kind: FileKind = isDirectory ? .other : FileKindClassifier.classify(name: parsed.name, size: parsed.logical)
        return ScannedEntry(
            nameOffset: 0, nameLength: 0, flags: flags, kind: kind, dedupe: dedupeKind(parsed, isDirectory: isDirectory),
            subdirectoryIndex: -1, entryCount: parsed.hasEntryCount ? Int32(clamping: parsed.entryCount) : -1, allocated: allocated, logical: parsed.error != 0 ? 0 : (isDirectory ? 0 : parsed.logical),
            privateBytes: privateBytes, modified: parsed.modified, accessed: parsed.accessed, fileID: parsed.fileID,
            cloneID: parsed.cloneID, device: parsed.hasRealDevice ? parsed.realDevice : 0)
    }

    /// Whether the scanner should read inside this entry.
    static func shouldDescend(_ parsed: ParsedEntry, flags: NodeFlags) -> Bool {
        parsed.isDirectory && parsed.error == 0
            && !flags.contains(.mountBoundary) && !flags.contains(.dataless) && !flags.contains(.symlink)
    }

    /// Flags derived from the object type, BSD flags and extended flags.
    private static func nodeFlags(for parsed: ParsedEntry) -> NodeFlags {
        var flags: NodeFlags = []
        if parsed.isDirectory { flags.insert(.directory) }
        if parsed.objectType == Bulk.objectSymlink { flags.insert(.symlink) }
        if parsed.fsFlags & Bulk.sfDataless != 0 { flags.insert(.dataless) }
        if parsed.fsFlags & Bulk.sfRestricted != 0 { flags.insert(.restricted) }
        if parsed.hasExtFlags {
            if parsed.extFlags & Bulk.efMayShareBlocks != 0 { flags.insert(.mayShareBlocks) }
            if parsed.extFlags & Bulk.efIsSparse != 0 { flags.insert(.sparse) }
        }
        return flags
    }

    /// A directory is a boundary when it is a mount point or lives on a different physical volume than the root.
    private static func isBoundary(_ parsed: ParsedEntry, rootDevice: UInt32?) -> Bool {
        if parsed.mountStatus & Bulk.mountStatusIsMountPoint != 0 { return true }
        guard let rootDevice, parsed.hasRealDevice else { return false }
        return parsed.realDevice != rootDevice
    }

    /// Which global table, if any, decides whether this file's bytes were already counted.
    private static func dedupeKind(_ parsed: ParsedEntry, isDirectory: Bool) -> LinkDedupe {
        guard !isDirectory, parsed.error == 0 else { return .none }
        if parsed.linkCount > 1 && parsed.fileID != 0 { return .hardLink }
        if parsed.hasExtFlags && parsed.extFlags & Bulk.efSharesAllBlocks != 0 && parsed.hasCloneID && parsed.cloneID != 0 {
            return .clone
        }
        return .none
    }
}

/// Opens directories, working around `PATH_MAX` for deep trees.
enum DirectoryOpener {
    private static let pathLimit = 1000

    /// Opens a NUL-terminated directory path read-only. Returns -1 with `errno` set on failure.
    static func open(path: [UInt8], followSymlink: Bool) -> Int32 {
        let flags = O_RDONLY | O_DIRECTORY | O_CLOEXEC | (followSymlink ? 0 : O_NOFOLLOW)
        guard path.count <= pathLimit else { return openByComponents(path: path, flags: flags) }
        return path.withUnsafeBufferPointer { pointer in
            pointer.baseAddress!.withMemoryRebound(to: CChar.self, capacity: path.count) { Darwin.open($0, flags) }
        }
    }

    /// Opens a long absolute path by opening a short prefix normally, then one component at a time with `openat`,
    /// so no single call exceeds the path limit and only the final component is refused if it is a symlink.
    private static func openByComponents(path: [UInt8], flags: Int32) -> Int32 {
        let body = Array(path.dropLast())
        var cut = min(body.count - 1, pathLimit - 100)
        while cut > 0 && body[cut] != UInt8(ascii: "/") { cut -= 1 }
        var current = open(path: Array(body[0..<max(cut, 1)]) + [0], followSymlink: true)
        guard current >= 0 else { return -1 }
        let components = body[max(cut, 1)...].split(separator: UInt8(ascii: "/"), omittingEmptySubsequences: true)
        for component in components {
            var name = Array(component)
            name.append(0)
            let next = name.withUnsafeBufferPointer { pointer in
                pointer.baseAddress!.withMemoryRebound(to: CChar.self, capacity: name.count) { openat(current, $0, flags) }
            }
            let failure = errno
            close(current)
            guard next >= 0 else { errno = failure; return -1 }
            current = next
        }
        return current
    }
}

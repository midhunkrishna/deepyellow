import DYCore
import Foundation

/// Why a cached scan could not be read.
public enum ScanCacheError: Error, Equatable {
    case notACache
    case unsupportedVersion
    case truncated
    case corrupt
}

/// Saves and loads finished trees, so the app can show the previous scan immediately on launch.
///
/// Layout: an 8-byte magic, a `UInt64` metadata length, the metadata as JSON, two `UInt64` counts (nodes, name bytes),
/// then each `FileTreeColumns` array as raw native-endian bytes in declaration order.
public enum ScanCache {
    private static let magic: [UInt8] = Array("DYSCAN\u{0}\u{1}".utf8)

    /// Writes a tree atomically: a partial write never replaces an existing cache.
    public static func save(_ tree: FileTree, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            let handle = try FileHandle(forWritingTo: temporary)
            defer { try? handle.close() }
            try writeHeader(of: tree, to: handle)
            try writeColumns(tree.columns, to: handle)
            try handle.synchronize()
            guard rename(temporary.path, url.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    /// Reads a tree back, checking the file's size and structure before trusting it.
    public static func load(from url: URL) throws -> FileTree {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try data.withUnsafeBytes { raw in
            var reader = ByteReader(raw: raw)
            guard reader.take(magic.count) == magic[...] else { throw ScanCacheError.notACache }
            let metaLength = try reader.takeInteger()
            let meta = try decodeMeta(try reader.takeBytes(Int(clamping: metaLength)))
            let nodes = Int(clamping: try reader.takeInteger()), nameBytes = Int(clamping: try reader.takeInteger())
            let columns = try readColumns(&reader, nodes: nodes, nameBytes: nameBytes)
            guard reader.remaining == 0 else { throw ScanCacheError.corrupt }
            try validate(columns)
            return FileTree(columns: columns, meta: meta)
        }
    }

    /// The default cache location for a scan root: one file per root under Application Support.
    public static func defaultURL(forRoot root: String) -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let label = (root as NSString).lastPathComponent.filter { $0.isLetter || $0.isNumber }
        let name = (label.isEmpty ? "root" : label) + "-" + String(fnv1a(root), radix: 16) + ".dyscan"
        return support.appendingPathComponent("DeepYellow/scans/\(name)")
    }

    // MARK: Writing

    private static func writeHeader(of tree: FileTree, to handle: FileHandle) throws {
        let encoder = JSONEncoder()
        let meta = try encoder.encode(tree.meta)
        var header = Data(magic)
        header.append(integer: UInt64(meta.count))
        header.append(meta)
        header.append(integer: UInt64(tree.count))
        header.append(integer: UInt64(tree.columns.nameBytes.count))
        try handle.write(contentsOf: header)
    }

    private static func writeColumns(_ c: FileTreeColumns, to handle: FileHandle) throws {
        try write(c.parent, to: handle); try write(c.firstChild, to: handle); try write(c.childCount, to: handle)
        try write(c.allocated, to: handle); try write(c.logical, to: handle); try write(c.privateBytes, to: handle)
        try write(c.fileCount, to: handle); try write(c.modified, to: handle); try write(c.accessed, to: handle)
        try write(c.flags, to: handle); try write(c.kind, to: handle); try write(c.inode, to: handle)
        try write(c.nameOffset, to: handle); try write(c.nameLength, to: handle); try write(c.nameBytes, to: handle)
    }

    /// Writes an array's raw bytes without copying them into a `Data` first.
    private static func write<T>(_ values: [T], to handle: FileHandle) throws {
        try values.withUnsafeBytes { raw in
            guard raw.count > 0 else { return }
            try handle.write(contentsOf: Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: raw.baseAddress!), count: raw.count, deallocator: .none))
        }
    }

    // MARK: Reading

    private static func decodeMeta(_ bytes: Data) throws -> ScanMeta {
        do { return try JSONDecoder().decode(ScanMeta.self, from: bytes) } catch { throw ScanCacheError.corrupt }
    }

    private static func readColumns(_ r: inout ByteReader, nodes n: Int, nameBytes: Int) throws -> FileTreeColumns {
        var c = FileTreeColumns()
        c.parent = try r.takeArray(Int32.self, n); c.firstChild = try r.takeArray(Int32.self, n)
        c.childCount = try r.takeArray(Int32.self, n); c.allocated = try r.takeArray(UInt64.self, n)
        c.logical = try r.takeArray(UInt64.self, n); c.privateBytes = try r.takeArray(UInt64.self, n)
        c.fileCount = try r.takeArray(UInt32.self, n); c.modified = try r.takeArray(Int32.self, n)
        c.accessed = try r.takeArray(Int32.self, n); c.flags = try r.takeArray(UInt16.self, n)
        c.kind = try r.takeArray(UInt8.self, n); c.inode = try r.takeArray(UInt64.self, n)
        c.nameOffset = try r.takeArray(UInt32.self, n); c.nameLength = try r.takeArray(UInt16.self, n)
        c.nameBytes = try r.takeArray(UInt8.self, nameBytes)
        return c
    }

    /// Rejects structurally impossible columns, which would crash readers that trust the invariants.
    private static func validate(_ c: FileTreeColumns) throws {
        let n = c.parent.count
        guard n >= 1, c.parent[0] == noNode else { throw ScanCacheError.corrupt }
        for i in 0..<n {
            let first = Int(c.firstChild[i]), count = Int(c.childCount[i])
            if i > 0 && !(c.parent[i] >= 0 && Int(c.parent[i]) < i) { throw ScanCacheError.corrupt }
            if first >= 0 && (first <= i || count < 0 || first + count > n) { throw ScanCacheError.corrupt }
            if Int(c.nameOffset[i]) + Int(c.nameLength[i]) > c.nameBytes.count { throw ScanCacheError.corrupt }
            if c.kind[i] >= UInt8(FileKind.allCases.count) { throw ScanCacheError.corrupt }
        }
    }

    private static func fnv1a(_ string: String) -> UInt64 {
        string.utf8.reduce(0xcbf2_9ce4_8422_2325) { ($0 ^ UInt64($1)) &* 0x100_0000_01b3 }
    }
}

/// Sequential, bounds-checked reads over a mapped file.
private struct ByteReader {
    let raw: UnsafeRawBufferPointer
    var offset = 0
    var remaining: Int { raw.count - offset }

    init(raw: UnsafeRawBufferPointer) { self.raw = raw }

    /// Takes up to `count` bytes without failing; callers compare the result to what they expect.
    mutating func take(_ count: Int) -> ArraySlice<UInt8> {
        let end = min(raw.count, offset + count)
        defer { offset = end }
        return Array(raw[offset..<end])[...]
    }

    mutating func takeInteger() throws -> UInt64 {
        guard remaining >= 8 else { throw ScanCacheError.truncated }
        defer { offset += 8 }
        return raw.loadUnaligned(fromByteOffset: offset, as: UInt64.self)
    }

    mutating func takeBytes(_ count: Int) throws -> Data {
        guard count >= 0, remaining >= count else { throw ScanCacheError.truncated }
        defer { offset += count }
        return Data(raw[offset..<(offset + count)])
    }

    /// Copies `count` elements of a trivial type out of the file.
    mutating func takeArray<T>(_ type: T.Type, _ count: Int) throws -> [T] {
        let (bytes, overflow) = count.multipliedReportingOverflow(by: MemoryLayout<T>.stride)
        guard !overflow, count >= 0, remaining >= bytes else { throw ScanCacheError.truncated }
        let source = raw.baseAddress.map { $0 + offset }
        defer { offset += bytes }
        return [T](unsafeUninitializedCapacity: count) { buffer, initialized in
            if let source, bytes > 0 { memcpy(buffer.baseAddress!, source, bytes) }
            initialized = count
        }
    }
}

private extension Data {
    /// Appends a native-endian integer.
    mutating func append(integer: UInt64) {
        var value = integer
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }
}

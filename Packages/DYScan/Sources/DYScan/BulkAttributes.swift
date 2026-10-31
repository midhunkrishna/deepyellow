import Darwin

/// Attribute bits and option values for `getattrlistbulk`, written out so the scanner doesn't depend on
/// which of them the platform headers happen to import.
enum Bulk {
    // Common group.
    static let cmnName: UInt32 = 0x0000_0001
    static let cmnDeviceID: UInt32 = 0x0000_0002
    static let cmnObjectType: UInt32 = 0x0000_0008
    static let cmnModifiedTime: UInt32 = 0x0000_0400
    static let cmnAccessedTime: UInt32 = 0x0000_1000
    static let cmnFlags: UInt32 = 0x0004_0000
    static let cmnFileID: UInt32 = 0x0200_0000
    static let cmnError: UInt32 = 0x2000_0000
    static let cmnReturnedAttributes: UInt32 = 0x8000_0000

    // Directory group.
    static let dirEntryCount: UInt32 = 0x0000_0002
    static let dirMountStatus: UInt32 = 0x0000_0004
    static let mountStatusIsMountPoint: UInt32 = 0x1

    // File group.
    static let fileLinkCount: UInt32 = 0x0000_0001
    static let fileTotalSize: UInt32 = 0x0000_0002
    static let fileAllocSize: UInt32 = 0x0000_0004

    // Extended common group, selected by `optionExtendedCommon` and carried in `forkattr`.
    static let extPrivateSize: UInt32 = 0x0000_0008
    static let extRealDeviceID: UInt32 = 0x0000_0040
    static let extCloneID: UInt32 = 0x0000_0100
    static let extFlags: UInt32 = 0x0000_0200

    // Options.
    static let optionExtendedCommon: UInt64 = 0x0000_0020

    // Extended flag values, inferred by experiment because the SDK doesn't define them.
    static let efMayShareBlocks: UInt64 = 0x1
    static let efIsSparse: UInt64 = 0x10
    static let efSharesAllBlocks: UInt64 = 0x40

    // BSD file flags.
    static let sfRestricted: UInt32 = 0x0008_0000
    static let sfFirmlink: UInt32 = 0x0080_0000
    static let sfDataless: UInt32 = 0x4000_0000

    // Vnode types.
    static let objectDirectory: UInt32 = 2
    static let objectSymlink: UInt32 = 5

    /// The attribute list every directory read asks for.
    ///
    /// Private size is left out unless asked for: it roughly doubles the kernel's cost per entry, and for a file
    /// that shares no blocks it equals the allocated size anyway.
    static func makeRequest(includePrivateSize: Bool = false) -> attrlist {
        var request = attrlist()
        request.bitmapcount = 5
        request.commonattr = cmnReturnedAttributes | cmnError | cmnName | cmnObjectType | cmnModifiedTime
            | cmnAccessedTime | cmnFlags | cmnFileID
        request.dirattr = dirEntryCount | dirMountStatus
        request.fileattr = fileLinkCount | fileTotalSize | fileAllocSize
        request.forkattr = extRealDeviceID | extCloneID | extFlags | (includePrivateSize ? extPrivateSize : 0)
        return request
    }

    /// The attribute list for asking about one file's private size.
    static func makePrivateSizeRequest() -> attrlist {
        var request = attrlist()
        request.bitmapcount = 5
        request.commonattr = cmnReturnedAttributes
        request.forkattr = extPrivateSize
        return request
    }
}

/// The attributes of one directory entry, with a presence flag for each optional one.
///
/// `name` points into the read buffer and is valid only until the next `getattrlistbulk` call.
struct ParsedEntry {
    var name: UnsafeBufferPointer<UInt8>
    var error: UInt32 = 0
    var objectType: UInt32 = 0
    var fsFlags: UInt32 = 0
    var modified: Int32 = 0
    var accessed: Int32 = 0
    var fileID: UInt64 = 0
    var mountStatus: UInt32 = 0
    var entryCount: UInt32 = 0
    var hasEntryCount = false
    var linkCount: UInt32 = 0
    var logical: UInt64 = 0
    var allocated: UInt64 = 0
    var privateSize: UInt64 = 0
    var realDevice: UInt32 = 0
    var cloneID: UInt64 = 0
    var extFlags: UInt64 = 0
    var hasSizes = false
    var hasPrivateSize = false
    var hasRealDevice = false
    var hasCloneID = false
    var hasExtFlags = false

    /// Whether the entry is a directory (including packages and mount points).
    var isDirectory: Bool { objectType == Bulk.objectDirectory }
}

/// Reads fields out of one entry's bytes in order, using unaligned loads because the kernel packs fields on 4-byte boundaries.
private struct FieldCursor {
    let base: UnsafeRawPointer
    let length: Int
    var offset: Int
    var overran = false

    /// Reads a `T` at the cursor and advances. Sets `overran` instead of reading past the entry.
    mutating func take<T>(_: T.Type) -> T? {
        guard offset + MemoryLayout<T>.size <= length else { overran = true; return nil }
        let value = base.loadUnaligned(fromByteOffset: offset, as: T.self)
        offset += MemoryLayout<T>.size
        return value
    }
}

/// Turns one `getattrlistbulk` entry into a `ParsedEntry`, driven only by the attribute set the entry itself reports.
enum BulkEntryParser {
    private static let knownCommon = Bulk.cmnName | Bulk.cmnDeviceID | Bulk.cmnObjectType | Bulk.cmnModifiedTime
        | Bulk.cmnAccessedTime | Bulk.cmnFlags | Bulk.cmnFileID | Bulk.cmnError | Bulk.cmnReturnedAttributes
    private static let knownDir = Bulk.dirEntryCount | Bulk.dirMountStatus
    private static let knownFile = Bulk.fileLinkCount | Bulk.fileTotalSize | Bulk.fileAllocSize
    private static let knownExtended = Bulk.extPrivateSize | Bulk.extRealDeviceID | Bulk.extCloneID | Bulk.extFlags

    /// Parses the entry at `entry`, whose first four bytes hold its total length. Returns nil when it is malformed.
    static func parse(_ entry: UnsafeRawPointer, length: Int) -> ParsedEntry? {
        var cursor = FieldCursor(base: entry, length: length, offset: 4)
        guard let common = cursor.take(UInt32.self), let volume = cursor.take(UInt32.self),
              let directory = cursor.take(UInt32.self), let file = cursor.take(UInt32.self),
              let extended = cursor.take(UInt32.self) else { return nil }
        guard volume == 0, common & ~knownCommon == 0, directory & ~knownDir == 0,
              file & ~knownFile == 0, extended & ~knownExtended == 0, common & Bulk.cmnName != 0 else { return nil }

        var parsed = ParsedEntry(name: UnsafeBufferPointer(start: nil, count: 0))
        if common & Bulk.cmnError != 0 { parsed.error = cursor.take(UInt32.self) ?? 0 }
        guard readCommon(common, into: &parsed, cursor: &cursor) else { return nil }
        readDirectory(directory, into: &parsed, cursor: &cursor)
        readFile(file, into: &parsed, cursor: &cursor)
        readExtended(extended, into: &parsed, cursor: &cursor)
        return cursor.overran ? nil : parsed
    }

    /// Reads the common-group fields in ascending bit order, resolving the name reference against the entry.
    private static func readCommon(_ set: UInt32, into parsed: inout ParsedEntry, cursor: inout FieldCursor) -> Bool {
        let referenceOffset = cursor.offset
        guard let dataOffset = cursor.take(Int32.self), let nameLength = cursor.take(UInt32.self) else { return false }
        let start = referenceOffset + Int(dataOffset)
        guard start >= 0, nameLength > 0, start + Int(nameLength) <= cursor.length else { return false }
        let bytes = cursor.base.advanced(by: start).assumingMemoryBound(to: UInt8.self)
        var count = Int(nameLength)
        if bytes[count - 1] == 0 { count -= 1 }
        parsed.name = UnsafeBufferPointer(start: bytes, count: count)
        if set & Bulk.cmnDeviceID != 0 { _ = cursor.take(UInt32.self) }
        if set & Bulk.cmnObjectType != 0 { parsed.objectType = cursor.take(UInt32.self) ?? 0 }
        if set & Bulk.cmnModifiedTime != 0 { parsed.modified = readSeconds(&cursor) }
        if set & Bulk.cmnAccessedTime != 0 { parsed.accessed = readSeconds(&cursor) }
        if set & Bulk.cmnFlags != 0 { parsed.fsFlags = cursor.take(UInt32.self) ?? 0 }
        if set & Bulk.cmnFileID != 0 { parsed.fileID = cursor.take(UInt64.self) ?? 0 }
        return true
    }

    /// Reads a `timespec` and returns its seconds clamped into `Int32`.
    private static func readSeconds(_ cursor: inout FieldCursor) -> Int32 {
        let seconds = cursor.take(Int64.self) ?? 0
        _ = cursor.take(Int64.self)
        return Int32(clamping: seconds)
    }

    /// Reads the directory-group fields.
    private static func readDirectory(_ set: UInt32, into parsed: inout ParsedEntry, cursor: inout FieldCursor) {
        if set & Bulk.dirEntryCount != 0 { parsed.entryCount = cursor.take(UInt32.self) ?? 0; parsed.hasEntryCount = true }
        if set & Bulk.dirMountStatus != 0 { parsed.mountStatus = cursor.take(UInt32.self) ?? 0 }
    }

    /// Reads the file-group fields.
    private static func readFile(_ set: UInt32, into parsed: inout ParsedEntry, cursor: inout FieldCursor) {
        if set & Bulk.fileLinkCount != 0 { parsed.linkCount = cursor.take(UInt32.self) ?? 0 }
        if set & Bulk.fileTotalSize != 0 { parsed.logical = UInt64(clamping: cursor.take(Int64.self) ?? 0); parsed.hasSizes = true }
        if set & Bulk.fileAllocSize != 0 { parsed.allocated = UInt64(clamping: cursor.take(Int64.self) ?? 0) }
    }

    /// Reads the extended common fields that arrive in the fork group.
    private static func readExtended(_ set: UInt32, into parsed: inout ParsedEntry, cursor: inout FieldCursor) {
        if set & Bulk.extPrivateSize != 0 {
            parsed.privateSize = UInt64(clamping: cursor.take(Int64.self) ?? 0)
            parsed.hasPrivateSize = true
        }
        if set & Bulk.extRealDeviceID != 0 { parsed.realDevice = cursor.take(UInt32.self) ?? 0; parsed.hasRealDevice = true }
        if set & Bulk.extCloneID != 0 { parsed.cloneID = cursor.take(UInt64.self) ?? 0; parsed.hasCloneID = true }
        if set & Bulk.extFlags != 0 { parsed.extFlags = cursor.take(UInt64.self) ?? 0; parsed.hasExtFlags = true }
    }
}

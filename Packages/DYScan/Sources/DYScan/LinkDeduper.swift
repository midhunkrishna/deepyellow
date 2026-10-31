import Foundation

/// Identifies a file on a physical volume.
struct LinkKey: Hashable {
    var device: UInt32
    var id: UInt64
}

/// What deduplication decided about one file.
enum LinkVerdict {
    case first
    case duplicate
}

/// Remembers hard-linked inodes and fully-cloned families so each is counted once.
///
/// Not thread-safe: the aggregator thread is its only user.
struct LinkDeduper {
    private var hardLinks = Set<LinkKey>()
    private var clones = Set<LinkKey>()

    /// Records a multi-link file by (physical device, file id) and says whether it was seen before.
    mutating func visitHardLink(device: UInt32, fileID: UInt64) -> LinkVerdict {
        hardLinks.insert(LinkKey(device: device, id: fileID)).inserted ? .first : .duplicate
    }

    /// Records a fully-shared clone by (physical device, clone id) and says whether its family was seen before.
    mutating func visitClone(device: UInt32, cloneID: UInt64) -> LinkVerdict {
        clones.insert(LinkKey(device: device, id: cloneID)).inserted ? .first : .duplicate
    }
}

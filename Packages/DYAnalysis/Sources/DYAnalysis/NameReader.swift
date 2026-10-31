import DYCore

/// Direct, allocation-free access to node names for tight loops, valid only inside `NameReader.with`.
struct NameReader {
    let bytes: UnsafeBufferPointer<UInt8>
    let offsets: UnsafeBufferPointer<UInt32>
    let lengths: UnsafeBufferPointer<UInt16>

    /// Pins the name columns of `tree` for the duration of `body`.
    static func with<R>(_ tree: FileTree, _ body: (NameReader) -> R) -> R {
        tree.columns.nameBytes.withUnsafeBufferPointer { bytes in
            tree.columns.nameOffset.withUnsafeBufferPointer { offsets in
                tree.columns.nameLength.withUnsafeBufferPointer { lengths in
                    body(NameReader(bytes: bytes, offsets: offsets, lengths: lengths))
                }
            }
        }
    }

    /// The raw UTF-8 name of a node.
    @inline(__always) func name(_ index: Int) -> UnsafeBufferPointer<UInt8> {
        let start = Int(offsets[index])
        return UnsafeBufferPointer(rebasing: bytes[start..<(start + Int(lengths[index]))])
    }
}

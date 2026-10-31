import DYCore
import Foundation

/// A child shown in a directory preview.
public struct PreviewChild: Sendable, Equatable {
    public var url: URL
    public var name: String
    public var size: UInt64
    public var kind: FileKind
    public var isDirectory: Bool

    /// Creates a child entry.
    public init(url: URL, name: String, size: UInt64, kind: FileKind, isDirectory: Bool) {
        self.url = url
        self.name = name
        self.size = size
        self.kind = kind
        self.isDirectory = isDirectory
    }
}

/// Everything the preview needs to know about one item, so it never has to touch a tree.
public struct PreviewItem: Sendable, Equatable {
    public var url: URL
    public var name: String
    public var size: UInt64
    public var modified: Date?
    public var kind: FileKind
    public var isDirectory: Bool
    /// An iCloud placeholder. Its file is never opened, read, thumbnailed or handed to QuickLook.
    public var isDataless: Bool
    public var largestChildren: [PreviewChild]

    /// Creates an item.
    public init(url: URL, name: String, size: UInt64, modified: Date? = nil, kind: FileKind,
                isDirectory: Bool = false, isDataless: Bool = false, largestChildren: [PreviewChild] = []) {
        self.url = url
        self.name = name
        self.size = size
        self.modified = modified
        self.kind = kind
        self.isDirectory = isDirectory
        self.isDataless = isDataless
        self.largestChildren = largestChildren
    }
}

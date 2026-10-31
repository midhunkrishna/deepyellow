import Foundation
import DYCore

/// The rules that make a node untouchable, evaluated per node so the planner can apply them to any input.
struct PlannerGuards {
    private let tree: FileTree
    private let tier: [UInt8]
    private let stale: Set<NodeID>
    /// Nodes protected by where they are: the root, home, its ancestors, system folders and standard user folders.
    private let placeReasons: [NodeID: String]

    private static let systemFolders = ["System", "Applications", "Library", "Users", "usr", "bin", "sbin", "private", "Volumes"]
    private static let userFolders = ["Library", "Documents", "Desktop", "Pictures", "Movies", "Music", "Downloads"]

    /// Builds the guards for `tree`. `home` is the user's home directory path.
    init(tree: FileTree, tier: [UInt8], stalePaths: [String], home: String) {
        self.tree = tree
        self.tier = tier
        self.stale = Set(stalePaths.flatMap { Self.lookup(tree, Self.components($0)) })
        var reasons: [NodeID: String] = [0: "This is the scan root, which can never be removed"]
        Self.addPlaceGuards(tree: tree, home: home, into: &reasons)
        self.placeReasons = reasons
    }

    /// Why `node` itself must not be moved, or nil. Says nothing about being inside a Photos library.
    func hazard(_ node: NodeID) -> String? {
        if let reason = placeReasons[node] { return reason }
        let flags = tree.flags(node)
        if flags.contains(.restricted) { return "Protected by macOS" }
        if flags.contains(.mountBoundary) { return "A mount point or volume boundary" }
        if flags.contains(.unreadable) { return "Couldn't be read, so its contents are unknown" }
        if node < tier.count, tier[Int(node)] == SafetyTier.never.rawValue { return "Advice says this must never be removed" }
        if Self.isPhotosLibrary(tree, node) { return "A Photos library; manage it in Photos" }
        if stale.contains(node) { return "Changed since you marked it" }
        return nil
    }

    /// Whether `node` is itself a `.photoslibrary` bundle.
    static func isPhotosLibrary(_ tree: FileTree, _ node: NodeID) -> Bool {
        let suffix = Array(".photoslibrary".utf8)
        return tree.withName(node) { name in
            guard name.count >= suffix.count else { return false }
            let tail = name.suffix(suffix.count)
            return zip(tail, suffix).allSatisfy { ($0 | 0x20) == $1 || $0 == $1 }
        }
    }

    /// Why `path` can't be a plan item regardless of the tree: not absolute, or containing `.` or `..`.
    static func pathProblem(_ path: String) -> String? {
        guard path.hasPrefix("/"), path != "/" else { return "Not a usable absolute path" }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
        if parts.contains(where: { $0 == ".." || $0 == "." }) { return "Path contains a relative component" }
        return nil
    }

    /// Splits a path into lowercase components, dropping a trailing slash.
    static func components(_ path: String) -> [String] {
        path.split(separator: "/").map { $0.lowercased() }
    }

    /// Every node whose path, compared without regard to case, equals `target`. More than one only on case-sensitive volumes.
    static func lookup(_ tree: FileTree, _ target: [String]) -> [NodeID] {
        let root = components(tree.name(0))
        guard target.count >= root.count, Array(target.prefix(root.count)) == root else { return [] }
        var frontier: [NodeID] = [0]
        for part in target.dropFirst(root.count) {
            frontier = frontier.flatMap { node in tree.children(node).filter { tree.name($0).lowercased() == part } }
            if frontier.isEmpty { break }
        }
        return frontier
    }

    /// Adds `/`, system folders, home, its ancestors and the standard user folders.
    private static func addPlaceGuards(tree: FileTree, home: String, into reasons: inout [NodeID: String]) {
        func guardPath(_ parts: [String], _ reason: String) {
            for node in lookup(tree, parts) where reasons[node] == nil { reasons[node] = reason }
        }
        guardPath([], "The top of the disk")
        for folder in systemFolders { guardPath([folder.lowercased()], "A top-level system folder") }
        if components(tree.name(0)).isEmpty {
            for child in tree.children(0) where reasons[child] == nil { reasons[child] = "A top-level folder of the disk" }
        }
        let homeParts = components(home)
        guard !homeParts.isEmpty else { return }
        for length in 1..<homeParts.count { guardPath(Array(homeParts.prefix(length)), "Contains your home folder") }
        guardPath(homeParts, "Your home folder")
        for folder in userFolders { guardPath(homeParts + [folder.lowercased()], "A standard folder in your home") }
    }
}

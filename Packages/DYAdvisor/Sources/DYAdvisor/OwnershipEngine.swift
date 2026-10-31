import DYCore
import Foundation

/// Whether the app behind a folder is on this Mac.
public enum Ownership: Sendable, Equatable {
    /// The app is installed.
    case installed(AppIdentity)
    /// The folder is named by a bundle identifier and no installed app matches it or comes from the same vendor.
    case notInstalled(bundleID: String)
    /// The folder is named like an app, or like a vendor's helper, but nothing proves the app is gone. A guess.
    case possiblyNotInstalled(name: String)
}

/// One folder in the user's Library and the app it belongs to.
public struct OwnedFolder: Sendable {
    public let node: NodeID
    public let ownership: Ownership
    public let bytes: UInt64
    /// Most recent modification time beneath the folder, in seconds since 1970.
    public let newestModified: Int32

    /// Creates an owned folder.
    public init(node: NodeID, ownership: Ownership, bytes: UInt64, newestModified: Int32) {
        self.node = node
        self.ownership = ownership
        self.bytes = bytes
        self.newestModified = newestModified
    }
}

/// Every folder the engine could attribute to an app.
public struct OwnershipReport: Sendable {
    public let folders: [OwnedFolder]
    private let index: [NodeID: Int]

    /// Creates a report from owned folders.
    public init(folders: [OwnedFolder]) {
        self.folders = folders
        index = Dictionary(uniqueKeysWithValues: folders.enumerated().map { ($1.node, $0) })
    }

    /// The owned folder that is `id` or contains it, or nil when the node isn't inside one.
    public func owner(of id: NodeID, tree: FileTree) -> OwnedFolder? {
        var current = id
        while current >= 0 {
            if let position = index[current] { return folders[position] }
            current = tree.parent(current)
        }
        return nil
    }
}

/// Attributes folders in `~/Library` to apps. Facts only: it never raises a safety tier, and when it can't tell whether an
/// app is gone it says so with `possiblyNotInstalled` or says nothing.
public enum OwnershipEngine {
    /// The Library folders whose direct children are named for the app that owns them.
    static let libraryFolders = ["Containers", "Group Containers", "Caches", "Application Support", "Preferences",
                                 "Saved Application State", "HTTPStorages", "WebKit", "Logs"]

    /// Plain names in Application Support that belong to the system or to Apple, not to a removable app.
    private static let systemNames: Set<String> = [
        "addressbook", "clouddocs", "callhistorydb", "callhistorytransactions", "crashreporter", "diagnosticreports", "knowledge",
        "mobilesync", "syncservices", "icloud", "dock", "fileprovider", "coresspotlight", "controlcenter", "animoji", "apple",
        "com.apple", "networkserviceproxy", "differentialprivacy", "identityservicesd", "facetime", "quicklook", "sharedfilelist",
    ]

    /// Attributes the direct children of the Library folders under `home`. Returns nil if `isCancelled` becomes true.
    public static func analyze(lens: TreeLens, home: String, catalog: AppCatalog, isCancelled: () -> Bool) -> OwnershipReport? {
        let tree = lens.tree
        let library = (home.hasSuffix("/") ? String(home.dropLast()) : home) + "/Library"
        var candidates: [(node: NodeID, ownership: Ownership)] = []
        for folder in libraryFolders {
            if isCancelled() { return nil }
            guard let parent = tree.find(path: library + "/" + folder), tree.isDirectory(parent) else { continue }
            let plainNamesCount = folder == "Application Support"
            for child in tree.children(parent) where lens.included[Int(child)] && lens.size[Int(child)] > 0 {
                if tree.flags(child).contains(.restricted) { continue }
                let name = tree.name(child)
                if let verdict = judge(name: name, allowsPlainNames: plainNamesCount, catalog: catalog) {
                    candidates.append((child, verdict))
                }
            }
        }
        guard !candidates.isEmpty else { return OwnershipReport(folders: []) }
        let newest = newestModified(lens: lens)
        let folders = candidates.map {
            OwnedFolder(node: $0.node, ownership: $0.ownership, bytes: lens.size[Int($0.node)], newestModified: newest[Int($0.node)])
        }
        return OwnershipReport(folders: folders.sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.node < $1.node })
    }

    /// The verdict for one folder name, or nil when the engine has nothing reliable to say.
    static func judge(name rawName: String, allowsPlainNames: Bool, catalog: AppCatalog) -> Ownership? {
        let name = stripSuffix(rawName)
        let lower = name.lowercased()
        guard !name.hasPrefix("."), !lower.contains("com.apple."), !lower.hasPrefix("apple") else { return nil }
        let parsed = parseGroup(name)
        if BundleIDShape.matches(parsed.id) { return judge(bundleID: parsed.id, team: parsed.team, catalog: catalog) }
        guard allowsPlainNames, parsed.team == nil, !systemNames.contains(lower) else { return nil }
        if let app = catalog.app(named: name) { return .installed(app) }
        return .possiblyNotInstalled(name: name)
    }

    /// Judges a bundle-identifier-shaped name against the installed apps. A name from the same vendor as an installed app
    /// gets no verdict, because vendors keep per-profile and per-update folders of their own.
    private static func judge(bundleID: String, team: String?, catalog: AppCatalog) -> Ownership? {
        if let app = installedApp(bundleID: bundleID, catalog: catalog) { return .installed(app) }
        if let team, let app = catalog.app(teamID: team) { return .installed(app) }
        if catalog.relatedApp(toBundleID: bundleID) != nil { return nil }
        return .notInstalled(bundleID: bundleID)
    }

    /// An installed app matching the identifier or any shorter dotted prefix of three or more components, such as a helper's.
    private static func installedApp(bundleID: String, catalog: AppCatalog) -> AppIdentity? {
        var parts = bundleID.split(separator: ".").map(String.init)
        while parts.count >= 3 {
            if let app = catalog.app(bundleID: parts.joined(separator: ".")) { return app }
            parts.removeLast()
        }
        return nil
    }

    /// Removes the suffixes macOS adds to per-app preference, state and cookie entries.
    private static func stripSuffix(_ name: String) -> String {
        for suffix in [".plist", ".savedState", ".binarycookies", ".lockfile"] where name.hasSuffix(suffix) && name.count > suffix.count {
            return String(name.dropLast(suffix.count))
        }
        return name
    }

    /// Splits a group container name into its team identifier (ten capitals or digits) and its identifier.
    private static func parseGroup(_ name: String) -> (team: String?, id: String) {
        var rest = Substring(name)
        var team: String?
        if let dot = rest.firstIndex(of: "."), rest.distance(from: rest.startIndex, to: dot) == 10,
           rest[rest.startIndex..<dot].allSatisfy({ ($0.isUppercase && $0.isASCII) || $0.isNumber }) {
            team = String(rest[rest.startIndex..<dot])
            rest = rest[rest.index(after: dot)...]
        }
        if rest.hasPrefix("group.") { rest = rest.dropFirst(6) }
        return (team, String(rest))
    }

    /// The newest modification time in every node's subtree, in one reverse pass.
    private static func newestModified(lens: TreeLens) -> [Int32] {
        let tree = lens.tree
        var newest = tree.columns.modified
        for index in stride(from: tree.count - 1, to: 0, by: -1) where lens.included[index] {
            let parent = Int(tree.columns.parent[index])
            newest[parent] = max(newest[parent], newest[index])
        }
        return newest
    }
}

/// Recognises names written like reverse-DNS bundle identifiers.
enum BundleIDShape {
    private static let topLevel: Set<String> = [
        "com", "org", "net", "io", "app", "dev", "ai", "co", "me", "edu", "gov", "de", "fr", "uk", "jp", "cn", "ru", "nl", "se",
        "ch", "us", "ca", "au", "in", "eu", "info", "biz", "xyz", "tv", "fm", "sh", "it", "es", "br", "kr", "pl", "no", "dk", "fi",
    ]

    /// Whether `name` has at least three dot-separated components, a known top-level prefix and only identifier characters.
    static func matches(_ name: String) -> Bool {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3, topLevel.contains(parts[0].lowercased()) else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "-" || $0 == "_" }
        }
    }
}

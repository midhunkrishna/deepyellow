import CoreServices
import Foundation
import Security

/// An application, as far as the system can say.
public struct AppIdentity: Sendable, Equatable {
    public var bundleID: String?
    public var name: String

    /// Creates an identity.
    public init(bundleID: String?, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

/// Answers whether an application is installed. A seam so tests never depend on the machine they run on.
public protocol AppCatalog: Sendable {
    /// The installed app with this bundle identifier (any case), or nil.
    func app(bundleID: String) -> AppIdentity?
    /// The installed app this folder name plausibly belongs to, or nil.
    func app(named: String) -> AppIdentity?
    /// The installed app signed by this developer team, or nil.
    func app(teamID: String) -> AppIdentity?
    /// An installed app whose identifier contains `bundleID` as a dotted prefix, is a prefix of it, or comes from the same
    /// vendor (the first two components). Used to avoid calling a vendor's helper folders orphaned.
    func relatedApp(toBundleID bundleID: String) -> AppIdentity?
}

extension AppCatalog {
    /// Catalogs that don't know team identifiers say nothing.
    public func app(teamID: String) -> AppIdentity? { nil }
    /// Catalogs that can't relate identifiers say nothing.
    public func relatedApp(toBundleID bundleID: String) -> AppIdentity? { nil }
}

/// The apps installed on this Mac: bundles found in the usual application folders, plus anything Launch Services knows.
public final class SystemAppCatalog: AppCatalog, @unchecked Sendable {
    /// Folders searched, to a depth of three, when no others are given.
    public static var defaultSearchDirectories: [String] {
        ["/Applications", "/System/Applications", "/System/Cryptexes/App/System/Applications",
         "/Library/Application Support/Apple", NSHomeDirectory() + "/Applications"]
    }

    private struct Entry {
        var identity: AppIdentity
        var path: String
        var names: [String]
    }

    private let entries: [Entry]
    private let byBundleID: [String: Int]
    private let usesLaunchServices: Bool
    private let lock = NSLock()
    private var teams: [String: AppIdentity]?

    /// Scans `searchDirectories` for app bundles. Set `usesLaunchServices` to false to answer from those folders alone.
    public init(searchDirectories: [String] = SystemAppCatalog.defaultSearchDirectories, usesLaunchServices: Bool = true) {
        var found: [Entry] = []
        for directory in searchDirectories { Self.collect(in: directory, depth: 3, into: &found) }
        entries = found
        var index: [String: Int] = [:]
        for (position, entry) in found.enumerated() {
            if let id = entry.identity.bundleID, index[id.lowercased()] == nil { index[id.lowercased()] = position }
        }
        byBundleID = index
        self.usesLaunchServices = usesLaunchServices
    }

    /// Looks the identifier up in the scanned folders, then in Launch Services.
    public func app(bundleID: String) -> AppIdentity? {
        if let position = byBundleID[bundleID.lowercased()] { return entries[position].identity }
        guard usesLaunchServices else { return nil }
        return launchServicesApp(bundleID: bundleID)
    }

    /// Matches a folder name against app names and identifiers, preferring exact matches.
    public func app(named name: String) -> AppIdentity? {
        let wanted = name.lowercased().trimmingCharacters(in: .whitespaces)
        guard wanted.count >= 4 else { return nil }
        if let exact = entries.first(where: { $0.names.contains(wanted) }) { return exact.identity }
        let squashed = wanted.replacingOccurrences(of: " ", with: "")
        let words = Set(wanted.split(separator: " ").map(String.init))
        return entries.first { entry in
            entry.names.contains { $0.count >= 4 && (words.contains($0) || $0.split(separator: " ").contains { $0 == Substring(wanted) }) }
                || entry.identity.bundleID?.lowercased().split(separator: ".").contains { String($0) == squashed } == true
        }?.identity
    }

    /// Finds an installed app signed by `teamID`, reading signatures once on first use.
    public func app(teamID: String) -> AppIdentity? {
        lock.lock()
        defer { lock.unlock() }
        if teams == nil {
            var map: [String: AppIdentity] = [:]
            for entry in entries {
                if let team = CodeSigningTeam.teamID(ofAppAt: entry.path), map[team] == nil { map[team] = entry.identity }
            }
            teams = map
        }
        return teams?[teamID]
    }

    /// Finds an app that shares a dotted prefix, or a vendor, with `bundleID`.
    public func relatedApp(toBundleID bundleID: String) -> AppIdentity? {
        let wanted = bundleID.lowercased()
        let vendor = wanted.split(separator: ".").prefix(2).joined(separator: ".")
        return entries.first { entry in
            guard let id = entry.identity.bundleID?.lowercased() else { return false }
            return id.hasPrefix(wanted + ".") || wanted.hasPrefix(id + ".") || id.hasPrefix(vendor + ".") || id == vendor
        }?.identity
    }

    /// Adds every `.app` found under `directory`, descending through plain folders up to `depth` levels.
    private static func collect(in directory: String, depth: Int, into found: inout [Entry]) {
        guard depth > 0, let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return }
        for name in names where !name.hasPrefix(".") {
            let path = directory + "/" + name
            if name.hasSuffix(".app") {
                if let entry = entry(forApp: path) { found.append(entry) }
            } else {
                collect(in: path, depth: depth - 1, into: &found)
            }
        }
    }

    /// Reads an app's identifier and names from its Info.plist.
    private static func entry(forApp path: String) -> Entry? {
        let fileName = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let plist = (NSDictionary(contentsOfFile: path + "/Contents/Info.plist") as? [String: Any]) ?? [:]
        let bundleID = plist["CFBundleIdentifier"] as? String
        let candidates = [fileName, plist["CFBundleName"] as? String, plist["CFBundleDisplayName"] as? String,
                          plist["CFBundleExecutable"] as? String]
        let names = Array(Set(candidates.compactMap { $0?.lowercased() }))
        let display = (plist["CFBundleDisplayName"] as? String) ?? (plist["CFBundleName"] as? String) ?? fileName
        let identity = AppIdentity(bundleID: bundleID, name: fileName == display ? fileName : display)
        guard bundleID != nil || !fileName.isEmpty else { return nil }
        return Entry(identity: identity, path: path, names: names)
    }

    /// Asks Launch Services for an app with this identifier.
    private func launchServicesApp(bundleID: String) -> AppIdentity? {
        guard let urls = LSCopyApplicationURLsForBundleIdentifier(bundleID as CFString, nil)?.takeRetainedValue() as? [URL],
              let url = urls.first else { return nil }
        return AppIdentity(bundleID: bundleID, name: url.deletingPathExtension().lastPathComponent)
    }
}

/// Reads a developer team identifier from an app's code signature, without validating it.
enum CodeSigningTeam {
    /// The team identifier of the app at `path`, or nil when unsigned or unreadable.
    static func teamID(ofAppAt path: String) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any] else { return nil }
        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    }
}

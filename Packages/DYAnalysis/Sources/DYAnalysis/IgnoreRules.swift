import Foundation

/// One user-visible ignore rule. Patterns are gitignore-like; see `IgnoreEngine`.
public struct IgnoreRule: Codable, Identifiable, Sendable {
    public var id: UUID
    /// `name`, `a/b`, `/absolute/path` or `~/path`, with `*` and `?`. A leading `!` keeps matches visible and beats hide.
    public var pattern: String
    public var enabled: Bool
    public var label: String
    /// Built-in rules can be disabled but not deleted by the UI.
    public var isPreset: Bool

    /// Creates a rule.
    public init(id: UUID = UUID(), pattern: String, enabled: Bool = true, label: String = "", isPreset: Bool = false) {
        self.id = id
        self.pattern = pattern
        self.enabled = enabled
        self.label = label.isEmpty ? pattern : label
        self.isPreset = isPreset
    }
}

/// An ordered list of ignore rules.
public struct IgnoreRuleSet: Codable, Sendable {
    public var rules: [IgnoreRule]

    /// Creates a set from rules.
    public init(rules: [IgnoreRule]) { self.rules = rules }

    /// The built-in rules, from the research notes: macOS plumbing is hidden, and every reclaim target stays visible.
    public static let defaults = IgnoreRuleSet(rules: presets())

    /// Builds the preset rules with stable ids, so saved enable/disable choices survive relaunch.
    private static func presets() -> [IgnoreRule] {
        let hidden: [(String, String)] = [
            (".DS_Store", "Finder view settings"),
            (".Spotlight-V100", "Spotlight index"),
            (".fseventsd", "FSEvents log"),
            (".DocumentRevisions-V100", "Document versions database"),
            (".TemporaryItems", "OS temporary items"),
            (".PreviousSystemInformation", "Upgrade leftovers"),
            (".com.apple.templatemigration.boot-install", "Upgrade leftovers"),
            ("._*", "AppleDouble companion files"),
            ("Icon\r", "Custom folder icons"),
            (".localized", "Localisation marker"),
            (".CFUserTextEncoding", "Text encoding marker"),
            (".apdisk", "Volume marker"),
            (".VolumeIcon.icns", "Volume icon"),
            (".hidden", "Hidden-name list"),
            ("/.vol", "Synthetic APFS entry"),
            ("/.file", "Synthetic APFS entry"),
            ("/.nofollow", "Synthetic APFS entry"),
            ("/.resolve", "Synthetic APFS entry"),
            ("/System/Volumes/VM", "System volume"),
            ("/System/Volumes/Preboot", "System volume"),
            ("/System/Volumes/Update", "System volume"),
            ("/System/Volumes/xarts", "System volume"),
            ("/System/Volumes/iSCPreboot", "System volume"),
            ("/System/Volumes/Hardware", "System volume"),
        ]
        let kept: [(String, String)] = [
            ("~/Library/Caches", "Caches stay visible"),
            ("~/Library/Logs", "Logs stay visible"),
            ("~/Library/Developer", "Developer data stays visible"),
            ("~/Library/Application Support", "Application data stays visible"),
            ("~/.Trash", "Trash stays visible"),
            ("/Library/Caches", "System caches stay visible"),
            ("~/.cache", "Caches stay visible"),
            ("~/.npm", "Package caches stay visible"),
            ("~/.gradle", "Package caches stay visible"),
            ("~/.cocoapods", "Package caches stay visible"),
            (".Trashes", "Volume Trash stays visible"),
        ]
        var rules: [IgnoreRule] = []
        for (pattern, label) in hidden {
            rules.append(IgnoreRule(id: stableID(rules.count), pattern: pattern, label: label, isPreset: true))
        }
        for (pattern, label) in kept {
            rules.append(IgnoreRule(id: stableID(rules.count), pattern: "!" + pattern, label: label, isPreset: true))
        }
        return rules
    }

    /// A deterministic UUID for the preset at `index`.
    private static func stableID(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "D1E7A000-0000-4000-8000-%012X", index + 1)) ?? UUID()
    }
}

/// What the rules hid.
public struct IgnoreResult: Sendable {
    /// Per node: hidden by a rule, or inside a hidden node.
    public var hidden: [Bool]
    /// Bytes and files per rule, counted once at each topmost hidden node.
    public var perRule: [UUID: (bytes: UInt64, files: UInt64)]
}

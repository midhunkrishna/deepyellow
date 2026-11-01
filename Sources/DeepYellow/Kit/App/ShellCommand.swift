import AppKit
import DYCore
import DYWorkspace

/// A direction for moving the selection.
public enum MoveDirection: Equatable { case left, right, up, down }

/// Every command the shell offers. The same list drives keys, the menu bar, the palette and the shortcut overlay.
public enum ShellCommand: Equatable {
    case lens(LensKind)
    case mark(Decision)
    case review, openPlan, togglePreview, focusQuery, toggleMetric, cycleColor, hide
    case zoomIn, zoomOut, undo, redo, openPalette, openLedger, escape
    case toggleSQL, runSQL, copyReviewPath
    case chooseFolder, openDemo, rescan, installCLI, toggleHints
    case move(MoveDirection)

    /// A command as shown to people: title, key and where it belongs.
    public struct Info {
        public var title: String
        public var key: String
        public var command: ShellCommand
    }

    /// The commands offered in the palette and the shortcut overlay, in display order.
    public static let catalog: [Info] = {
        let lenses = LensKind.allCases.enumerated().map { Info(title: "Show \(lensTitle($1))", key: "\($0 + 1)", command: .lens($1)) }
        return lenses + [
            Info(title: "Keep selection", key: "k", command: .mark(.keep)),
            Info(title: "Mark selection for removal", key: "x", command: .mark(.remove)),
            Info(title: "Decide selection later", key: "l", command: .mark(.later)),
            Info(title: "Clear mark", key: "u", command: .mark(.none)),
            Info(title: "Review the current set", key: "r", command: .review),
            Info(title: "Open the Plan", key: "⌘⏎", command: .openPlan),
            Info(title: "Toggle preview", key: "Space", command: .togglePreview),
            Info(title: "Focus the query field", key: "/", command: .focusQuery),
            Info(title: "Switch between size and file count", key: "m", command: .toggleMetric),
            Info(title: "Cycle colour mode", key: "c", command: .cycleColor),
            Info(title: "Hide selection", key: "h", command: .hide),
            Info(title: "Go into the selected folder", key: "⏎", command: .zoomIn),
            Info(title: "Zoom out", key: "⌫", command: .zoomOut),
            Info(title: "Undo", key: "⌘Z", command: .undo),
            Info(title: "Redo", key: "⇧⌘Z", command: .redo),
            Info(title: "Open the Ledger", key: "", command: .openLedger),
            Info(title: "Show or hide the SQL drawer", key: "s", command: .toggleSQL),
            Info(title: "Run the SQL query", key: "⌘⏎", command: .runSQL),
            Info(title: "Copy the path shown in Review", key: "⌘C", command: .copyReviewPath),
            Info(title: "Choose a folder to scan…", key: "⌘O", command: .chooseFolder),
            Info(title: "Open the sample disk", key: "", command: .openDemo),
            Info(title: "Rescan", key: "⌘R", command: .rescan),
            Info(title: "Install Command Line Tool…", key: "", command: .installCLI),
        ]
    }()

    /// The tab and menu title of a lens.
    public static func lensTitle(_ kind: LensKind) -> String {
        switch kind {
        case .map: "Map"
        case .things: "Things"
        case .spectrum: "Spectrum"
        case .field: "Field"
        case .rings: "Rings"
        case .browse: "Browse"
        case .reclaim: "Reclaim"
        }
    }
}

/// Turns a key press into a command. Pure, so it can be tested without a window.
public enum KeyMap {
    /// The command for a key, or nil when the key isn't ours. `characters` is the unmodified character.
    public static func command(characters: String?, keyCode: UInt16, flags: NSEvent.ModifierFlags) -> ShellCommand? {
        let mods = flags.intersection([.command, .control, .option, .shift])
        let key = characters?.lowercased() ?? ""
        if mods.contains(.command) {
            if mods == .command, key == "k" { return .openPalette }
            if mods == .command, key == "c" { return .copyReviewPath }
            if mods == .command, keyCode == 36 || keyCode == 76 { return .openPlan }
            return nil
        }
        if !mods.subtracting(.shift).isEmpty { return nil }
        switch keyCode {
        case 53: return .escape
        case 49: return .togglePreview
        case 36, 76: return .zoomIn
        case 51, 117: return .zoomOut
        case 123: return .move(.left)
        case 124: return .move(.right)
        case 125: return .move(.down)
        case 126: return .move(.up)
        default: break
        }
        if let index = Int(key), (1...7).contains(index) { return .lens(LensKind.allCases[index - 1]) }
        switch key {
        case "k": return .mark(.keep)
        case "x": return .mark(.remove)
        case "l": return .mark(.later)
        case "u": return .mark(.none)
        case "r": return .review
        case "/": return .focusQuery
        case "m": return .toggleMetric
        case "c": return .cycleColor
        case "h": return .hide
        case "s": return .toggleSQL
        default: return nil
        }
    }
}

/// Builds query terms from a Field brush so the brush stays visible and editable in the query field.
public enum BrushQuery {
    private static let brushPrefixes = ["age>", "age<", "opened>", "opened<", "size>", "size<"]

    /// Replaces any earlier brush terms in `existing` with terms for the brushed range.
    /// `age` is in log10 days, `size` in log10 bytes.
    public static func apply(to existing: String, age: ClosedRange<Float>, size: ClosedRange<Float>, clock: String) -> String {
        let kept = existing.split(separator: " ").map(String.init).filter { word in
            !brushPrefixes.contains { word.lowercased().hasPrefix($0) }
        }
        let low = Int(pow(10, Double(age.lowerBound)).rounded(.down))
        let high = Int(pow(10, Double(age.upperBound)).rounded(.up))
        let terms = ["\(clock)>\(low)d", "\(clock)<\(high)d",
                     "size>\(bytesTerm(pow(10, Double(size.lowerBound)), up: false))", "size<\(bytesTerm(pow(10, Double(size.upperBound)), up: true))"]
        return (kept + terms).joined(separator: " ")
    }

    /// Writes a byte count as a whole number with a unit, such as `1230mb`, so the query language needs no decimals.
    static func bytesTerm(_ bytes: Double, up: Bool) -> String {
        let units: [(String, Double)] = [("tb", 1e12), ("gb", 1e9), ("mb", 1e6), ("kb", 1e3), ("b", 1)]
        for (name, factor) in units {
            let value = bytes / factor
            if value >= 100 { return "\(Int(up ? value.rounded(.up) : value.rounded(.down)))\(name)" }
        }
        return "\(Int(bytes))b"
    }
}

/// Where a key press goes, given what has keyboard focus.
public enum KeyRoute: Equatable {
    /// Run the command.
    case perform(ShellCommand)
    /// Take focus out of the text field being edited.
    case leaveTextField
    /// Leave the event to the text field.
    case passThrough
}

/// Decides what a command does when a text field may be taking the keys. Single-key shortcuts never fire while typing.
public enum KeyRouter {
    /// `⌘⏎` runs the query while the SQL editor has focus and opens the Plan everywhere else.
    public static func route(_ command: ShellCommand, typing: Bool, sqlEditorFocused: Bool) -> KeyRoute {
        guard typing else { return .perform(command) }
        switch command {
        case .escape: return .leaveTextField
        case .openPlan: return .perform(sqlEditorFocused ? .runSQL : .openPlan)
        case .openPalette: return .perform(.openPalette)
        default: return .passThrough
        }
    }
}

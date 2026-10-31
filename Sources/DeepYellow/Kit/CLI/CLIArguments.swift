import Foundation

/// What a launch of the CLI should open in the app.
public struct OpenRequest: Equatable {
    /// The folder to open, already made absolute, or nil for the sample disk.
    public var path: String?
    /// Open the built-in sample disk.
    public var demo: Bool
    /// Print what would be handed to the system instead of opening anything.
    public var dryRun: Bool
    /// Open a real scan in a session whose Trash mover refuses every call.
    public var readOnly: Bool

    /// Creates a request.
    public init(path: String?, demo: Bool, dryRun: Bool, readOnly: Bool = false) {
        self.path = path; self.demo = demo; self.dryRun = dryRun; self.readOnly = readOnly
    }
}

/// A parsed command line.
public enum CLICommand: Equatable {
    case help(topic: String?)
    case version
    case open(OpenRequest)
    case things(path: String, minimumBytes: UInt64?, top: Int?, json: Bool)
    case reclaim(path: String, json: Bool)
    case spectrum(path: String, json: Bool)
    case dupes(path: String, minimumBytes: UInt64, json: Bool)
}

/// A mistake in the arguments. Reported on standard error with exit code 64.
public struct CLIUsageError: Error, Equatable {
    public var message: String
    /// Creates an error with a plain-words message.
    public init(_ message: String) { self.message = message }
}

/// Turns the words after `deepyellow` into a `CLICommand`.
public enum CLIParser {
    static let subcommands: Set<String> = ["things", "reclaim", "spectrum", "dupes"]
    /// The smallest file the duplicate finder looks at unless `--min` says otherwise.
    public static let defaultDuplicateMinimum: UInt64 = 1_000_000

    /// Parses `arguments` (without the program name and without `--cli`).
    public static func parse(_ arguments: [String]) throws -> CLICommand {
        var flags = Flags()
        var positional: [String] = []
        var index = 0
        while index < arguments.count {
            let word = arguments[index]
            index += 1
            if let (name, inline) = splitOption(word) {
                try flags.apply(name: name, inline: inline, rest: arguments, index: &index)
            } else {
                positional.append(word)
            }
        }
        return try flags.command(positional: positional)
    }

    /// Splits `--name=value` into its parts; nil for words that aren't options.
    private static func splitOption(_ word: String) -> (String, String?)? {
        guard word.hasPrefix("-"), word.count > 1 else { return nil }
        guard let equals = word.firstIndex(of: "=") else { return (word, nil) }
        return (String(word[..<equals]), String(word[word.index(after: equals)...]))
    }

    /// Everything the options can set, gathered before the subcommand decides what matters.
    private struct Flags {
        var help = false, version = false, demo = false, dryRun = false, json = false, readOnly = false
        var minimum: UInt64?
        var top: Int?

        /// Records one option, reading its value from `inline` or the next word.
        mutating func apply(name: String, inline: String?, rest: [String], index: inout Int) throws {
            switch name {
            case "--help", "-h": help = true
            case "--version": version = true
            case "--demo": demo = true
            case "--json": json = true
            case "--print-open-args": dryRun = true
            case "--read-only": readOnly = true
            case "--min":
                let text = try value(name, inline, rest, &index)
                guard let bytes = SizeParser.parse(text) else { throw CLIUsageError("--min needs a size such as 100mb, not '\(text)'") }
                minimum = bytes
            case "--top":
                let text = try value(name, inline, rest, &index)
                guard let count = Int(text), count > 0 else { throw CLIUsageError("--top needs a positive number, not '\(text)'") }
                top = count
            default: throw CLIUsageError("unknown option '\(name)'. Try: deepyellow --help")
            }
        }

        /// The value for an option that takes one.
        private func value(_ name: String, _ inline: String?, _ rest: [String], _ index: inout Int) throws -> String {
            if let inline { return inline }
            guard index < rest.count else { throw CLIUsageError("\(name) needs a value") }
            defer { index += 1 }
            return rest[index]
        }

        /// Picks the command from the first positional word.
        func command(positional: [String]) throws -> CLICommand {
            if version { return .version }
            let first = positional.first
            if help { return .help(topic: first.flatMap { CLIParser.subcommands.contains($0) ? $0 : nil }) }
            if demo { return .open(OpenRequest(path: nil, demo: true, dryRun: dryRun)) }
            if readOnly, positional.isEmpty { throw CLIUsageError("--read-only needs a folder to scan") }
            guard let first else { throw CLIUsageError("missing a command or a folder. Try: deepyellow --help") }
            guard CLIParser.subcommands.contains(first) else {
                guard positional.count == 1 else { throw CLIUsageError("only one folder can be opened at a time") }
                return .open(OpenRequest(path: first, demo: false, dryRun: dryRun, readOnly: readOnly))
            }
            guard positional.count == 2 else { throw CLIUsageError("\(first) needs exactly one folder. Try: deepyellow \(first) --help") }
            let path = positional[1]
            switch first {
            case "things": return .things(path: path, minimumBytes: minimum, top: top, json: json)
            case "reclaim": return .reclaim(path: path, json: json)
            case "spectrum": return .spectrum(path: path, json: json)
            default: return .dupes(path: path, minimumBytes: minimum ?? CLIParser.defaultDuplicateMinimum, json: json)
            }
        }
    }
}

/// Reads sizes such as `100mb`, `1.5 GB` or `4096`. Units are decimal, like Finder.
public enum SizeParser {
    /// Returns the byte count, or nil when `text` isn't a size.
    public static func parse(_ text: String) -> UInt64? {
        let lowered = text.lowercased().trimmingCharacters(in: .whitespaces)
        let units: [(String, Double)] = [("tb", 1e12), ("gb", 1e9), ("mb", 1e6), ("kb", 1e3), ("b", 1)]
        var number = lowered
        var scale = 1.0
        for (suffix, factor) in units where lowered.hasSuffix(suffix) {
            number = String(lowered.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            scale = factor
            break
        }
        guard let value = Double(number), value >= 0, value.isFinite else { return nil }
        return UInt64(value * scale)
    }
}

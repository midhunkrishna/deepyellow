import Foundation

/// The text printed by `--help`.
public enum CLIHelp {
    /// Help for the whole tool, or for one subcommand.
    public static func text(topic: String?) -> String {
        switch topic {
        case "things": return """
            usage: deepyellow things <path> [--min 100mb] [--top N] [--json]

            Ranked list of the biggest things under <path>: files and folders as peers, cut at a size
            threshold so the list is disjoint and adds up to the total. Without --min the threshold is
            chosen to give about 25 rows.

            JSON: {"path", "total", "thresholdBytes", "things": [{"path", "name", "bytes", "files",
            "kind": "item" | "rest", "items"?}]}. A "rest" row stands for the smaller items inside "path".
            """
        case "reclaim": return """
            usage: deepyellow reclaim <path> [--json]

            Safety groups from the built-in rules, then the worklists: forgotten large things, leftovers of
            apps that look gone, and the largest things you haven't decided about. Cleanup commands are
            printed, never run. Duplicates are not read here; use `deepyellow dupes`.

            JSON: {"path", "total", "groups": [{"id", "title", "tier", "bytes", "reclaimableBytes", "files",
            "items", "cleanupCommand"}], "worklists": [{"kind", "title", "why", "bytes", "files", "items",
            "top": [{"path", "bytes"}]}]}
            """
        case "spectrum": return """
            usage: deepyellow spectrum <path> [--json]

            How many files and how many bytes fall in each size range (three ranges per decade).

            JSON: {"path", "totalFiles", "totalBytes", "filesHolding80PercentOfBytes", "bins": [{"lower",
            "upper", "files", "bytes"}]}
            """
        case "dupes": return """
            usage: deepyellow dupes <path> [--min 1mb] [--json]

            Exact duplicates: same size, same head and tail, same SHA-256. Hard links and clones of the same
            data are not duplicates, and iCloud placeholders are skipped, never downloaded. Files are read, never
            changed. --min sets the smallest file considered (default 1mb).

            JSON: {"path", "bytesHashed", "wastedBytes", "sets": [{"size", "copies", "wastedBytes",
            "paths": [...]}]}
            """
        default: return """
            deepyellow: read a folder and print what DeepYellow would show. It is read-only and has no delete command.

            usage:
              deepyellow <path>                        open the app on a folder (works when already running)
              deepyellow --demo                        open the app on the sample disk
              deepyellow things <path> [--min 100mb] [--top N] [--json]
              deepyellow reclaim <path> [--json]
              deepyellow spectrum <path> [--json]
              deepyellow dupes <path> [--min 1mb] [--json]
              deepyellow --version | --help

            Run `deepyellow <command> --help` for the exact JSON fields.
            Colour: truecolor bars on a terminal; plain text when piped or when NO_COLOR is set.
            Exit codes: 0 success, 2 the path does not exist or is not a folder, 64 bad arguments.
            """
        }
    }
}

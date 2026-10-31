import DYDecide
import DYWorkspace
import Foundation

/// What the GUI was asked to do, read from the process arguments.
public struct LaunchOptions: Equatable {
    /// Use the sample disk and the in-memory fake Trash.
    public var demo = false
    /// A screenshot scenario to render offscreen, then quit.
    public var shot: String?
    /// Where the screenshot goes.
    public var out: String?
    /// Folders to open, in order.
    public var paths: [String] = []
    /// A real scan whose Trash mover refuses every call.
    public var readOnly = false

    /// True for `--demo` and for a `--shot` without `--read-only`: both use the demo environment.
    public var isDemo: Bool { demo || (shot != nil && !readOnly) }

    /// Reads `--demo`, `--shot <name>`, `--out <file>` and folder paths. Unknown options (for example the ones macOS adds) are ignored.
    public static func parse(_ arguments: [String]) -> LaunchOptions {
        var options = LaunchOptions()
        var index = 0
        while index < arguments.count {
            let word = arguments[index]
            index += 1
            switch word {
            case "--demo": options.demo = true
            case "--read-only": options.readOnly = true
            case "--shot": if index < arguments.count { options.shot = arguments[index]; index += 1 }
            case "--out": if index < arguments.count { options.out = arguments[index]; index += 1 }
            default: if !word.hasPrefix("-") { options.paths.append(word) }
            }
        }
        return options
    }
}

/// Which Trash mover a session gets.
public enum MoverKind: Equatable {
    /// The in-memory fake that never touches the disk.
    case demo
    /// The real Trash. Only a normal launch gets it.
    case system
    /// A mover that fails every call, for `--read-only` sessions. There is no path from it to the real Trash.
    case refusing
}

/// Builds the workspace for a launch. This is the one place that names `SystemTrash`.
public enum Composition {
    /// The real mover is chosen only when the source isn't demo.
    public static func moverKind(for options: LaunchOptions) -> MoverKind {
        if options.isDemo { return .demo }
        return options.readOnly ? .refusing : .system
    }

    /// The data directory: a scratch folder for demos, `DEEPYELLOW_HOME` or a scratch folder for read-only screenshots, else the default.
    public static func dataDirectory(options: LaunchOptions, environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if options.isDemo { return demoDataDirectory(options: options, environment: environment) }
        if options.shot != nil {
            if let home = environment["DEEPYELLOW_HOME"], !home.isEmpty { return URL(fileURLWithPath: home, isDirectory: true) }
            return FileManager.default.temporaryDirectory.appendingPathComponent("DeepYellowShot-\(UUID().uuidString)", isDirectory: true)
        }
        return WorkspaceEnvironment.defaultDataDirectory(environment: environment)
    }

    /// A scratch folder for demo state, so a demo never writes into Application Support.
    /// `DEEPYELLOW_HOME` is honoured when set, except for screenshots, which always start clean.
    public static func demoDataDirectory(options: LaunchOptions, environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if options.shot == nil, let home = environment["DEEPYELLOW_HOME"], !home.isEmpty {
            return URL(fileURLWithPath: home, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("DeepYellowDemo-\(UUID().uuidString)", isDirectory: true)
    }

    /// The workspace environment for `options`.
    public static func environment(for options: LaunchOptions, demoDirectory: URL) -> WorkspaceEnvironment {
        switch moverKind(for: options) {
        case .demo:
            var environment = WorkspaceEnvironment.demo(dataDirectory: demoDirectory)
            environment.previewLocation = DemoMedia.locator(in: DemoMedia.folder(in: demoDirectory))
            return environment
        case .refusing: return .live(mover: RefusingTrash(), dataDirectory: demoDirectory)
        case .system: return .live(mover: SystemTrash(), dataDirectory: demoDirectory)
        }
    }
}

/// The process entry point shared by the GUI and the CLI.
public enum EntryPoint {
    /// Runs the CLI for `--cli`, `--version` and `--help`; otherwise starts the GUI. Returns the exit code.
    public static func run(arguments: [String]) -> Int32 {
        let rest = Array(arguments.dropFirst())
        if rest.first == "--cli" { return CLI.run(arguments: Array(rest.dropFirst()), context: .process()) }
        if rest.contains("--version") || rest.contains("--help") { return CLI.run(arguments: rest, context: .process()) }
        return MainActor.assumeIsolated { GUILauncher.run(options: LaunchOptions.parse(rest)) }
    }
}

/// A Trash mover that refuses every request, so a read-only session can't move anything.
public struct RefusingTrash: TrashMoving {
    /// The reason given for every refusal.
    public struct Refused: Error, LocalizedError {
        public var errorDescription: String? { "Read-only: nothing can be moved." }
    }

    /// Creates the mover.
    public init() {}

    /// Always throws.
    public func moveToTrash(path: String) throws -> String { throw Refused() }
    /// Always throws.
    public func moveBack(from: String, to: String) throws { throw Refused() }
    /// Always throws.
    public func currentFingerprint(path: String) throws -> Fingerprint { throw Refused() }
}

import AppKit
import DYAdvisor
import DYCore
import DYScan
import DYWorkspace
import Foundation

/// Everything the CLI touches outside its own logic, so tests can replace it.
public struct CLIContext {
    public var isTTY: Bool
    public var environment: [String: String]
    public var home: String
    public var out: (String) -> Void
    public var err: (String) -> Void
    /// Hands an open request to the system; returns the exit code.
    public var open: (OpenRequest) -> Int32

    /// The real process: standard streams, the user's home and the system opener.
    public static func process() -> CLIContext {
        CLIContext(isTTY: isatty(1) != 0, environment: ProcessInfo.processInfo.environment, home: NSHomeDirectory(),
                   out: { FileHandle.standardOutput.write(Data($0.utf8)) }, err: { FileHandle.standardError.write(Data($0.utf8)) },
                   open: { AppOpener.open($0) })
    }
}

/// The `deepyellow` command: parses, scans, runs an engine and prints. It never changes a file.
public enum CLI {
    /// Runs the command and returns the process exit code.
    public static func run(arguments: [String], context: CLIContext) -> Int32 {
        let command: CLICommand
        do { command = try CLIParser.parse(arguments) } catch let error as CLIUsageError {
            context.err("deepyellow: \(error.message)\n")
            return 64
        } catch { return 64 }
        let style = OutputStyle.detect(isTTY: context.isTTY, environment: context.environment)
        switch command {
        case .help(let topic): context.out(CLIHelp.text(topic: topic) + "\n"); return 0
        case .version: context.out("DeepYellow \(AppVersion.current)\n"); return 0
        case .open(var request):
            if let path = request.path {
                guard let resolved = resolveFolder(path) else { return missing(path, context) }
                request.path = resolved
            }
            return context.open(request)
        case .things(let path, let minimum, let top, let json):
            return withTree(path, context) { tree in
                let report = CLIAnalysis.things(tree: tree, minimumBytes: minimum, top: top)
                context.out(json ? CLIRender.thingsJSON(report) : CLIRender.things(report, style: style))
            }
        case .reclaim(let path, let json):
            return withTree(path, context) { tree in
                let summary = CLIAnalysis.reclaim(tree: tree, home: context.home, catalog: SystemAppCatalog())
                context.out(json ? CLIRender.reclaimJSON(summary) : CLIRender.reclaim(summary, style: style))
            }
        case .spectrum(let path, let json):
            return withTree(path, context) { tree in
                let summary = CLIAnalysis.spectrum(tree: tree)
                context.out(json ? CLIRender.spectrumJSON(summary) : CLIRender.spectrum(summary, style: style))
            }
        case .dupes(let path, let minimum, let json):
            return withTree(path, context) { tree in
                let summary = CLIScan.blocking { await CLIAnalysis.duplicates(tree: tree, minimumBytes: minimum, reader: LocalFileReader(), progress: { _ in }) }
                context.out(json ? CLIRender.dupesJSON(summary) : CLIRender.dupes(summary, style: style))
            }
        }
    }

    /// Resolves `path` to an absolute folder path, or nil when it doesn't exist or isn't a folder.
    public static func resolveFolder(_ path: String) -> String? {
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        return url.path
    }

    /// Reports an unknown path on standard error. Exit code 2.
    private static func missing(_ path: String, _ context: CLIContext) -> Int32 {
        context.err("deepyellow: no such folder: \(path)\n")
        return 2
    }

    /// Scans `path`, shows a progress line on a terminal, then runs `body`.
    private static func withTree(_ path: String, _ context: CLIContext, _ body: (FileTree) -> Void) -> Int32 {
        guard let resolved = resolveFolder(path) else { return missing(path, context) }
        let showProgress = isatty(2) != 0 && context.isTTY
        var progress: (@Sendable (ScanProgress) -> Void)?
        if showProgress {
            progress = { value in FileHandle.standardError.write(Data("\rScanning… \(Format.count(value.files)) files".utf8)) }
        }
        let tree = CLIScan.scan(path: resolved, progress: progress)
        if showProgress { FileHandle.standardError.write(Data("\r\u{1B}[2K".utf8)) }
        if tree.meta.unreadableDirectories > 0 {
            context.err("deepyellow: \(tree.meta.unreadableDirectories) folders could not be read; totals are partial. See: Full Disk Access.\n")
        }
        body(tree)
        return 0
    }
}

/// The app version stamped into Info.plist by the packaging script.
public enum AppVersion {
    /// `0.0.0-dev` for a plain `swift run`.
    public static var current: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0-dev" }
}

/// Opens DeepYellow through the system, so it works whether or not the app is already running.
public enum AppOpener {
    public static let bundleID = "com.midhunkrishna.deepyellow"

    /// The app bundle holding the running binary, else the installed app with the bundle identifier.
    public static func appURL() -> URL? {
        var url = URL(fileURLWithPath: ProcessInfo.processInfo.arguments.first ?? "").resolvingSymlinksInPath()
        while url.path != "/" {
            if url.pathExtension == "app" { return url }
            url.deleteLastPathComponent()
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    /// The launch arguments a request needs. A read-only session is its own instance, so it never shares a window with a normal one.
    public static func arguments(for request: OpenRequest) -> [String] {
        if request.demo { return ["--demo"] }
        if request.readOnly, let path = request.path { return ["--read-only", path] }
        return []
    }

    /// Demo and read-only sessions start a new instance of the app.
    public static func needsNewInstance(_ request: OpenRequest) -> Bool { request.demo || request.readOnly }

    /// The lines `--print-open-args` prints: exactly what would be handed to the system.
    public static func description(of request: OpenRequest, appURL: URL?) -> String {
        var lines = ["app: \(appURL?.path ?? "(not found)")"]
        if let path = request.path, !request.readOnly { lines.append("open: \(path)") }
        lines.append("arguments: \(arguments(for: request).joined(separator: " ").nonEmpty ?? "(none)")")
        lines.append("new instance: \(needsNewInstance(request) ? "yes" : "no")")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Opens the request, or prints it for a dry run. Returns the exit code.
    public static func open(_ request: OpenRequest) -> Int32 {
        let app = appURL()
        if request.dryRun {
            FileHandle.standardOutput.write(Data(description(of: request, appURL: app).utf8))
            return 0
        }
        guard let app else {
            FileHandle.standardError.write(Data("deepyellow: can't find DeepYellow.app\n".utf8))
            return 1
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = arguments(for: request)
        configuration.createsNewApplicationInstance = needsNewInstance(request)
        let done = DispatchSemaphore(value: 0)
        let failure = ResultBox<String>()
        let finish: @Sendable (Error?) -> Void = { error in failure.value = error?.localizedDescription; done.signal() }
        if let path = request.path, !request.readOnly {
            NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: app, configuration: configuration) { _, error in finish(error) }
        } else {
            NSWorkspace.shared.openApplication(at: app, configuration: configuration) { _, error in finish(error) }
        }
        _ = done.wait(timeout: .now() + 15)
        if let message = failure.value {
            FileHandle.standardError.write(Data("deepyellow: \(message)\n".utf8))
            return 1
        }
        return 0
    }
}

private extension String {
    /// The string, or nil when it is empty.
    var nonEmpty: String? { isEmpty ? nil : self }
}

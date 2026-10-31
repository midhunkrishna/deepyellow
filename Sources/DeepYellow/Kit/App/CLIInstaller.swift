import Foundation

/// Creates the `deepyellow` symlink, only ever from an explicit click, and never over a file that isn't a link.
public struct CLIInstaller {
    /// The app's CLI script: `DeepYellow.app/Contents/Resources/bin/deepyellow`.
    public var scriptURL: URL

    /// The default destination that needs no administrator rights.
    public static var defaultDirectory: URL { URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".local/bin", isDirectory: true) }

    /// What happened.
    public enum Outcome: Equatable {
        case installed(link: String, onPath: Bool)
        case alreadyInstalled(link: String)
        case refused(String)
    }

    /// Creates a locator for the script inside the running app bundle.
    public static func forRunningApp() -> CLIInstaller? {
        guard let app = AppOpener.appURL() else { return nil }
        return CLIInstaller(scriptURL: app.appendingPathComponent("Contents/Resources/bin/deepyellow"))
    }

    /// Links `directory/deepyellow` to the script. An existing link to another place is replaced; any other file is left alone.
    public func install(into directory: URL, environment: [String: String] = ProcessInfo.processInfo.environment) -> Outcome {
        let fm = FileManager.default
        guard fm.fileExists(atPath: scriptURL.path) else { return .refused("The command script isn't inside this app bundle: \(scriptURL.path)") }
        let link = directory.appendingPathComponent("deepyellow")
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            if let existing = try? fm.destinationOfSymbolicLink(atPath: link.path) {
                if existing == scriptURL.path { return .alreadyInstalled(link: link.path) }
                try fm.removeItem(at: link)
            } else if fm.fileExists(atPath: link.path) {
                return .refused("\(link.path) already exists and isn't a link, so it was left alone.")
            }
            try fm.createSymbolicLink(at: link, withDestinationURL: scriptURL)
        } catch {
            return .refused(error.localizedDescription)
        }
        let path = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        return .installed(link: link.path, onPath: path.contains(directory.path))
    }
}

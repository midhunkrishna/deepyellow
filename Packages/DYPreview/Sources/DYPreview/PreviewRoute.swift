import DYCore
import Foundation

/// Which renderer shows an item.
public enum PreviewRoute: Sendable, Equatable {
    case dataless, directory, video, image, audio, pdf, text, quickLook

    static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "log", "json", "xml", "yaml", "yml", "csv", "tsv", "ini", "conf", "cfg",
        "plist", "toml", "swift", "py", "js", "ts", "c", "h", "cpp", "m", "rs", "go", "java", "sh", "zsh",
        "html", "css", "sql", "strings", "rtf",
    ]

    /// Chooses the renderer. A dataless item always routes to `.dataless`, whatever its kind, so nothing
    /// downstream can open it.
    public static func route(for item: PreviewItem) -> PreviewRoute {
        if item.isDataless { return .dataless }
        if item.isDirectory { return .directory }
        let ext = item.url.pathExtension.lowercased()
        switch item.kind {
        case .video: return .video
        case .image: return .image
        case .audio: return .audio
        case .code: return .text
        case .document: return ext == "pdf" ? .pdf : (textExtensions.contains(ext) ? .text : .quickLook)
        case .application, .archive: return .quickLook
        case .other: return textExtensions.contains(ext) ? .text : .quickLook
        }
    }
}

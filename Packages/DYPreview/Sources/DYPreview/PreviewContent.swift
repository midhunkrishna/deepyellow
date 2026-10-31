import CoreGraphics
import Foundation

/// What a loaded item will display.
public enum PreviewContent: Sendable {
    case empty
    case dataless
    case directory([PreviewChild])
    case video(URL)
    case image(CGImage)
    case audio(Waveform)
    case pdf(URL)
    case text(String)
    case quickLook(URL)
}

/// The functions that touch file contents. Injected so tests can prove which ones run.
public struct PreviewLoaders: Sendable {
    public var image: @Sendable (URL, CGFloat) async -> CGImage?
    public var isPlayable: @Sendable (URL) async -> Bool
    public var pdfPageCount: @Sendable (URL) async -> Int
    public var text: @Sendable (URL) async -> String?
    public var waveform: @Sendable (URL) async -> Waveform?

    /// Creates loaders from closures.
    public init(image: @escaping @Sendable (URL, CGFloat) async -> CGImage?,
                isPlayable: @escaping @Sendable (URL) async -> Bool,
                pdfPageCount: @escaping @Sendable (URL) async -> Int,
                text: @escaping @Sendable (URL) async -> String?,
                waveform: @escaping @Sendable (URL) async -> Waveform?) {
        self.image = image
        self.isPlayable = isPlayable
        self.pdfPageCount = pdfPageCount
        self.text = text
        self.waveform = waveform
    }
}

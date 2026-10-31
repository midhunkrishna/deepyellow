import AVFoundation
import Foundation
import PDFKit

extension PreviewLoaders {
    /// The real loaders. Each one opens its file read-only.
    public static let live = PreviewLoaders(
        image: { url, side in
            await Task.detached(priority: .userInitiated) { ImageDecoder.decode(url, maxSide: side) }.value
        },
        isPlayable: { url in
            (try? await AVURLAsset(url: url).load(.isPlayable)) ?? false
        },
        pdfPageCount: { url in
            await Task.detached(priority: .userInitiated) { PDFDocument(url: url)?.pageCount ?? 0 }.value
        },
        text: { url in
            await Task.detached(priority: .userInitiated) { TextExtractor.head(of: url) }.value
        },
        waveform: { url in
            await WaveformExtractor.extract(from: url)
        }
    )
}

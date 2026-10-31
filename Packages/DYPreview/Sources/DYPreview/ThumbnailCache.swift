import AVFoundation
import CoreGraphics
import Foundation

/// A byte-bounded cache of small thumbnails for images and videos.
public actor ThumbnailCache {
    /// Decodes one thumbnail. Replaceable so tests can count calls.
    public typealias Decoder = @Sendable (URL, CGFloat) async -> CGImage?

    public static let shared = ThumbnailCache()

    private struct Key: Hashable { var url: URL; var side: Int }
    private var cache: LRUCache<Key, CGImage>
    private let decoder: Decoder

    /// Creates a cache holding at most `maxBytes` of pixels.
    public init(maxBytes: Int = 96 * 1024 * 1024, decoder: @escaping Decoder = ThumbnailCache.liveDecoder) {
        cache = LRUCache(maxCost: maxBytes)
        self.decoder = decoder
    }

    /// Number of thumbnails held.
    public var count: Int { cache.count }

    /// Returns a thumbnail whose long edge is about `side` pixels, decoding on first use. Placeholders are skipped.
    public func image(for url: URL, side: CGFloat) async -> CGImage? {
        let key = Key(url: url, side: Int(side.rounded()))
        if let hit = cache.get(key) { return hit }
        guard !DatalessGuard.isDataless(url), let image = await decoder(url, side) else { return nil }
        if Task.isCancelled { return nil }
        cache.set(key, image, cost: image.bytesPerRow * image.height)
        return image
    }

    /// Decodes images through ImageIO and videos through `AVAssetImageGenerator`.
    public static let liveDecoder: Decoder = { url, side in
        if let image = ImageDecoder.decode(url, maxSide: side) { return image }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: side, height: side)
        return try? await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image
    }
}

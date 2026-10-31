import CoreGraphics
import Foundation
import ImageIO

/// Decodes images with ImageIO at a bounded size.
public enum ImageDecoder {
    /// Decodes at most `maxSide` pixels on the long edge, or the full image when `maxSide` is 0. Nil if undecodable.
    /// Opens the file read-only. Never call this for a dataless item.
    public static func decode(_ url: URL, maxSide: CGFloat) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions),
              CGImageSourceGetCount(source) > 0 else { return nil }
        if maxSide <= 0 {
            return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

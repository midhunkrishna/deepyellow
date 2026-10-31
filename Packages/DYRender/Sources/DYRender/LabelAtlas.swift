import AppKit
import CoreText
import Foundation

/// Everything that determines how a piece of text rasterises. Used as the atlas key.
public struct TextSpec: Hashable {
    public enum Weight: Int { case regular, medium, semibold }
    public var text: String
    /// Font size in pixels.
    public var size: Float
    public var weight: Weight = .regular
    /// Tabular numerals, for sizes and counts.
    public var tabular = false
    /// Truncate with an ellipsis beyond this many pixels. Zero means never.
    public var maxWidth = 0

    public init(text: String, size: Float, weight: Weight = .regular, tabular: Bool = false, maxWidth: Int = 0) {
        self.text = text; self.size = size; self.weight = weight; self.tabular = tabular; self.maxWidth = maxWidth
    }
}

/// A rasterised label's place in the atlas and its metrics.
public struct AtlasEntry {
    /// Texel rectangle including a one pixel margin on every side.
    public var x: Int, y: Int, w: Int, h: Int
    /// Width of the text itself in pixels.
    public var textWidth: Float
    var lastUsed: Int
}

/// Rasterises text with CoreText into 8-bit coverage bitmaps.
public enum TextRasterizer {
    /// The font for a spec: SF Pro, with tabular figures where requested.
    public static func font(_ spec: TextSpec) -> NSFont {
        let weight: NSFont.Weight = [.regular, .medium, .semibold][spec.weight.rawValue]
        let size = CGFloat(spec.size)
        return spec.tabular ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    }

    /// Builds the CoreText line, slightly tracked at small sizes for legibility on dark grounds.
    static func line(_ spec: TextSpec, truncate: Bool) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [.font: font(spec), .kern: spec.size < 14 ? spec.size * 0.012 : 0]
        let string = NSAttributedString(string: spec.text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(string)
        guard truncate, spec.maxWidth > 0, CTLineGetTypographicBounds(line, nil, nil, nil) > Double(spec.maxWidth) else { return line }
        let token = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
        return CTLineCreateTruncatedLine(line, Double(spec.maxWidth), .end, token) ?? line
    }

    /// The natural width of the text in pixels, ignoring truncation.
    public static func naturalWidth(_ spec: TextSpec) -> Float {
        Float(CTLineGetTypographicBounds(line(spec, truncate: false), nil, nil, nil))
    }

    /// Draws the text white-on-clear into a coverage bitmap with a one pixel margin.
    public static func rasterize(_ spec: TextSpec) -> (pixels: [UInt8], width: Int, height: Int, textWidth: Float) {
        let line = line(spec, truncate: true)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let textWidth = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        let width = Int(ceil(textWidth)) + 2, height = Int(ceil(ascent + descent)) + 2
        var pixels = [UInt8](repeating: 0, count: width * height)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return }
            context.setAllowsFontSmoothing(false)
            context.setShouldAntialias(true)
            context.setAllowsFontSubpixelPositioning(true)
            context.textPosition = CGPoint(x: 1, y: descent + 1)
            CTLineDraw(line, context)
        }
        // CoreGraphics bitmaps are bottom-up in memory only for flipped consumers; this one is top row first already.
        return (pixels, width, height, Float(textWidth))
    }
}

/// Shelf allocator over a fixed texture, with first-fit reuse of freed gaps.
struct ShelfPacker {
    struct Row { var y: Int; var height: Int; var free: [(x: Int, w: Int)] }
    let width: Int, height: Int
    var rows: [Row] = []
    var nextY = 0

    init(width: Int, height: Int) { self.width = width; self.height = height }

    /// Finds room for a `w` by `h` block, or nil when the atlas is full.
    mutating func allocate(w: Int, h: Int) -> (x: Int, y: Int)? {
        for index in rows.indices where rows[index].height >= h && rows[index].height <= h + 8 {
            if let slot = rows[index].free.firstIndex(where: { $0.w >= w }) {
                let gap = rows[index].free[slot]
                if gap.w == w { rows[index].free.remove(at: slot) } else { rows[index].free[slot] = (gap.x + w, gap.w - w) }
                return (gap.x, rows[index].y)
            }
        }
        let rowHeight = (h + 7) / 8 * 8
        guard nextY + rowHeight <= height, w <= width else { return nil }
        rows.append(Row(y: nextY, height: rowHeight, free: w == width ? [] : [(w, width - w)]))
        nextY += rowHeight
        return (0, rows[rows.count - 1].y)
    }

    /// Returns a block to its row, merging neighbouring gaps.
    mutating func release(x: Int, y: Int, w: Int) {
        guard let index = rows.firstIndex(where: { $0.y == y }) else { return }
        var gaps = rows[index].free + [(x, w)]
        gaps.sort { $0.x < $1.x }
        var merged: [(x: Int, w: Int)] = []
        for gap in gaps {
            if let last = merged.last, last.x + last.w == gap.x { merged[merged.count - 1].w += gap.w } else { merged.append(gap) }
        }
        rows[index].free = merged
    }
}

/// A CPU-side texture atlas of rasterised labels with least-recently-used eviction.
///
/// The GPU texture is only a mirror: call `takeDirty()` and upload those regions. Safe to reuse from any canvas.
public final class LabelAtlas {
    public let width: Int, height: Int
    public private(set) var pixels: [UInt8]
    private var packer: ShelfPacker
    private var entries: [TextSpec: AtlasEntry] = [:]
    private var widths: [TextSpec: Float] = [:]
    private var dirty: [(x: Int, y: Int, w: Int, h: Int)] = []
    private var frame = 0

    /// Creates an empty atlas.
    public init(width: Int = 2048, height: Int = 2048) {
        self.width = width; self.height = height
        pixels = [UInt8](repeating: 0, count: width * height)
        packer = ShelfPacker(width: width, height: height)
    }

    /// Marks the start of a frame. Entries touched since the previous call are safe from eviction.
    public func beginFrame() { frame += 1 }

    public var entryCount: Int { entries.count }

    /// The width in pixels the text would have without truncation. Cached.
    public func naturalWidth(_ spec: TextSpec) -> Float {
        var key = spec
        key.maxWidth = 0
        if let cached = widths[key] { return cached }
        if widths.count > 20_000 { widths.removeAll() }
        let width = TextRasterizer.naturalWidth(key)
        widths[key] = width
        return width
    }

    /// The atlas entry for a spec, rasterising and placing it if needed. Nil when it cannot fit.
    public func entry(for spec: TextSpec) -> AtlasEntry? {
        if var existing = entries[spec] {
            existing.lastUsed = frame
            entries[spec] = existing
            return existing
        }
        let bitmap = TextRasterizer.rasterize(spec)
        guard let place = allocate(w: bitmap.width, h: bitmap.height) else { return nil }
        for row in 0..<bitmap.height {
            let source = row * bitmap.width, target = (place.y + row) * width + place.x
            pixels.replaceSubrange(target..<(target + bitmap.width), with: bitmap.pixels[source..<(source + bitmap.width)])
        }
        dirty.append((place.x, place.y, bitmap.width, bitmap.height))
        let created = AtlasEntry(x: place.x, y: place.y, w: bitmap.width, h: bitmap.height, textWidth: bitmap.textWidth, lastUsed: frame)
        entries[spec] = created
        return created
    }

    /// Allocates a block, evicting the least recently used labels from earlier frames when full.
    private func allocate(w: Int, h: Int) -> (x: Int, y: Int)? {
        if let place = packer.allocate(w: w, h: h) { return place }
        let victims = entries.filter { $0.value.lastUsed < frame }.sorted { $0.value.lastUsed < $1.value.lastUsed }
        var evicted = 0
        for (key, value) in victims {
            entries[key] = nil
            packer.release(x: value.x, y: value.y, w: value.w)
            evicted += 1
            if evicted % 16 == 0, let place = packer.allocate(w: w, h: h) { return place }
        }
        return packer.allocate(w: w, h: h)
    }

    /// Regions written since the last call, to mirror into the GPU texture.
    public func takeDirty() -> [(x: Int, y: Int, w: Int, h: Int)] {
        defer { dirty.removeAll(keepingCapacity: true) }
        return dirty
    }
}

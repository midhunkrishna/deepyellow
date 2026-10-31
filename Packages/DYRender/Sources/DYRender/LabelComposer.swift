import DYCore
import Foundation
import simd

/// One textured glyph-run quad: pixel rectangle, atlas UV rectangle and colour.
public struct LabelQuad {
    public var rect: SIMD4<Float>, uv: SIMD4<Float>, color: SIMD4<Float>
    /// Pivot x, pivot y and angle in radians (clockwise on screen). An angle of zero draws the quad upright.
    public var rotation: SIMD4<Float> = .zero

    /// Creates a quad, optionally rotated about a pivot.
    public init(rect: SIMD4<Float>, uv: SIMD4<Float>, color: SIMD4<Float>, rotation: SIMD4<Float> = .zero) {
        self.rect = rect; self.uv = uv; self.color = color; self.rotation = rotation
    }
}

/// How a free-standing caption lines up with its anchor.
public enum CaptionAlignment { case left, right, center }

/// Turns label requests into positioned quads using a `LabelAtlas`. At most `limit` labels per frame.
public final class LabelComposer {
    public let atlas: LabelAtlas
    public var limit = 300
    /// Backing rectangles (x, y, width, height, alpha) for captions that need a solid ground, filled by `compose`.
    public private(set) var plates: [SIMD4<Float>] = []
    private static let ladder: [Float] = [10, 11, 12, 13, 15, 17, 20, 24, 28, 34, 42]

    /// Creates a composer drawing from `atlas`.
    public init(atlas: LabelAtlas) { self.atlas = atlas }

    /// Resolves requests for `lens` into quads, largest tiles first.
    public func compose(_ requests: [LabelRequest], lens: TreeLens, metric: Metric, scale: Float) -> [LabelQuad] {
        atlas.beginFrame()
        plates.removeAll(keepingCapacity: true)
        var quads: [LabelQuad] = []
        let ordered = requests.sorted { $0.priority > $1.priority }
        var used = 0
        for request in ordered where used < limit {
            let before = quads.count
            switch request.role {
            case .tile: placeTile(request, lens, metric, scale, &quads)
            case .header: placeHeader(request, lens, metric, scale, &quads)
            case .dust: placeDust(request, metric, scale, &quads)
            }
            if quads.count > before { used += 1 }
        }
        return quads
    }

    /// The largest ladder size not exceeding `target` pixels.
    private func snap(_ target: Float, scale: Float) -> Float {
        let points = target / scale
        return (Self.ladder.last { $0 <= points } ?? Self.ladder[0]) * scale
    }

    /// Places `spec`, truncating to `available` pixels. Returns the width used, or nil if it cannot fit.
    private func place(_ spec: TextSpec, x: Float, y: Float, available: Float, color: SIMD4<Float>, rightAlign: Bool = false,
                       _ quads: inout [LabelQuad]) -> Float? {
        guard available >= spec.size * 2.2 else { return nil }
        var spec = spec
        let natural = atlas.naturalWidth(spec)
        if natural > available { spec.maxWidth = Int(available / 8) * 8 }
        guard let entry = atlas.entry(for: spec) else { return nil }
        let left = rightAlign ? x - entry.textWidth : x
        let aw = Float(atlas.width), ah = Float(atlas.height)
        quads.append(LabelQuad(rect: SIMD4((left - 1).rounded(), (y - 1).rounded(), Float(entry.w), Float(entry.h)),
                               uv: SIMD4(Float(entry.x) / aw, Float(entry.y) / ah, Float(entry.x + entry.w) / aw, Float(entry.y + entry.h) / ah),
                               color: color))
        return entry.textWidth
    }

    private func textColor(_ request: LabelRequest, strength: Float) -> SIMD4<Float> {
        let base: SIMD3<Float> = request.darkText ? SIMD3(0.08, 0.06, 0.03) : Palette.textPrimary
        return SIMD4(base, request.alpha * strength)
    }

    /// Name and size at the top left of a tile, with the size set in tabular numerals underneath.
    private func placeTile(_ request: LabelRequest, _ lens: TreeLens, _ metric: Metric, _ scale: Float, _ quads: inout [LabelQuad]) {
        let r = request.rect
        let size = snap(0.034 * (r.z * r.w).squareRoot() + 4 * scale, scale: scale)
        let pad = max(6 * scale, size * 0.62)
        let available = r.z - 2 * pad
        let nameHeight = size * 1.28
        guard r.w >= nameHeight + 2 * pad - pad * 0.3 else { return }
        let name = lens.tree.name(request.node)
        _ = place(TextSpec(text: name, size: size, weight: .medium), x: r.x + pad, y: r.y + pad, available: available,
                  color: textColor(request, strength: 0.97), &quads)
        let detailSize = (size * 0.82).rounded()
        guard r.w >= nameHeight + detailSize * 1.3 + 2 * pad else { return }
        let detail = detailText(request.node, lens, metric, long: true)
        var spec = TextSpec(text: detail, size: detailSize, weight: .regular, tabular: true)
        if atlas.naturalWidth(spec) > available { spec.text = detailText(request.node, lens, metric, long: false) }
        _ = place(spec, x: r.x + pad, y: r.y + pad + nameHeight, available: available, color: textColor(request, strength: 0.68), &quads)
    }

    /// Directory name on the left and size on the right, centred in the header band.
    private func placeHeader(_ request: LabelRequest, _ lens: TreeLens, _ metric: Metric, _ scale: Float, _ quads: inout [LabelQuad]) {
        let r = request.rect
        let size = min(snap(request.band * 0.46, scale: scale), 17 * scale)
        let pad = max(5 * scale, request.band * 0.4)
        let top = r.y + (request.band - size * 1.28) / 2 + r.w * 0 + request.band * 0.1
        let detail = detailText(request.node, lens, metric, long: false)
        let detailSpec = TextSpec(text: detail, size: (size * 0.92).rounded(), weight: .regular, tabular: true)
        let detailWidth = atlas.naturalWidth(detailSpec)
        let showDetail = r.z > detailWidth + 120 * scale
        let nameRoom = r.z - 2 * pad - (showDetail ? detailWidth + pad : 0)
        _ = place(TextSpec(text: lens.tree.name(request.node), size: size, weight: .semibold), x: r.x + pad, y: top, available: nameRoom,
                  color: SIMD4(Palette.textSecondary, request.alpha * 0.95), &quads)
        if showDetail {
            _ = place(detailSpec, x: r.x + r.z - pad, y: top, available: detailWidth + 4, color: SIMD4(Palette.textMuted, request.alpha * 1.0),
                      rightAlign: true, &quads)
        }
    }

    /// The centred "12,431 small files · 3.1 GB" caption on a dust tile.
    private func placeDust(_ request: LabelRequest, _ metric: Metric, _ scale: Float, _ quads: inout [LabelQuad]) {
        let r = request.rect
        let size = snap(0.022 * (r.z * r.w).squareRoot() + 6 * scale, scale: scale)
        let text = "\(Format.count(request.dustFiles)) small \(request.dustFiles == 1 ? "file" : "files") · \(Format.bytes(request.dustBytes))"
        let spec = TextSpec(text: text, size: min(size, 20 * scale), weight: .regular, tabular: true)
        let width = atlas.naturalWidth(spec)
        guard r.z - 16 * scale >= width else { return }
        let x = r.x + (r.z - width) / 2, y = r.y + (r.w - spec.size * 1.28) / 2
        let before = quads.count
        guard place(spec, x: x, y: y, available: r.z - 16 * scale, color: SIMD4(Palette.textPrimary, request.alpha), &quads) != nil else { return }
        // A dark plate under solid text keeps the caption readable over the motes.
        let used = quads[before].rect
        let padX = 9 * scale, padY = 4 * scale
        plates.append(SIMD4(used.x - padX, used.y - padY + scale, used.z + 2 * padX, used.w + 2 * padY - 2 * scale))
        quads.swapAt(before, quads.count - 1)
    }

    /// Places a free-standing caption at `x`, `y`, aligned left, right or centred on `x`. Returns the quad and the text width used.
    public func caption(_ spec: TextSpec, x: Float, y: Float, available: Float, color: SIMD4<Float>,
                        align: CaptionAlignment = .left) -> (quad: LabelQuad, width: Float)? {
        var spec = spec
        let natural = atlas.naturalWidth(spec)
        if natural > available { spec.maxWidth = Int(available / 8) * 8 }
        guard spec.maxWidth > 0 || natural <= available, let entry = atlas.entry(for: spec) else { return nil }
        let left: Float = align == .left ? x : (align == .right ? x - entry.textWidth : x - entry.textWidth / 2)
        let aw = Float(atlas.width), ah = Float(atlas.height)
        let quad = LabelQuad(rect: SIMD4((left - 1).rounded(), (y - 1).rounded(), Float(entry.w), Float(entry.h)),
                             uv: SIMD4(Float(entry.x) / aw, Float(entry.y) / ah, Float(entry.x + entry.w) / aw, Float(entry.y + entry.h) / ah),
                             color: color)
        return (quad, entry.textWidth)
    }

    /// Size text for a node. The long form adds the file count for directories.
    private func detailText(_ node: NodeID, _ lens: TreeLens, _ metric: Metric, long: Bool) -> String {
        let bytes = Format.bytes(lens.size[Int(node)])
        let files = lens.files[Int(node)]
        let isDirectory = lens.tree.isDirectory(node)
        switch metric {
        case .bytes: return long && isDirectory && files > 1 ? "\(bytes) · \(Format.count(files)) files" : bytes
        case .files: return long && isDirectory ? "\(Format.count(files)) files · \(bytes)" : (files == 1 && !isDirectory ? bytes : "\(Format.count(files)) files")
        }
    }
}

import DYCore
import SwiftUI

/// Slice-and-dice layout of weights into a rectangle.
public enum DirectoryLayout {
    /// Returns one rect per weight, with area proportional to the weight. Alternates split direction by depth and
    /// places the largest first. Rects tile `bounds` exactly.
    public static func rects(weights: [UInt64], in bounds: CGRect) -> [CGRect] {
        var out = [CGRect](repeating: .zero, count: weights.count)
        split(Array(weights.indices), weights, bounds, horizontal: bounds.width >= bounds.height, into: &out)
        return out
    }

    /// Recursively splits the first item off the rest.
    private static func split(_ ids: [Int], _ weights: [UInt64], _ rect: CGRect, horizontal: Bool, into out: inout [CGRect]) {
        guard let first = ids.first else { return }
        if ids.count == 1 { out[first] = rect; return }
        let total = ids.reduce(0.0) { $0 + Double(max(weights[$1], 1)) }
        let share = CGFloat(Double(max(weights[first], 1)) / total)
        let head: CGRect, rest: CGRect
        if horizontal {
            head = CGRect(x: rect.minX, y: rect.minY, width: rect.width * share, height: rect.height)
            rest = CGRect(x: head.maxX, y: rect.minY, width: rect.width - head.width, height: rect.height)
        } else {
            head = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * share)
            rest = CGRect(x: rect.minX, y: head.maxY, width: rect.width, height: rect.height - head.height)
        }
        out[first] = head
        split(Array(ids.dropFirst()), weights, rest, horizontal: !horizontal, into: &out)
    }
}

/// Largest children as tiles sized by share, with thumbnails for images and videos.
struct DirectoryView: View {
    let children: [PreviewChild]

    var body: some View {
        GeometryReader { geo in
            let sorted = children.sorted { $0.size > $1.size }
            let rects = DirectoryLayout.rects(weights: sorted.map(\.size), in: CGRect(origin: .zero, size: geo.size))
            ZStack(alignment: .topLeading) {
                ForEach(sorted.indices, id: \.self) { index in
                    ChildTile(child: sorted[index])
                        .frame(width: max(rects[index].width - 2, 0), height: max(rects[index].height - 2, 0))
                        .offset(x: rects[index].minX + 1, y: rects[index].minY + 1)
                }
            }
        }
        .padding(8)
    }
}

/// One tile: kind colour, a lazily loaded thumbnail, and a slim label.
struct ChildTile: View {
    let child: PreviewChild
    @State private var thumbnail: CGImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Theme.color(Palette.kind(child.kind)).opacity(0.35)
            if let thumbnail { Image(decorative: thumbnail, scale: 1).resizable().aspectRatio(contentMode: .fill) }
            Text("\(child.name)  \(Format.bytes(child.size))")
                .font(.system(size: 10).monospacedDigit()).lineLimit(1).padding(4)
                .foregroundStyle(Theme.primary).shadow(radius: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .task(id: child.url) {
            guard !child.isDirectory, child.kind == .image || child.kind == .video else { return }
            thumbnail = await ThumbnailCache.shared.image(for: child.url, side: 320)
        }
    }
}

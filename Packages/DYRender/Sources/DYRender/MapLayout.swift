import DYCore
import Foundation

/// A directory's visible children, largest first, with running totals so any tail can be summed in O(1).
public struct ChildList {
    public var ids: [NodeID] = []
    /// `count + 1` entries; entry `i` is the sum of the metric over `ids[..<i]`.
    public var valuePrefix: [UInt64] = [0]
    public var bytesPrefix: [UInt64] = [0]
    public var filesPrefix: [UInt64] = [0]
    public var count: Int { ids.count }
    public init() {}
}

/// What a dust tile stands for: every child of a directory from `start` onward.
public struct TailInfo: Equatable {
    public var start: Int, count: Int
    public var bytes: UInt64, files: UInt64
    public var kind: UInt8
    /// Metric value of the first child inside the tail, which is the largest piece it would resolve into.
    public var firstValue: UInt64
}

/// One placed rectangle: a node, or the dust tile for a directory's remaining children.
public struct LayoutTile {
    public var node: NodeID
    public var rect: WRect
    public var value: UInt64
    public var tail: TailInfo?
    public var isTail: Bool { tail != nil }
}

/// The placed children of one container: a directory, or the remainder inside a dust tile.
public struct ContainerLayout {
    public var rect: WRect
    public var tiles: [LayoutTile]
}

/// Lazy, world-space treemap layout over a `TreeLens`.
///
/// Each directory places its children only when asked, inside its own rectangle, so zooming never reflows anything.
/// A directory places its large children plus one dust tile for the rest; asking for the dust tile's content places
/// the next chunk the same way, so tiny files resolve at any zoom.
public final class MapLayout {
    public static let targetAspect = 1.5
    /// Fraction of a directory's shorter side kept as padding and as header band.
    public static let paddingFraction = 0.010, headerFraction = 0.042
    private static let shareFloor: UInt64 = 500
    private static let firstChunk = (minimum: 12, capacity: 48)
    private static let laterChunk = (minimum: 128, capacity: 512)

    public let lens: TreeLens
    public let metric: Metric
    public let worldRect: WRect
    private let dominantKind: [UInt8]
    private var childLists: [NodeID: ChildList] = [:]
    private var containers: [Int: ContainerLayout] = [:]

    /// Creates a layout whose root rectangle is `worldAspect` wide for every unit of height.
    ///
    /// `dominantKind` colours dust tiles; when empty the children's own file kinds are used.
    public init(lens: TreeLens, metric: Metric, worldAspect: Double, dominantKind: [UInt8] = []) {
        self.lens = lens
        self.metric = metric
        self.worldRect = WRect(0, 0, worldAspect, 1)
        self.dominantKind = dominantKind
    }

    /// The visible children of `node`, sorted by the metric.
    public func children(of node: NodeID) -> ChildList {
        if let cached = childLists[node] { return cached }
        var list = ChildList()
        list.ids = lens.visibleChildren(of: node, metric: metric)
        list.valuePrefix.reserveCapacity(list.ids.count + 1)
        list.bytesPrefix.reserveCapacity(list.ids.count + 1)
        list.filesPrefix.reserveCapacity(list.ids.count + 1)
        for id in list.ids {
            list.valuePrefix.append(list.valuePrefix.last! &+ lens.value(id, metric))
            list.bytesPrefix.append(list.bytesPrefix.last! &+ lens.size[Int(id)])
            list.filesPrefix.append(list.filesPrefix.last! &+ UInt64(lens.files[Int(id)]))
        }
        childLists[node] = list
        return list
    }

    /// Places the chunk of `parent`'s children starting at index `start` inside `rect`, plus a dust tile for the rest.
    public func layout(parent: NodeID, start: Int, in rect: WRect) -> ContainerLayout {
        let key = Int(parent) << 32 | start
        if let cached = containers[key], cached.rect == rect { return cached }
        let list = children(of: parent)
        guard start < list.count else { return ContainerLayout(rect: rect, tiles: []) }
        let end = chunkEnd(list, start: start)
        var tiles: [LayoutTile] = (start..<end).map {
            LayoutTile(node: list.ids[$0], rect: rect, value: list.valuePrefix[$0 + 1] - list.valuePrefix[$0], tail: nil)
        }
        if end < list.count {
            let tail = tailInfo(list, from: end)
            let value = list.valuePrefix[list.count] - list.valuePrefix[end]
            let slot = tiles.firstIndex { $0.value < value } ?? tiles.count
            tiles.insert(LayoutTile(node: parent, rect: rect, value: value, tail: tail), at: slot)
        }
        let rects = Squarify.layout(values: tiles.map { Double($0.value) }, in: rect, targetAspect: Self.targetAspect)
        for index in tiles.indices { tiles[index].rect = rects[index] }
        let result = ContainerLayout(rect: rect, tiles: tiles)
        if containers.count > 400_000 { containers.removeAll(keepingCapacity: true) }
        containers[key] = result
        return result
    }

    /// The end of the chunk that gets its own tiles; everything after it becomes dust.
    private func chunkEnd(_ list: ChildList, start: Int) -> Int {
        let sizes = start == 0 ? Self.firstChunk : Self.laterChunk
        let total = list.valuePrefix[list.count] - list.valuePrefix[start]
        var end = start
        while end < list.count && end - start < sizes.capacity {
            let value = list.valuePrefix[end + 1] - list.valuePrefix[end]
            if end - start >= sizes.minimum && value &* Self.shareFloor < total { break }
            end += 1
        }
        return list.count - end <= 2 ? list.count : end
    }

    /// Summarises the children from `from` onward for their dust tile.
    private func tailInfo(_ list: ChildList, from: Int) -> TailInfo {
        let count = list.count - from
        var kindBytes = [UInt64](repeating: 0, count: FileKind.allCases.count)
        let step = max(1, count / 64)
        for index in stride(from: from, to: list.count, by: step) {
            let id = list.ids[index]
            let kind = dominantKind.isEmpty ? lens.tree.kind(id).rawValue : dominantKind[Int(id)]
            kindBytes[Int(min(kind, 7))] &+= list.valuePrefix[index + 1] - list.valuePrefix[index]
        }
        let best = kindBytes.indices.max { kindBytes[$0] < kindBytes[$1] } ?? 7
        return TailInfo(start: from, count: count, bytes: list.bytesPrefix[list.count] - list.bytesPrefix[from],
                        files: list.filesPrefix[list.count] - list.filesPrefix[from], kind: UInt8(best),
                        firstValue: list.valuePrefix[from + 1] - list.valuePrefix[from])
    }

    /// Whether a directory is a pass-through for one dominant child, which gets a slim header so chains like
    /// `/` > `Users` > `demo` read as a breadcrumb instead of eating the map.
    public func isChain(_ node: NodeID) -> Bool {
        let list = children(of: node)
        guard list.count > 0 else { return false }
        return list.count == 1 || (list.valuePrefix[1] &* 50 >= list.valuePrefix[list.count] &* 49)
    }

    /// The area inside a directory's rectangle that holds its children, after padding and the header band.
    public func contentRect(of rect: WRect, slim: Bool = false) -> WRect {
        let side = rect.minSide
        let pad = side * (slim ? 0.0035 : Self.paddingFraction)
        let header = headerHeight(of: rect, slim: slim)
        return WRect(rect.x + pad, rect.y + pad + header, max(0, rect.w - 2 * pad), max(0, rect.h - 2 * pad - header))
    }

    /// The world-space height reserved for a directory's header.
    public func headerHeight(of rect: WRect, slim: Bool = false) -> Double { rect.minSide * (slim ? 0.022 : Self.headerFraction) }

    /// The world rectangle of `node`, or nil if the lens hides it.
    public func rect(of node: NodeID) -> WRect? {
        if node == 0 { return lens.included[0] ? worldRect : nil }
        guard lens.included[Int(node)], lens.value(node, metric) > 0 else { return nil }
        var rect = worldRect
        let chain = lens.tree.ancestry(node)
        for step in 0..<(chain.count - 1) {
            guard let found = locate(chain[step + 1], inside: chain[step], rect: rect) else { return nil }
            rect = found
        }
        return rect
    }

    /// Finds `child`'s rectangle by walking `parent`'s chunk chain.
    private func locate(_ child: NodeID, inside parent: NodeID, rect: WRect) -> WRect? {
        var area = contentRect(of: rect, slim: isChain(parent))
        var start = 0
        while true {
            let container = layout(parent: parent, start: start, in: area)
            if let hit = container.tiles.first(where: { $0.node == child && !$0.isTail }) { return hit.rect }
            guard let tail = container.tiles.first(where: { $0.isTail }), let info = tail.tail else { return nil }
            area = tail.rect
            start = info.start
        }
    }
}

import DYCore
import Foundation

/// Files in one size range.
public struct SpectrumBin: Sendable {
    /// Inclusive lower bound in bytes.
    public var lower: UInt64
    /// Exclusive upper bound in bytes.
    public var upper: UInt64
    public var count: UInt64
    public var bytes: UInt64
    /// Indexed by `FileKind` raw value.
    public var bytesByKind: [UInt64]
    public var countByKind: [UInt64]
}

/// The shape of a subtree's file sizes.
public struct SpectrumResult: Sendable {
    /// Ranges 1-2-5 per decade, from the smallest to the largest occupied one. A leading `0..<1` bin holds empty files.
    public var bins: [SpectrumBin]
    /// Cumulative share of bytes against share of files, largest file first, at most 512 points.
    public var curve: [(itemShare: Double, byteShare: Double)]
    /// How many of the largest files hold at least this share of all bytes.
    public var itemsForShare: @Sendable (Double) -> Int
    public var totalFiles: UInt64
    public var totalBytes: UInt64
}

/// Computes size distributions.
public enum SpectrumEngine {
    private static let powersOfTen: [UInt64] = (0...19).map { exponent in (0..<exponent).reduce(UInt64(1)) { value, _ in value * 10 } }
    private static let kindCount = FileKind.allCases.count

    /// Builds the spectrum of the visible files beneath `under`.
    public static func compute(lens: TreeLens, under: NodeID) -> SpectrumResult {
        let inside = Subtree.membership(of: under, in: lens.tree)
        let columns = lens.tree.columns
        let slots = 64, kinds = kindCount
        var counts = [UInt64](repeating: 0, count: slots), bytes = [UInt64](repeating: 0, count: slots)
        var kindCounts = [UInt64](repeating: 0, count: slots * kinds), kindBytes = [UInt64](repeating: 0, count: slots * kinds)
        var sizes: [UInt64] = []
        var totalBytes: UInt64 = 0
        for index in Int(max(under, 0))..<lens.tree.count where inside[index] && Subtree.isVisibleFile(index, lens: lens) {
            let size = lens.size[index]
            let slot = binIndex(size)
            let cell = slot * kinds + Int(columns.kind[index])
            counts[slot] += 1
            bytes[slot] &+= size
            kindCounts[cell] += 1
            kindBytes[cell] &+= size
            sizes.append(size)
            totalBytes &+= size
        }
        var bins: [SpectrumBin] = []
        if let first = counts.firstIndex(where: { $0 > 0 }), let last = counts.lastIndex(where: { $0 > 0 }) {
            for slot in first...last {
                var bin = emptyBin(slot)
                bin.count = counts[slot]
                bin.bytes = bytes[slot]
                bin.countByKind = Array(kindCounts[(slot * kinds)..<((slot + 1) * kinds)])
                bin.bytesByKind = Array(kindBytes[(slot * kinds)..<((slot + 1) * kinds)])
                bins.append(bin)
            }
        }
        sizes.sort(by: >)
        let curve = Curve(sizes: sizes, totalBytes: totalBytes)
        return SpectrumResult(bins: bins, curve: curve.points, itemsForShare: curve.itemsForShare,
                              totalFiles: UInt64(sizes.count), totalBytes: totalBytes)
    }

    /// The slot for a size: 0 for empty files, then three per decade.
    static func binIndex(_ size: UInt64) -> Int {
        guard size > 0 else { return 0 }
        var decade = ((63 - size.leadingZeroBitCount) * 1233) >> 12
        if decade > 19 { decade = 19 }
        if size < powersOfTen[decade] { decade -= 1 }
        if decade < 19, size >= powersOfTen[decade + 1] { decade += 1 }
        let mantissa = size / powersOfTen[decade]
        return 1 + decade * 3 + (mantissa >= 5 ? 2 : mantissa >= 2 ? 1 : 0)
    }

    /// An empty bin with the bounds of `slot`.
    private static func emptyBin(_ slot: Int) -> SpectrumBin {
        let zeros = [UInt64](repeating: 0, count: kindCount)
        guard slot > 0 else { return SpectrumBin(lower: 0, upper: 1, count: 0, bytes: 0, bytesByKind: zeros, countByKind: zeros) }
        return SpectrumBin(lower: bound(slot - 1), upper: bound(slot), count: 0, bytes: 0, bytesByKind: zeros, countByKind: zeros)
    }

    /// The lower bound of the slot after `index`: 1, 2, 5, 10, 20, 50, ...
    private static func bound(_ index: Int) -> UInt64 {
        let decade = index / 3
        guard decade <= 19 else { return UInt64.max }
        let (product, overflow) = powersOfTen[decade].multipliedReportingOverflow(by: [1, 2, 5][index % 3])
        return overflow ? UInt64.max : product
    }

    /// Cumulative statistics over files sorted largest first.
    private struct Curve {
        var points: [(itemShare: Double, byteShare: Double)] = []
        var itemsForShare: @Sendable (Double) -> Int = { _ in 0 }

        /// Samples the cumulative sum at selected ranks and builds the lookup.
        init(sizes: [UInt64], totalBytes: UInt64) {
            let count = sizes.count
            guard count > 0, totalBytes > 0 else {
                if count > 0 { points = [(1, 1)] }
                return
            }
            let curveRanks = Curve.geometricRanks(count: count, points: 512)
            let anchorRanks = Curve.anchorRanks(count: count)
            let ranks = Array(Set(curveRanks + anchorRanks)).sorted()
            var sums: [Int: UInt64] = [:]
            var running: UInt64 = 0, next = 0
            for (offset, size) in sizes.enumerated() {
                running &+= size
                if offset + 1 == ranks[next] {
                    sums[ranks[next]] = running
                    next += 1
                    if next == ranks.count { break }
                }
            }
            let total = Double(totalBytes)
            points = curveRanks.map { (Double($0) / Double(count), Double(sums[$0] ?? 0) / total) }
            let anchors = anchorRanks.map { (rank: $0, sum: sums[$0] ?? 0) }
            itemsForShare = { share in
                Curve.lookup(share: share, anchors: anchors, totalBytes: totalBytes)
            }
        }

        /// At most `points` ranks, dense at the top, always ending at `count`.
        static func geometricRanks(count: Int, points: Int) -> [Int] {
            if count <= points { return Array(1...count) }
            var ranks = Set<Int>([1, count])
            for step in 0..<points { ranks.insert(max(1, min(count, Int(pow(Double(count), Double(step) / Double(points - 1)).rounded())))) }
            return ranks.sorted().suffix(points).sorted()
        }

        /// Exact for the first 4096 ranks, then 0.5 percent steps.
        static func anchorRanks(count: Int) -> [Int] {
            var ranks = Array(1...min(count, 4096))
            var rank = 4096
            while rank < count {
                rank = max(rank + 1, Int(Double(rank) * 1.005))
                ranks.append(min(rank, count))
            }
            return ranks
        }

        /// Smallest number of files whose bytes reach `share`, interpolating between anchors.
        static func lookup(share: Double, anchors: [(rank: Int, sum: UInt64)], totalBytes: UInt64) -> Int {
            guard share > 0, let last = anchors.last else { return 0 }
            let target = min(share, 1) * Double(totalBytes)
            if target >= Double(last.sum) { return last.rank }
            var low = 0, high = anchors.count - 1
            while low < high {
                let middle = (low + high) / 2
                if Double(anchors[middle].sum) >= target { high = middle } else { low = middle + 1 }
            }
            guard low > 0 else { return anchors[0].rank }
            let before = anchors[low - 1], after = anchors[low]
            let fraction = (target - Double(before.sum)) / max(Double(after.sum - before.sum), 1)
            return before.rank + max(1, Int((fraction * Double(after.rank - before.rank)).rounded(.up)))
        }
    }
}

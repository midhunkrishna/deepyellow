import Foundation

/// Treemap row packing that targets a preferred tile aspect instead of squares.
public enum Squarify {
    /// Splits `rect` into one rectangle per value, in input order, with areas proportional to the values.
    ///
    /// Values should be sorted descending for the best ratios. The rectangles tile `rect` exactly.
    public static func layout(values: [Double], in rect: WRect, targetAspect: Double = 1.5) -> [WRect] {
        let count = values.count
        guard count > 0 else { return [] }
        if count == 1 { return [rect] }
        var result = [WRect](repeating: WRect(rect.x, rect.y, 0, 0), count: count)
        var remaining = rect
        var remainingTotal = values.reduce(0, +)
        guard remainingTotal > 0 else { return result }
        var index = 0
        while index < count {
            let end = rowEnd(values, from: index, remaining: remaining, remainingTotal: remainingTotal, targetAspect: targetAspect)
            let rowSum = values[index..<end].reduce(0, +)
            let isLast = end == count
            place(row: index..<end, values: values, rowSum: rowSum, in: &remaining, remainingTotal: remainingTotal, exact: isLast, into: &result)
            remainingTotal -= rowSum
            index = end
        }
        return result
    }

    /// Chooses how many items join the row starting at `from`, stopping when adding another worsens the worst aspect.
    private static func rowEnd(_ values: [Double], from: Int, remaining: WRect, remainingTotal: Double, targetAspect: Double) -> Int {
        let wide = remaining.w >= remaining.h
        let side = wide ? remaining.h : remaining.w
        let areaPerValue = remaining.area / remainingTotal
        var rowSum = 0.0, best = Double.infinity, end = from
        while end < values.count {
            rowSum += values[end]
            let score = worstScore(values[from...end], rowSum: rowSum, side: side, areaPerValue: areaPerValue, wide: wide, targetAspect: targetAspect)
            if score > best && end > from { rowSum -= values[end]; break }
            best = score
            end += 1
        }
        return end
    }

    /// The largest log-distance from the target aspect among a candidate row's tiles.
    private static func worstScore(_ row: ArraySlice<Double>, rowSum: Double, side: Double, areaPerValue: Double,
                                   wide: Bool, targetAspect: Double) -> Double {
        let thickness = rowSum * areaPerValue / side
        var worst = 0.0
        for value in row {
            let length = max(value * areaPerValue / max(thickness, 1e-300), 1e-300)
            let aspect = wide ? thickness / length : length / max(thickness, 1e-300)
            worst = max(worst, abs(log(max(aspect, 1e-300) / targetAspect)))
        }
        return worst
    }

    /// Lays one row along the shorter side of `remaining`, then shrinks `remaining` by the row's thickness.
    private static func place(row: Range<Int>, values: [Double], rowSum: Double, in remaining: inout WRect,
                              remainingTotal: Double, exact: Bool, into result: inout [WRect]) {
        let wide = remaining.w >= remaining.h
        let side = wide ? remaining.h : remaining.w
        let full = wide ? remaining.w : remaining.h
        let thickness = exact ? full : min(full, rowSum / remainingTotal * remaining.area / side)
        var cursor = wide ? remaining.y : remaining.x
        let limit = wide ? remaining.maxY : remaining.maxX
        for item in row {
            let length = item == row.upperBound - 1 ? limit - cursor : values[item] / rowSum * side
            result[item] = wide ? WRect(remaining.x, cursor, thickness, length) : WRect(cursor, remaining.y, length, thickness)
            cursor += length
        }
        if wide { remaining.x += thickness; remaining.w -= thickness } else { remaining.y += thickness; remaining.h -= thickness }
    }
}

import DYAnalysis
import DYCore
import SwiftUI

/// What one histogram measures.
enum SpectrumSeries {
    case count, bytes

    /// The bin's total for this series.
    func value(_ bin: SpectrumBin) -> UInt64 { self == .count ? bin.count : bin.bytes }

    /// The bin's total for one kind.
    func value(_ bin: SpectrumBin, kind: FileKind) -> UInt64 {
        self == .count ? bin.countByKind[Int(kind.rawValue)] : bin.bytesByKind[Int(kind.rawValue)]
    }

    /// The label above a column.
    func label(_ value: UInt64) -> String { self == .count ? SpectrumModel.countLabel(value) : Format.bytes(value) }
}

/// One histogram: size ranges across, stacked by kind. Each column is a button that writes its range into the query.
struct SpectrumHistogram: View {
    let title: String
    let result: SpectrumResult
    let series: SpectrumSeries
    let activeQuery: String
    let onSelect: (SpectrumBin) -> Void
    private let barHeight: CGFloat = 200

    var body: some View {
        let bins = result.bins
        let peak = max(bins.map { series.value($0) }.max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.textSecondary)
            GeometryReader { proxy in
                let width = proxy.size.width / CGFloat(max(bins.count, 1))
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(Array(bins.enumerated()), id: \.offset) { _, bin in
                        column(bin, peak: peak, showsValue: width >= 34 || series.value(bin) == peak)
                            .frame(width: width)
                    }
                }
            }
            .frame(height: barHeight + 18)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
            axisLabels(bins)
        }
    }

    /// One column: the value above a stack of kind segments.
    private func column(_ bin: SpectrumBin, peak: UInt64, showsValue: Bool) -> some View {
        let value = series.value(bin)
        let height = value == 0 ? 0 : max(CGFloat(value) / CGFloat(peak) * barHeight, 2)
        let isActive = activeQuery == SpectrumModel.query(activeQuery, selecting: bin)
        return Button { onSelect(bin) } label: {
            VStack(spacing: 3) {
                Spacer(minLength: 0)
                Text(showsValue && value > 0 ? series.label(value) : " ")
                    .font(Theme.number(size: 10)).foregroundStyle(Theme.textSecondary).lineLimit(1).fixedSize()
                    .frame(width: 0, alignment: .center).frame(maxWidth: .infinity)
                VStack(spacing: 0) {
                    ForEach(FileKind.allCases.reversed(), id: \.rawValue) { kind in
                        let part = series.value(bin, kind: kind)
                        if part > 0 {
                            Theme.kind(kind).frame(height: max(height * CGFloat(part) / CGFloat(max(value, 1)), 1))
                        }
                    }
                }
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .padding(.horizontal, 1.5)
            }
            .frame(maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 5).fill(isActive ? Theme.surfaceRaised : .clear))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.accent, lineWidth: isActive ? 1 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(SpectrumModel.rangeLabel(bin)): \(series.label(value))")
    }

    /// Size labels under the columns, on the first bin of each decade so they never collide.
    private func axisLabels(_ bins: [SpectrumBin]) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width / CGFloat(max(bins.count, 1))
            HStack(spacing: 0) {
                ForEach(Array(bins.enumerated()), id: \.offset) { _, bin in
                    Text(isDecade(bin) ? SpectrumModel.columnLabel(bin) : "")
                        .font(Theme.number(size: 10.5)).foregroundStyle(Theme.textMuted)
                        .fixedSize().frame(width: width)
                }
            }
        }
        .frame(height: 14)
    }

    /// Whether a bin starts at 0 or a power of ten.
    private func isDecade(_ bin: SpectrumBin) -> Bool {
        if bin.upper == 1 { return true }
        var value = bin.lower
        while value >= 10, value % 10 == 0 { value /= 10 }
        return value == 1
    }
}

/// The cumulative curve: how few of the largest files hold most of the bytes. The file axis is logarithmic and labelled.
struct SpectrumCurve: View {
    let result: SpectrumResult
    private let left: CGFloat = 40, bottom: CGFloat = 38, top: CGFloat = 8, right: CGFloat = 12

    var body: some View {
        let total = Double(max(result.totalFiles, 10))
        let decades = max(Int(ceil(log10(total))), 1)
        let share80 = result.itemsForShare(0.8)
        VStack(alignment: .leading, spacing: 8) {
            Text("HOW CONCENTRATED IT IS").font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.textSecondary)
            Canvas { context, size in
                draw(&context, size: size, decades: decades, share80: share80)
            }
            .frame(height: 242)
            .accessibilityLabel("The top \(Format.count(share80)) files hold 80 percent of the bytes. File axis is logarithmic.")
        }
    }

    /// Draws grid, axes, the curve and the 80% marker.
    private func draw(_ context: inout GraphicsContext, size: CGSize, decades: Int, share80: Int) {
        let plot = CGRect(x: left, y: top, width: size.width - left - right, height: size.height - top - bottom)
        func x(_ rank: Double) -> CGFloat { plot.minX + CGFloat(log10(max(rank, 1)) / Double(decades)) * plot.width }
        func y(_ share: Double) -> CGFloat { plot.maxY - CGFloat(share) * plot.height }
        let label = Font.system(size: 10.5).monospacedDigit()
        for decade in 0...decades {
            let rank = pow(10, Double(decade))
            var line = Path()
            line.move(to: CGPoint(x: x(rank), y: plot.minY)); line.addLine(to: CGPoint(x: x(rank), y: plot.maxY))
            context.stroke(line, with: .color(Theme.hairline.opacity(0.7)), lineWidth: 1)
            context.draw(Text(Format.compactCount(UInt64(rank))).font(label).foregroundColor(Theme.textMuted),
                         at: CGPoint(x: x(rank), y: plot.maxY + 12), anchor: .center)
        }
        for share in [0.0, 0.5, 0.8, 1.0] {
            var line = Path()
            line.move(to: CGPoint(x: plot.minX, y: y(share))); line.addLine(to: CGPoint(x: plot.maxX, y: y(share)))
            context.stroke(line, with: .color(Theme.hairline.opacity(share == 0 ? 1 : 0.5)), lineWidth: 1)
            context.draw(Text("\(Int(share * 100))%").font(label).foregroundColor(Theme.textMuted),
                         at: CGPoint(x: plot.minX - 6, y: y(share)), anchor: .trailing)
        }
        context.draw(Text("Files, largest first (log scale)").font(.system(size: 10.5)).foregroundColor(Theme.textSecondary),
                     at: CGPoint(x: plot.midX, y: size.height - 6), anchor: .bottom)
        var curve = Path()
        curve.move(to: CGPoint(x: x(1), y: y(0)))
        for point in result.curve { curve.addLine(to: CGPoint(x: x(point.itemShare * Double(result.totalFiles)), y: y(point.byteShare))) }
        context.stroke(curve, with: .color(Theme.textPrimary), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        let mark = CGPoint(x: x(Double(share80)), y: y(0.8))
        context.fill(Path(ellipseIn: CGRect(x: mark.x - 5, y: mark.y - 5, width: 10, height: 10)), with: .color(Theme.accent))
        context.stroke(Path(ellipseIn: CGRect(x: mark.x - 5, y: mark.y - 5, width: 10, height: 10)), with: .color(Theme.background), lineWidth: 2)
        let words = "The top \(Format.count(share80)) files hold 80%"
        let roomOnLeft = mark.x - plot.minX > 230
        context.draw(Text(words).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.textPrimary),
                     at: CGPoint(x: mark.x + (roomOnLeft ? -12 : 12), y: mark.y + (roomOnLeft ? -14 : 20)),
                     anchor: roomOnLeft ? .trailing : .leading)
    }
}

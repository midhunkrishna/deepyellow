import DYAnalysis
import DYCore
import Foundation

/// The figures above and beside the Things list, computed once per result.
struct ThingsSummary: Equatable {
    /// "294 GB as 41 things".
    var title: String
    /// "The largest 6 hold 80%. ..."
    var subtitle: String
    /// Running share of the total after each row, 0...1.
    var cumulative: [Double]
    /// How many of the largest rows it takes to reach 80%.
    var countFor80: Int

    /// Summarises a cut.
    init(result: ThingsResult, metric: Metric) {
        let total = Double(max(result.total, 1))
        var running: UInt64 = 0
        var cumulative: [Double] = []
        var reached = 0
        for (index, item) in result.items.enumerated() {
            running &+= item.value
            cumulative.append(Double(running) / total)
            if reached == 0, Double(running) >= total * 0.8 { reached = index + 1 }
        }
        let count = result.items.count
        self.cumulative = cumulative
        countFor80 = reached
        title = "\(MetricFormat.text(result.total, metric: metric)) as \(Format.count(count)) \(count == 1 ? "thing" : "things")"
        subtitle = "The largest \(Format.count(max(reached, min(count, 1)))) hold 80%. Nothing is counted twice, and the list adds up exactly to the total."
    }
}

/// Maps the level-of-detail slider to the number of things the list aims for.
enum ThingsDetail {
    static let fewest = 6.0
    static let most = 3000.0

    /// The target item count for a slider position in 0...1, on a log scale so every tick changes the list visibly.
    static func target(forPosition position: Double) -> Int {
        let clamped = min(max(position, 0), 1)
        return Int((fewest * pow(most / fewest, clamped)).rounded())
    }

    /// The slider position that gives `target` items.
    static func position(forTarget target: Int) -> Double {
        let value = min(max(Double(target), fewest), most)
        return log(value / fewest) / log(most / fewest)
    }
}

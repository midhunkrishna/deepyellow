import DYAnalysis
import DYCore
import DYWorkspace
import SwiftUI

/// The size histogram and cumulative share view.
///
/// Counts and bytes are separate small multiples, never one chart with two axes. A click on a column writes `size>` terms
/// into the query, so the filter stays visible and editable in the query field.
public struct SpectrumLens: View {
    let workspace: Workspace

    /// Creates the lens over a workspace.
    public init(workspace: Workspace) { self.workspace = workspace }

    public var body: some View {
        if let result = workspace.spectrum {
            content(result)
        } else {
            LensPlaceholder(message: "Measuring file sizes…").background(Theme.background)
        }
    }

    /// The headline, legend and charts.
    private func content(_ result: SpectrumResult) -> some View {
        let headline = SpectrumModel.headline(result)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                LensHeadline(title: Text(headline.title), subtitle: headline.subtitle)
                legend(result)
                if SpectrumModel.hasSizeTerms(workspace.queryText) {
                    Button("Clear the size range") { workspace.setQuery(SpectrumModel.clearingSize(workspace.queryText)) }
                        .buttonStyle(GhostButtonStyle())
                }
                if result.bins.isEmpty {
                    LensPlaceholder(message: "No files in view.").frame(height: 200)
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 24) {
                            histogram("How many files", result, .count)
                            histogram("How much space", result, .bytes)
                        }
                        .frame(minWidth: 820)
                        VStack(alignment: .leading, spacing: 24) {
                            histogram("How many files", result, .count)
                            histogram("How much space", result, .bytes)
                        }
                    }
                    SpectrumCurve(result: result)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 18)
        }
        .background(Theme.background)
    }

    /// One of the two histograms.
    private func histogram(_ title: String, _ result: SpectrumResult, _ series: SpectrumSeries) -> some View {
        SpectrumHistogram(title: title, result: result, series: series, activeQuery: workspace.queryText) { bin in
            workspace.setQuery(SpectrumModel.query(workspace.queryText, selecting: bin))
        }
    }

    /// The kind colours in use.
    private func legend(_ result: SpectrumResult) -> some View {
        HStack(spacing: 14) {
            ForEach(SpectrumModel.presentKinds(result), id: \.rawValue) { kind in
                HStack(spacing: 5) {
                    KindSwatch(kind: kind)
                    Text(kind.title).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }
}

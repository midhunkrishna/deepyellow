import DYCore
import DYLenses
import DYSQL
import DYWorkspace
import SwiftUI

/// A small control for the drawer's toolbar. Light fill for the main action; gold is left for what can be reclaimed.
struct SQLChipLabel: View {
    let title: String
    var symbol: String?
    var key: String?
    var prominent = false

    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)) }
            Text(title).font(.system(size: 11.5, weight: .medium))
            if let key { Text(key).font(Theme.mono(size: 10)).opacity(0.6) }
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .foregroundStyle(prominent ? Theme.background : Theme.textPrimary)
        .background(prominent ? Theme.textPrimary : Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(prominent ? Color.clear : Theme.hairline, lineWidth: 1))
    }
}

/// A plain button that wears `SQLChipLabel`.
struct SQLChipButton: View {
    let title: String
    var symbol: String?
    var key: String?
    var prominent = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) { SQLChipLabel(title: title, symbol: symbol, key: key, prominent: prominent).opacity(enabled ? 1 : 0.4) }
            .buttonStyle(.plain).disabled(!enabled)
    }
}

/// The SQL drawer: editor, toolbar and results, docked above the ledger. The views above stay live and show the result.
struct SQLDrawer: View {
    let shell: ShellState
    let availableHeight: CGFloat
    private var workspace: Workspace { shell.workspace }
    @State private var dragStart: CGFloat?
    @State private var showSchema = false

    /// The drawer's height: its share of the window, never so tall that the views vanish.
    private var height: CGFloat { min(max(availableHeight * shell.sqlHeightFraction, 200), max(200, availableHeight - 260)) }

    var body: some View {
        VStack(spacing: 0) {
            handle
            toolbar
            SQLEditor(text: Binding(get: { shell.sqlDraft }, set: { shell.sqlDraft = $0 }), focusToken: shell.sqlFocusToken)
                .frame(height: editorHeight)
                .background(Theme.background.opacity(0.55))
            Rectangle().fill(Theme.hairline).frame(height: 1)
            SQLResultsPane(shell: shell)
        }
        .frame(height: height)
        .background(Theme.surface)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    /// The editor grows with its text, from two lines to six.
    private var editorHeight: CGFloat {
        let lines = shell.sqlDraft.split(separator: "\n", omittingEmptySubsequences: false).count
        return CGFloat(min(max(lines, 2), 6)) * 16 + 24
    }

    /// A strip to drag for resizing.
    private var handle: some View {
        ZStack {
            Color.clear
            Capsule().fill(Theme.hairline).frame(width: 36, height: 3)
        }
        .frame(height: 9)
        .contentShape(Rectangle())
        .onHover { inside in if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
        .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                let start = dragStart ?? height
                dragStart = start
                shell.sqlHeightFraction = min(0.7, max(0.18, (start - value.translation.height) / max(availableHeight, 1)))
            }
            .onEnded { _ in dragStart = nil })
    }

    /// Run or Cancel, Examples, History, Schema, status, and the buttons that act on the result's set.
    private var toolbar: some View {
        HStack(spacing: 7) {
            Text("SQL").font(Theme.mono(size: 10.5, weight: .semibold)).foregroundStyle(Theme.textMuted).padding(.trailing, 2)
            if workspace.sqlPhase == .running {
                SQLChipButton(title: "Cancel", symbol: "stop.fill") { workspace.cancelSQL() }
            } else {
                SQLChipButton(title: "Run", symbol: "play.fill", key: "⌘⏎", prominent: true, enabled: !shell.sqlDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    shell.perform(.runSQL)
                }
            }
            Menu {
                ForEach(Array(SQLEngine.examples.enumerated()), id: \.offset) { _, example in
                    Button(example.title) { load(example.sql) }
                }
            } label: { SQLChipLabel(title: "Examples", symbol: "text.book.closed") }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            Menu {
                if workspace.sqlHistory.isEmpty { Text("Nothing run yet") }
                ForEach(Array(workspace.sqlHistory.enumerated()), id: \.offset) { _, entry in
                    Button(String(entry.replacingOccurrences(of: "\n", with: " ").prefix(80))) { load(entry) }
                }
            } label: { SQLChipLabel(title: "History", symbol: "clock") }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            SQLChipButton(title: "Schema", symbol: "tablecells") { showSchema.toggle() }
                .popover(isPresented: $showSchema, arrowEdge: .top) { SQLSchemaPanel() }
            Spacer(minLength: 8)
            Text(status).font(Theme.number(size: 11)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            if let result = workspace.sqlResult, result.shape != .tableOnly {
                SQLChipButton(title: "Select all", symbol: "checkmark.circle") { workspace.selectSQLResults() }
                SQLChipButton(title: "Review", symbol: "rectangle.stack") { workspace.reviewSQLResults() }
            }
            Button { shell.perform(.toggleSQL) } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.textMuted).frame(width: 22, height: 22) }
                .buttonStyle(.plain).help("Close the drawer (s)")
        }
        .padding(.horizontal, 12).padding(.bottom, 7)
    }

    /// The right-hand status text: running, or row count and time.
    private var status: String {
        if workspace.sqlPhase == .running { return "Running…" }
        guard let result = workspace.sqlResult else { return "" }
        let time = result.elapsed < 1 ? "\(Int((result.elapsed * 1000).rounded())) ms" : String(format: "%.2f s", result.elapsed)
        return "\(Format.count(result.rowCount)) \(result.rowCount == 1 ? "row" : "rows") · \(time)"
    }

    /// Puts a statement in the editor and focuses it.
    private func load(_ sql: String) {
        shell.sqlDraft = sql
        shell.sqlFocusToken += 1
    }
}

/// What the results area shows: an invitation, a running line, an error in place, or the table.
struct SQLResultsPane: View {
    let shell: ShellState
    private var workspace: Workspace { shell.workspace }

    var body: some View {
        VStack(spacing: 0) {
            if case .failed(let failure) = workspace.sqlPhase { SQLErrorBanner(failure: failure, keepsFilter: workspace.sqlIsFiltering) }
            if workspace.sqlPhase == .running { IndeterminateBar() }
            if let result = workspace.sqlResult {
                SQLSummaryStrip(shell: shell, result: result)
                if result.rows.isEmpty { emptyRows(result) } else {
                    SQLTable(shell: shell, result: result, drillRow: workspace.sqlDrillRow)
                        .opacity(workspace.sqlPhase == .running ? 0.45 : 1)
                }
            } else if workspace.sqlPhase == .running {
                Spacer()
            } else if case .failed = workspace.sqlPhase {
                Spacer()
            } else {
                SQLInvitation(shell: shell)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A finished query with no rows.
    private func emptyRows(_ result: SQLResult) -> some View {
        VStack(spacing: 4) {
            Spacer()
            Text("No rows").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Text(result.shape == .tableOnly ? "The query ran and returned nothing." : "Nothing matched, so the views above are empty. The ✕ beside the query field brings everything back.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 24).frame(maxWidth: .infinity)
    }
}

/// The empty state: what the drawer is for, and three queries to start from.
struct SQLInvitation: View {
    let shell: ShellState

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            Text("Ask your disk a question").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Text("Write a SELECT over files, dirs or nodes. A result with an id column narrows every view above to those things.")
                .font(.system(size: 12)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            HStack(spacing: 8) {
                ForEach(Array(SQLEngine.examples.enumerated().filter { [0, 2, 8].contains($0.offset) }), id: \.offset) { _, entry in
                    Button {
                        shell.sqlDraft = entry.sql
                        shell.perform(.runSQL)
                    } label: { SQLChipLabel(title: entry.title) }
                        .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24).frame(maxWidth: .infinity)
    }
}

/// A thin line that sweeps while a query runs.
struct IndeterminateBar: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            GeometryReader { proxy in
                let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.hairline)
                    Rectangle().fill(Theme.textSecondary).frame(width: proxy.size.width * 0.25).offset(x: (proxy.size.width * 1.25) * phase - proxy.size.width * 0.25)
                }
                .clipped()
            }
        }
        .frame(height: 2)
    }
}

/// A failed query, in plain words, above whatever was already on screen. The views are not touched.
struct SQLErrorBanner: View {
    let failure: SQLFailure
    let keepsFilter: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(Theme.textSecondary).padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text(SQLValueText.message(of: failure) + (keepsFilter ? " The views still show the last result." : ""))
                    .font(.system(size: 12)).foregroundStyle(Theme.textSecondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceRaised)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.textMuted).frame(width: 3) }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private var title: String {
        switch failure {
        case .invalid: "This query can't run"
        case .refused: "Read-only"
        case .multipleStatements: "One statement at a time"
        case .tooLarge: "Too much for memory"
        case .cancelled: "Cancelled"
        }
    }

    private var symbol: String {
        switch failure {
        case .refused: "lock"
        case .cancelled: "stop.circle"
        default: "exclamationmark.triangle"
        }
    }
}

/// One line above the table: what the result does to the views, the row cap, and the way back from a drilled group.
struct SQLSummaryStrip: View {
    let shell: ShellState
    let result: SQLResult
    private var workspace: Workspace { shell.workspace }

    var body: some View {
        HStack(spacing: 10) {
            Text(summary).font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            if result.shape == .groups, workspace.sqlDrillRow != nil {
                Button { workspace.drillSQL(row: nil) } label: {
                    HStack(spacing: 4) { Image(systemName: "chevron.left").font(.system(size: 9, weight: .bold)); Text("All groups").font(.system(size: 11.5, weight: .medium)) }
                        .foregroundStyle(Theme.textPrimary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            if result.rows.count < result.rowCount {
                Text("showing \(Format.count(result.rows.count)) of \(Format.count(result.rowCount)) rows")
                    .font(Theme.number(size: 11)).foregroundStyle(Theme.textMuted)
            }
        }
        .padding(.horizontal, 14).frame(height: 26)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    /// What this result means for the views.
    private var summary: String {
        switch result.shape {
        case .nodes: return "Every view shows these \(Format.count(result.nodes.count)) \(result.nodes.count == 1 ? "thing" : "things")"
        case .groups:
            if let row = workspace.sqlDrillRow { return "Group \(row + 1) of \(Format.count(result.rowCount)) narrows the views" }
            return "\(Format.count(result.rowCount)) groups. Click one to narrow the views to it"
        case .tableOnly:
            return "This result has no id column, so the views stay as they are. Add id to the SELECT, or ids(id) to a GROUP BY."
        }
    }
}

/// How wide each column is and which ones are numbers.
enum SQLColumnLayout {
    /// A width for every column from its name and the first rows, clamped so one long path can't take the table.
    static func widths(_ result: SQLResult) -> [CGFloat] {
        result.columns.indices.map { index in
            let sample = result.rows.prefix(120).map { SQLValueText.text($0[index]).count }.max() ?? 0
            let characters = max(result.columns[index].count, min(sample, 64))
            return min(max(CGFloat(characters) * 7.1 + 26, 64), 460)
        }
    }

    /// Gives the room left over to the last text column, or to the last column when all are numbers, so a narrow table fills the drawer.
    static func fill(_ widths: [CGFloat], numeric: [Bool], available: CGFloat) -> [CGFloat] {
        guard !widths.isEmpty else { return widths }
        let extra = available - widths.reduce(0, +)
        guard extra > 0 else { return widths }
        var result = widths
        result[numeric.lastIndex(of: false) ?? widths.count - 1] += extra
        return result
    }

    /// True for columns whose first non-null cell is a number.
    static func numeric(_ result: SQLResult) -> [Bool] {
        result.columns.indices.map { index in
            result.rows.prefix(50).map { $0[index] }.first { $0 != .null }.map(SQLValueText.isNumber) ?? false
        }
    }
}

/// The result table: pinned header, virtualised rows, horizontal scroll when wide.
struct SQLTable: View {
    let shell: ShellState
    let result: SQLResult
    let drillRow: Int?
    @State private var hovered: Int?
    @State private var lastTapped: Int?
    private var workspace: Workspace { shell.workspace }

    var body: some View {
        let numeric = SQLColumnLayout.numeric(result)
        GeometryReader { proxy in
            let widths = SQLColumnLayout.fill(SQLColumnLayout.widths(result), numeric: numeric, available: proxy.size.width - 28)
            ScrollViewReader { scroller in
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(result.rows.indices, id: \.self) { index in row(index, widths, numeric).id(index) }
                        } header: {
                            header(widths, numeric)
                        }
                    }
                    .frame(minWidth: proxy.size.width, minHeight: proxy.size.height, alignment: .topLeading)
                }
                .scrollIndicators(.automatic)
                .onChange(of: workspace.selectedNodes.last) { _, node in revealRow(of: node, with: scroller) }
            }
        }
    }

    /// Scrolls the table to a node chosen elsewhere, such as on the Map. A click inside the table leaves the scroll alone.
    private func revealRow(of node: NodeID?, with scroller: ScrollViewProxy) {
        guard result.shape == .nodes, let node, let index = result.rowNode.firstIndex(of: node) else { return }
        if lastTapped == index { lastTapped = nil; return }
        scroller.scrollTo(index)
    }

    /// The column names.
    private func header(_ widths: [CGFloat], _ numeric: [Bool]) -> some View {
        HStack(spacing: 0) {
            ForEach(result.columns.indices, id: \.self) { column in
                Text(result.columns[column].uppercased()).font(Theme.mono(size: 9.5, weight: .semibold)).foregroundStyle(Theme.textMuted)
                    .lineLimit(1).padding(.trailing, 14).frame(width: widths[column], alignment: numeric[column] ? .trailing : .leading)
            }
        }
        .padding(.horizontal, 14).frame(height: 22, alignment: .leading)
        .background(Theme.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    /// One result row.
    private func row(_ index: Int, _ widths: [CGFloat], _ numeric: [Bool]) -> some View {
        let node: NodeID? = result.shape == .nodes && result.rowNode.indices.contains(index) ? result.rowNode[index] : nil
        let selected = node.map { workspace.isSelected($0) } ?? false
        let drilled = result.shape == .groups && drillRow == index
        let dimmed = result.shape == .nodes && node == nil
        return HStack(spacing: 0) {
            ForEach(result.columns.indices, id: \.self) { column in
                cell(result.rows[index][column], name: result.columns[column], numeric: numeric[column])
                    .padding(.trailing, 14)
                    .frame(width: widths[column], alignment: numeric[column] ? .trailing : .leading)
            }
        }
        .padding(.horizontal, 14).frame(height: 22, alignment: .leading)
        .background(selected || drilled ? Theme.surfaceRaised : (hovered == index ? Theme.surfaceRaised.opacity(0.55) : (index % 2 == 1 ? Theme.background.opacity(0.4) : Color.clear)))
        .overlay(alignment: .leading) { if selected || drilled { Rectangle().fill(Theme.textPrimary).frame(width: 2) } }
        .opacity(dimmed ? 0.45 : 1)
        .contentShape(Rectangle())
        .onTapGesture { tap(index, node) }
        .onHover { inside in
            if inside { hovered = index } else if hovered == index { hovered = nil }
            if result.shape == .nodes { workspace.hover = inside ? node : nil }
        }
    }

    /// A click selects the node as anywhere else, or drills into the group, or goes back out of it.
    private func tap(_ index: Int, _ node: NodeID?) {
        switch result.shape {
        case .nodes:
            guard let node else { return }
            lastTapped = index
            let flags = NSEvent.modifierFlags
            workspace.click(node, additive: flags.contains(.shift) || flags.contains(.command))
        case .groups: workspace.drillSQL(row: drillRow == index ? nil : index)
        case .tableOnly: break
        }
    }

    /// One cell: numbers in tabular mono, a swatch for kinds, middle truncation for anything long.
    @ViewBuilder private func cell(_ value: SQLValue, name: String, numeric: Bool) -> some View {
        switch value {
        case .null:
            Text("NULL").font(Theme.mono(size: 10, weight: .medium)).foregroundStyle(Theme.textMuted)
        case .integer, .real:
            Text(SQLValueText.text(value)).font(Theme.mono(size: 11.5)).foregroundStyle(Theme.textPrimary).lineLimit(1)
        case .blob:
            Text(SQLValueText.text(value)).font(Theme.mono(size: 10.5)).foregroundStyle(Theme.textMuted).lineLimit(1)
        case .text(let text):
            HStack(spacing: 6) {
                if name == "kind", let kind = FileKind.allCases.first(where: { "\($0)" == text }) {
                    Circle().fill(Theme.kind(kind)).frame(width: 7, height: 7)
                }
                if name.contains("path") || text.contains("/") {
                    Text(text).font(Theme.mono(size: 11)).foregroundStyle(Theme.textSecondary).lineLimit(1).truncationMode(.middle)
                } else {
                    Text(text).font(.system(size: 12)).foregroundStyle(Theme.textPrimary).lineLimit(1).truncationMode(.middle)
                }
            }
        }
    }
}

/// Every column of `nodes` and every function, for the Schema button.
struct SQLSchemaPanel: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Table nodes").font(.system(size: 12, weight: .semibold))
                Text("One row per file or folder. The views files and dirs hold the visible ones.").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                ForEach(SQLEngine.schema, id: \.name) { doc in entry(doc.name, doc.type, doc.meaning, typeWidth: 62) }
                Text("Functions").font(.system(size: 12, weight: .semibold)).padding(.top, 6)
                ForEach(SQLEngine.functions, id: \.name) { doc in entry(doc.name, doc.type, doc.meaning, typeWidth: 0) }
            }
            .padding(14)
        }
        .frame(width: 560, height: 420)
        .background(Theme.surface)
        .foregroundStyle(Theme.textPrimary)
    }

    /// One documented name.
    private func entry(_ name: String, _ type: String, _ meaning: String, typeWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 8) {
                Text(typeWidth > 0 ? name : type).font(Theme.mono(size: 11.5, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                if typeWidth > 0 { Text(type).font(Theme.mono(size: 10)).foregroundStyle(Theme.textMuted) }
            }
            Text(meaning).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The top-bar chip shown while a result narrows the views: `SQL 12 things · 184 GB ✕`.
struct SQLChip: View {
    let shell: ShellState
    private var workspace: Workspace { shell.workspace }

    var body: some View {
        if let summary = workspace.sqlFilterSummary {
            HStack(spacing: 7) {
                Text("SQL").font(Theme.mono(size: 9.5, weight: .semibold)).foregroundStyle(Theme.textMuted)
                Text(summary).font(Theme.number(size: 11.5)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Button { workspace.clearSQL() } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.textSecondary).frame(width: 14, height: 14) }
                    .buttonStyle(.plain).help("Clear the SQL filter")
            }
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.textMuted.opacity(0.55), lineWidth: 1))
            .fixedSize()
            .contentShape(Rectangle())
            .onTapGesture { if !shell.sqlOpen { shell.perform(.toggleSQL) } }
        }
    }
}

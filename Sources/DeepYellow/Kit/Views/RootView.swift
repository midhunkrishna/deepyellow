import DYAnalysis
import DYCore
import DYLenses
import DYPreview
import DYRender
import DYScan
import DYWorkspace
import SwiftUI

/// The whole window: one thin top line, the canvas, one thin bottom line, and panels only when summoned.
public struct RootView: View {
    let shell: ShellState
    private var workspace: Workspace { shell.workspace }

    /// Creates the window content.
    public init(shell: ShellState) { self.shell = shell }

    public var body: some View {
        ZStack {
            Theme.background
            if workspace.source == nil {
                WelcomeView(shell: shell)
            } else {
                GeometryReader { proxy in
                    VStack(spacing: 0) {
                        HeaderBar(shell: shell)
                        Divider().overlay(Theme.hairline)
                        ToolsRow(shell: shell)
                        NoticeBar(shell: shell)
                        content
                        if shell.sqlOpen { SQLDrawer(shell: shell, availableHeight: proxy.size.height) }
                        Divider().overlay(Theme.hairline)
                        LedgerFooter(shell: shell)
                    }
                }
            }
            if shell.hintsHeld { HintsOverlay().transition(.opacity) }
            VStack { Spacer(); ToastView(shell: shell) }.padding(.bottom, 54)
            SheetHost(shell: shell)
        }
        .preferredColorScheme(.dark)
        .lensActions(LensActions(
            previewNode: { node in shell.workspace.select([node]); shell.previewOpen = true },
            reviewPlan: { shell.perform(.openPlan) }))
        .ignoresSafeArea(.container, edges: .top)
        .animation(.easeOut(duration: 0.12), value: shell.hintsHeld)
    }

    /// The canvas area: review replaces it, otherwise the lens with the preview pane beside it.
    @ViewBuilder private var content: some View {
        if workspace.review != nil {
            ReviewMode(workspace: workspace, controller: shell.preview)
        } else {
            HStack(spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    LensHost(shell: shell)
                    if let hover = workspace.hover, let summary = workspace.summary(for: hover) {
                        HUDCard(summary: summary).padding(14).allowsHitTesting(false)
                    }
                }
                if shell.previewOpen {
                    Divider().overlay(Theme.hairline)
                    VStack(spacing: 0) {
                        PreviewPane(item: workspace.selectionPreview, controller: shell.preview)
                        if shell.isDemo {
                            Text("Sample disk: this preview plays generated sample media, not a file on your Mac.")
                                .font(.system(size: 10.5)).foregroundStyle(Theme.textMuted).padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(width: 420)
                }
            }
        }
    }
}

/// Breadcrumb, query field and lens tabs.
struct HeaderBar: View {
    let shell: ShellState
    private var workspace: Workspace { shell.workspace }
    @FocusState private var queryFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            if shell.isShot { StandInWindowButtons() } else { Color.clear.frame(width: 64, height: 1) }
            breadcrumb.layoutPriority(0)
            queryField
            SQLChip(shell: shell)
            Spacer(minLength: 4)
            tabs.layoutPriority(2)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
    }

    /// Clickable path from the scan root to the focus.
    private var breadcrumb: some View {
        HStack(spacing: 4) {
            Image(systemName: "internaldrive").font(.system(size: 11)).foregroundStyle(Theme.textMuted)
            ForEach(Array(workspace.breadcrumb.enumerated()), id: \.element) { index, node in
                if index > 0 { Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.textMuted) }
                Button(crumbTitle(node)) { workspace.setFocus(node) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: index == workspace.breadcrumb.count - 1 ? .semibold : .regular))
                    .foregroundStyle(index == workspace.breadcrumb.count - 1 ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .lineLimit(1)
        .frame(minWidth: 60, alignment: .leading)
    }

    /// The name shown for a breadcrumb node; the root shows the last part of the scanned path.
    private func crumbTitle(_ node: NodeID) -> String {
        guard let tree = workspace.tree else { return "" }
        if node == 0 {
            let root = tree.meta.rootPath
            return root == "/" ? (shell.isDemo ? "Macintosh HD" : "Disk") : (root as NSString).lastPathComponent
        }
        return tree.name(node)
    }

    /// The query field with its error flag and busy dot.
    private var queryField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.textMuted)
            TextField("", text: Binding(get: { workspace.queryText }, set: { workspace.setQuery($0) }),
                      prompt: Text("/  size>100mb age>1y kind:video").foregroundColor(Theme.textMuted))
                .textFieldStyle(.plain)
                .font(Theme.mono(size: 11.5))
                .focused($queryFocused)
                .onSubmit { queryFocused = false; NSApp.keyWindow?.makeFirstResponder(nil) }
            if !workspace.query.errors.isEmpty {
                Label("\(workspace.query.errors.count)", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.accent)
                    .help(workspace.query.errors.joined(separator: "\n"))
            }
            if workspace.isRecomputing { Circle().fill(Theme.accent).frame(width: 6, height: 6) }
            if !workspace.queryText.isEmpty {
                Button { workspace.setQuery("") } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textMuted) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .frame(minWidth: 180, idealWidth: 330, maxWidth: 380)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(queryFocused ? Theme.accent : Theme.hairline, lineWidth: 1))
        .onChange(of: shell.queryFocusToken) { queryFocused = true }
    }

    /// The seven lens tabs.
    private var tabs: some View {
        HStack(spacing: 2) {
            ForEach(Array(LensKind.allCases.enumerated()), id: \.element) { index, kind in
                let selected = workspace.lensKind == kind
                Button { shell.perform(.lens(kind)) } label: {
                    HStack(spacing: 4) {
                        Text("\(index + 1)").font(Theme.mono(size: 9.5)).foregroundStyle(Theme.textMuted)
                        Text(ShellCommand.lensTitle(kind)).font(.system(size: 12, weight: selected ? .semibold : .regular))
                    }
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                    .overlay(alignment: .bottom) { if selected { Rectangle().fill(Theme.accent).frame(height: 2).padding(.horizontal, 5) } }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Three stand-ins for the window buttons, used only in screenshots taken without a real window.
struct StandInWindowButtons: View {
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { _ in Circle().fill(Theme.hairline).frame(width: 12, height: 12) }
        }
        .frame(width: 64, alignment: .leading)
    }
}

/// The contextual tools row: selection and verdicts, or hints; view options on the right.
struct ToolsRow: View {
    let shell: ShellState
    private var workspace: Workspace { shell.workspace }

    var body: some View {
        HStack(spacing: 8) {
            if workspace.selectionCount > 0 { selectionTools } else { hint }
            Spacer(minLength: 8)
            viewOptions
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(Theme.surface.opacity(0.6))
    }

    private var hint: some View {
        Text("Click to select, double-click to zoom in, right-click for more.  Hold ⌥ for every shortcut.")
            .font(.system(size: 11.5)).foregroundStyle(Theme.textMuted).lineLimit(1)
    }

    /// Count, size and the verdict buttons for the selection.
    private var selectionTools: some View {
        HStack(spacing: 6) {
            Text("\(Format.count(workspace.selectionCount)) selected")
                .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Text(Format.bytes(workspace.selectionBytes)).font(Theme.number(size: 11.5)).foregroundStyle(Theme.textSecondary)
            ChipButton(title: "Keep", key: "k", tint: Theme.keep) { shell.perform(.mark(.keep)) }
            ChipButton(title: "Remove", key: "x", tint: Theme.remove) { shell.perform(.mark(.remove)) }
            ChipButton(title: "Later", key: "l", tint: Theme.later) { shell.perform(.mark(.later)) }
            ChipButton(title: "Clear", key: "u") { shell.perform(.mark(.none)) }
            ChipButton(title: "Hide", key: "h") { shell.perform(.hide) }
            ChipButton(title: "Review", key: "r") { shell.perform(.review) }
        }
    }

    /// Metric, colour mode, field clock, preview and palette.
    private var viewOptions: some View {
        HStack(spacing: 6) {
            if [.map, .rings, .field].contains(workspace.lensKind) {
                Menu {
                    ForEach(ColorMode.allCases, id: \.self) { mode in Button(colorTitle(mode)) { workspace.setColorMode(mode) } }
                } label: { Text("Colour: \(colorTitle(workspace.colorMode))").font(.system(size: 11.5)) }
                    .menuStyle(.borderlessButton).fixedSize()
            }
            if workspace.lensKind == .field {
                ChipButton(title: workspace.fieldClock == .modified ? "Age: modified" : "Age: opened") {
                    workspace.setFieldClock(workspace.fieldClock == .modified ? .accessed : .modified)
                }
            }
            ChipButton(title: workspace.metric == .bytes ? "Size" : "Files", key: "m") { shell.perform(.toggleMetric) }
            ChipButton(title: "Preview", key: "Space") { shell.perform(.togglePreview) }
            ChipButton(title: "Commands", key: "⌘K") { shell.perform(.openPalette) }
        }
    }

    /// The name of a colour mode.
    private func colorTitle(_ mode: ColorMode) -> String {
        switch mode {
        case .kind: "Kind"
        case .age: "Age"
        case .safety: "Safety"
        case .decision: "Decision"
        }
    }
}

/// States what the scan is doing and how complete it is. Partial results are never presented as whole.
struct NoticeBar: View {
    let shell: ShellState
    private var workspace: Workspace { shell.workspace }

    var body: some View {
        if let text = message {
            HStack(spacing: 10) {
                Image(systemName: workspace.scanPhase == .scanning ? "waveform" : "exclamationmark.circle").foregroundStyle(Theme.accent)
                Text(text).font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                Spacer()
                if workspace.scanPhase == .scanning { ChipButton(title: "Stop scan") { workspace.cancelScan() } }
                else if workspace.reconciliation?.limitedByPermissions == true && !shell.isDemo {
                    ChipButton(title: "Open Full Disk Access settings") { FullDiskAccess.openSettings() }
                }
            }
            .padding(.horizontal, 12).frame(height: 28)
            .background(Theme.surfaceRaised.opacity(0.7))
        }
    }

    /// The line to show, or nil when everything is complete.
    private var message: String? {
        if workspace.scanPhase == .scanning {
            let p = workspace.scanProgress
            let rate = (p?.elapsed ?? 0) > 0.5 ? " · \(Format.compactCount(Int(Double(p?.files ?? 0) / (p?.elapsed ?? 1)))) files/s" : ""
            let cached = workspace.isShowingCachedScan ? "Showing the scan from \(workspace.cachedScanAge ?? "earlier") while rescanning. " : ""
            return "\(cached)Reading… \(Format.count(p?.files ?? 0)) files, \(Format.bytes(p?.bytes ?? 0))\(rate)"
        }
        if workspace.scanWasCancelled { return "The scan was stopped early. These totals are partial." }
        if let r = workspace.reconciliation, r.limitedByPermissions || r.unreadableDirectories > 0 {
            return "Partial: \(Format.count(r.unreadableDirectories)) folders could not be read, so real totals are higher than shown. Full Disk Access lets DeepYellow read them."
        }
        return nil
    }
}

/// Picks the view for the current lens.
struct LensHost: View {
    let shell: ShellState
    private var workspace: Workspace { shell.workspace }

    var body: some View {
        Group {
            if workspace.lens == nil {
                Text(workspace.scanPhase == .idle ? "Nothing to show yet." : "Reading the first folders…")
                    .font(.system(size: 13)).foregroundStyle(Theme.textMuted).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch workspace.lensKind {
                case .map, .rings, .field: CanvasLens(shell: shell, kind: workspace.lensKind).id(workspace.lensKind)
                case .things: ThingsLens(workspace: workspace)
                case .spectrum: SpectrumLens(workspace: workspace)
                case .browse: BrowseLens(workspace: workspace)
                case .reclaim: ReclaimLens(workspace: workspace)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}

/// Hosts one Metal canvas through `DiskCanvasView`.
struct CanvasLens: View {
    let shell: ShellState
    let kind: LensKind
    private var workspace: Workspace { shell.workspace }

    var body: some View {
        if let lens = workspace.lens, let canvas = shell.canvases.canvas(for: kind) {
            if let image = shell.shotSnapshot {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                DiskCanvasView(canvas: canvas, lens: lens, style: workspace.nodeStyle, metric: workspace.metric,
                               selection: Set(workspace.selectedNodes), focus: workspace.focus, events: shell.canvasEvents(),
                               styleRevision: workspace.decisionVersion * 4 + (workspace.reclaimReport != nil ? 1 : 0) + (workspace.kindRefinement != nil ? 2 : 0))
                    .onChange(of: workspace.field?.nodes.count) { shell.syncField() }
                    .onAppear { shell.syncField() }
            }
        }
    }
}

extension ShellState {
    /// Pushes the Field lens points into the Field canvas.
    func syncField() {
        guard let data = workspace.field else { return }
        canvases.field.setPoints(positions: data.positions, kinds: data.kinds, nodes: data.nodes, ageRange: data.ageRange, sizeRange: data.sizeRange)
    }
}

/// What the pointer is over: name, size, share, date, files, safety and why.
struct HUDCard: View {
    let summary: NodeSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                DecisionGlyph(decision: summary.decision)
                Text(summary.name).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
            }
            HStack(spacing: 8) {
                Text(Format.bytes(summary.bytes)).font(Theme.number(size: 12, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                if let share = summary.shareOfParent { Text("\(share) of parent").font(.system(size: 11)).foregroundStyle(Theme.textSecondary) }
            }
            Text("\(Format.count(summary.files)) files" + (summary.modified.map { " · modified \($0.formatted(.dateTime.year().month().day()))" } ?? ""))
                .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            if summary.tier != .unknown {
                Text(tierName(summary.tier) + (summary.ruleTitle.map { ": \($0)" } ?? ""))
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(summary.tier == .safe || summary.tier == .rebuild ? Theme.accent : Theme.textSecondary)
                if let consequence = summary.consequence {
                    Text(consequence).font(.system(size: 11)).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(10).frame(width: 300, alignment: .leading)
        .background(Theme.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline, lineWidth: 1))
    }
}

/// The ledger line: a bar of the whole volume and the staged total.
struct LedgerFooter: View {
    let shell: ShellState
    private var workspace: Workspace { shell.workspace }

    var body: some View {
        HStack(spacing: 12) {
            Button { shell.perform(.openLedger) } label: {
                HStack(spacing: 10) {
                    Text("LEDGER").font(Theme.mono(size: 10, weight: .semibold)).foregroundStyle(Theme.textMuted)
                    bar.frame(width: 230, height: 8)
                    Text(summary).font(Theme.number(size: 11.5)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8)
            stagedButton
        }
        .padding(.horizontal, 12).frame(height: 34)
        .background(Theme.surface.opacity(0.6))
    }

    /// The staged total, or a note that nothing is staged.
    @ViewBuilder private var stagedButton: some View {
        if shell.isReadOnly { Text("READ-ONLY").font(Theme.mono(size: 10, weight: .semibold)).foregroundStyle(Theme.textMuted).padding(.trailing, 8) }
        if let plan = workspace.plan, !plan.items.isEmpty {
            Button { shell.perform(.openPlan) } label: {
                HStack(spacing: 6) {
                    Hatch().frame(width: 14, height: 12).clipShape(RoundedRectangle(cornerRadius: 2))
                    Text("\(Format.bytes(workspace.stagedBytes)) staged").font(Theme.number(size: 11.5, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    KeyCap(text: "⌘⏎")
                }
            }
            .buttonStyle(.plain)
        } else {
            Text("Nothing staged").font(.system(size: 11.5)).foregroundStyle(Theme.textMuted)
        }
    }

    /// The text beside the bar.
    private var summary: String {
        guard let r = workspace.reconciliation else { return "Reading…" }
        var parts = ["\(Format.bytes(r.visibleBytes)) visible", "\(Format.bytes(r.hiddenBytes)) hidden"]
        if r.unreadableDirectories > 0 { parts.append("\(Format.count(r.unreadableDirectories)) unreadable") }
        if let free = r.volumeAvailable { parts.append("\(Format.bytes(free)) free" + (r.usesSampleValues ? " (sample)" : "")) }
        return parts.joined(separator: " · ")
    }

    /// Visible, hidden, remainder and free as shares of the volume, with staged removal hatched over the visible part.
    private var bar: some View {
        GeometryReader { proxy in
            let r = workspace.reconciliation
            let total = Double(max(1, r?.volumeTotal ?? r?.scannedBytes ?? 1))
            let width = proxy.size.width
            let visible = width * Double(r?.visibleBytes ?? 0) / total
            let hidden = width * Double(r?.hiddenBytes ?? 0) / total
            let other = width * Double(max(0, r?.remainderBytes ?? 0)) / total
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(Theme.background).overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.hairline))
                HStack(spacing: 0) {
                    Rectangle().fill(Theme.textSecondary).frame(width: visible)
                    Rectangle().fill(Theme.textMuted).frame(width: hidden)
                    Rectangle().fill(Theme.hairline).frame(width: other)
                }
                .clipShape(RoundedRectangle(cornerRadius: 2))
                let staged = min(visible, width * Double(workspace.stagedBytes) / total)
                if staged > 0 { Hatch(spacing: 4).frame(width: max(3, staged)).offset(x: max(0, visible - staged)).clipped() }
            }
        }
    }
}

/// The message line at the bottom of the canvas.
struct ToastView: View {
    let shell: ShellState
    private var workspace: Workspace { shell.workspace }

    var body: some View {
        if let notice = workspace.notice {
            HStack(spacing: 12) {
                Text(notice.message).font(.system(size: 12)).foregroundStyle(Theme.textPrimary)
                if notice.canUndo { ChipButton(title: "Undo", key: "⌘Z") { workspace.undoNotice() } }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
            .task(id: notice.id) {
                try? await Task.sleep(for: .seconds(6))
                if workspace.notice?.id == notice.id { workspace.dismissNotice() }
            }
        }
    }
}

/// Every shortcut, shown while ⌥ is held.
struct HintsOverlay: View {
    var body: some View {
        let entries = ShellCommand.catalog.filter { !$0.key.isEmpty } + [
            ShellCommand.Info(title: "Move selection", key: "← ↑ ↓ →", command: .escape),
            ShellCommand.Info(title: "Back out one level", key: "Esc", command: .escape),
        ]
        ZStack {
            Color.black.opacity(0.35)
            VStack(alignment: .leading, spacing: 10) {
                HStack { Text("Shortcuts").font(.system(size: 13, weight: .semibold)); Spacer(); Text("release ⌥ to close").font(.system(size: 11)).foregroundStyle(Theme.textMuted) }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                        HStack(spacing: 8) {
                            KeyCap(text: entry.key).frame(minWidth: 40, alignment: .leading)
                            Text(entry.title).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                        }
                    }
                }
            }
            .padding(18).frame(width: 640)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline))
        }
        .allowsHitTesting(false)
    }
}

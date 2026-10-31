import AppKit
import DYCore
import DYPreview
import DYRender
import DYScan
import DYWorkspace
import Observation
import SwiftUI

/// Which modal panel is open.
public enum ShellSheet: Equatable { case plan, ledger, palette }

/// The three canvases, created once so they survive lens switches.
@MainActor
public final class CanvasSet {
    public let map = MapCanvas(frame: .zero)
    public let rings = RingsCanvas(frame: .zero)
    public let field = FieldCanvas(frame: .zero)

    /// The canvas that draws `kind`, or nil for lenses built from SwiftUI.
    public func canvas(for kind: LensKind) -> (any DiskCanvas)? {
        switch kind {
        case .map: map
        case .rings: rings
        case .field: field
        default: nil
        }
    }
}

/// View state that isn't part of the workspace: panels, hints, focus requests and the commands that drive them.
@MainActor @Observable
public final class ShellState {
    @ObservationIgnored public let workspace: Workspace
    @ObservationIgnored public let preview = PreviewController()
    @ObservationIgnored public let canvases = CanvasSet()
    @ObservationIgnored public let recentStore: RecentStore
    @ObservationIgnored public let isDemo: Bool
    /// A real scan whose Trash mover refuses everything; Apply is not offered.
    @ObservationIgnored public let isReadOnly: Bool

    public var sheet: ShellSheet?
    public var previewOpen = false
    public var hintsHeld = false
    public var paletteQuery = ""
    /// Bumped to move keyboard focus into the query field.
    public var queryFocusToken = 0
    public var hoverPoint: CGPoint = .zero
    public var fullDiskAccess: FullDiskAccess
    public var recents: [String]
    public var volumes: [VolumeInfo]
    /// Set by the screenshot harness: draw this image instead of the live canvas.
    public var shotSnapshot: NSImage?
    /// True while rendering a screenshot, which adds stand-in window buttons.
    public var isShot = false

    /// Creates the state around a workspace.
    public init(workspace: Workspace, isDemo: Bool, isReadOnly: Bool = false, fullDiskAccess: FullDiskAccess = FullDiskAccess.probe()) {
        self.workspace = workspace
        self.isDemo = isDemo
        self.isReadOnly = isReadOnly && !isDemo
        self.fullDiskAccess = fullDiskAccess
        recentStore = RecentStore(directory: workspace.environment.dataDirectory)
        recents = recentStore.load()
        volumes = workspace.environment.volumes()
    }

    // MARK: Commands

    /// Runs a command. Every key, menu item and palette row ends up here.
    public func perform(_ command: ShellCommand) {
        switch command {
        case .lens(let kind): workspace.setLens(kind)
        case .mark(let decision): mark(decision)
        case .review: if workspace.review == nil { Task { _ = await workspace.startReview() } }
        case .openPlan: workspace.endReview(); sheet = .plan
        case .togglePreview: previewOpen.toggle()
        case .focusQuery: queryFocusToken += 1
        case .toggleMetric: workspace.setMetric(workspace.metric == .bytes ? .files : .bytes)
        case .cycleColor: cycleColor()
        case .hide: if !workspace.selectedNodes.isEmpty { workspace.hide(.path, nodes: workspace.selectedNodes) }
        case .zoomIn: zoomIntoSelection()
        case .zoomOut: _ = workspace.zoomOut()
        case .undo: _ = workspace.undoDecision()
        case .redo: _ = workspace.redoDecision()
        case .openPalette: paletteQuery = ""; sheet = .palette
        case .openLedger: sheet = .ledger
        case .escape: backOut()
        case .chooseFolder: chooseFolder()
        case .openDemo: openDemo()
        case .rescan: if case .path(let path)? = workspace.source { workspace.open(.path(path), useCache: false) }
        case .installCLI: InstallPrompt.run()
        case .toggleHints: hintsHeld.toggle()
        case .move(let direction): move(direction)
        }
    }

    /// Applies a verdict to the review item when reviewing, else to the selection.
    private func mark(_ decision: Decision) {
        if workspace.review != nil {
            if decision == .none { _ = workspace.undoDecision() } else { _ = workspace.reviewVerdict(decision) }
        } else {
            _ = workspace.mark(decision)
        }
    }

    /// Steps to the next colour mode.
    private func cycleColor() {
        let all = ColorMode.allCases
        let next = all[((all.firstIndex(of: workspace.colorMode) ?? 0) + 1) % all.count]
        workspace.setColorMode(next)
    }

    /// Zooms into the first selected folder.
    private func zoomIntoSelection() {
        guard let node = workspace.selectedNodes.first(where: { workspace.tree?.isDirectory($0) == true }) else { return }
        workspace.zoomIn(node)
    }

    /// Backs out one level: panel, review, preview, selection, then zoom.
    private func backOut() {
        if sheet != nil { sheet = nil }
        else if workspace.review != nil { workspace.endReview() }
        else if previewOpen { previewOpen = false }
        else if workspace.selectionCount > 0 { workspace.clearSelection() }
        else { _ = workspace.zoomOut() }
    }

    /// Moves the selection: left and right between siblings, up to the parent, down to the first child. In review, steps through the set.
    private func move(_ direction: MoveDirection) {
        if let review = workspace.review {
            workspace.reviewGo(to: review.index + (direction == .right || direction == .down ? 1 : -1))
            return
        }
        guard let tree = workspace.tree, let lens = workspace.lens else { return }
        guard let current = workspace.selectedNodes.last else {
            if let first = lens.visibleChildren(of: workspace.focus).first { workspace.select([first]) }
            return
        }
        switch direction {
        case .up: if current != 0 { workspace.select([tree.parent(current)]) }
        case .down: if let child = lens.visibleChildren(of: current).first { workspace.select([child]) }
        case .left, .right:
            let siblings = lens.visibleChildren(of: tree.parent(current))
            guard let index = siblings.firstIndex(of: current) else { return }
            let target = index + (direction == .right ? 1 : -1)
            if siblings.indices.contains(target) { workspace.select([siblings[target]]) }
        }
    }

    // MARK: Opening

    /// Opens a folder, remembers it, and leaves any open panel.
    public func open(path: String) {
        sheet = nil
        recents = recentStore.record(path)
        workspace.open(.path(path))
    }

    /// Asks which folder to scan.
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Scan"
        panel.message = "Choose a folder or a volume to read. Nothing is changed."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(path: url.path)
    }

    /// Opens the sample disk here, or in a new demo instance when this session is the real one.
    public func openDemo() {
        if workspace.environment.sampleDisk != nil { workspace.open(.demo) } else { _ = AppOpener.open(OpenRequest(path: nil, demo: true, dryRun: false)) }
    }

    // MARK: Canvas events

    /// The callbacks every canvas shares.
    public func canvasEvents() -> CanvasEvents {
        CanvasEvents(
            onHover: { [weak self] node, point in
                self?.workspace.hover = node
                self?.hoverPoint = point
            },
            onClick: { [weak self] node, flags in
                self?.workspace.click(node, additive: flags.contains(.shift) || flags.contains(.command))
            },
            onDoubleClick: { [weak self] node in self?.workspace.zoomIn(node) },
            onContextMenu: { [weak self] node, event in self?.showContextMenu(node: node, event: event) },
            onFocusChanged: nil,
            onBrush: { [weak self] age, size in self?.applyBrush(age: age, size: size) })
    }

    /// Writes a Field brush into the query.
    private func applyBrush(age: ClosedRange<Float>, size: ClosedRange<Float>) {
        let clock = workspace.fieldClock == .modified ? "age" : "opened"
        workspace.setQuery(BrushQuery.apply(to: workspace.queryText, age: age, size: size, clock: clock))
    }

    /// Shows the native context menu for a node.
    private func showContextMenu(node: NodeID, event: NSEvent) {
        guard let tree = workspace.tree else { return }
        let menu = NSMenu()
        let nodes = workspace.isSelected(node) ? workspace.selectedNodes : [node]
        let name = tree.name(node)
        func add(_ title: String, _ action: @escaping () -> Void) { menu.addItem(ClosureItem(title: title, action: action)) }
        add("Keep") { [weak self] in _ = self?.workspace.mark(.keep, nodes: nodes) }
        add("Mark for removal") { [weak self] in _ = self?.workspace.mark(.remove, nodes: nodes) }
        add("Decide later") { [weak self] in _ = self?.workspace.mark(.later, nodes: nodes) }
        add("Clear mark") { [weak self] in _ = self?.workspace.mark(.none, nodes: nodes) }
        menu.addItem(.separator())
        if tree.isDirectory(node) { add("Zoom into \(name)") { [weak self] in self?.workspace.zoomIn(node) } }
        add("Review this") { [weak self] in
            if self?.workspace.startReview(nodes: nodes, title: name) == true { self?.previewOpen = false }
        }
        menu.addItem(.separator())
        add("Hide this") { [weak self] in self?.workspace.hide(.path, nodes: nodes) }
        add("Hide all named \(name)") { [weak self] in self?.workspace.hide(.name, nodes: nodes) }
        if !tree.isDirectory(node), (name as NSString).pathExtension.isEmpty == false {
            add("Hide all .\((name as NSString).pathExtension)") { [weak self] in self?.workspace.hide(.ext, nodes: nodes) }
        }
        menu.addItem(.separator())
        let path = tree.path(node)
        add("Copy path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(path, forType: .string) }
        if !isDemo { add("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) } }
        NSMenu.popUpContextMenu(menu, with: event, for: event.window?.contentView ?? NSView())
    }

    // MARK: Palette

    /// A row in the palette.
    public struct PaletteEntry: Identifiable {
        public var id: String { title }
        public var title: String
        public var key: String
        public var run: () -> Void
    }

    /// Commands matching `paletteQuery` in order, plus a jump when the query is an exact path in the scan.
    public func paletteEntries() -> [PaletteEntry] {
        let query = paletteQuery.trimmingCharacters(in: .whitespaces).lowercased()
        var entries = ShellCommand.catalog.filter { query.isEmpty || $0.title.lowercased().contains(query) }.map { info in
            PaletteEntry(title: info.title, key: info.key) { [weak self] in self?.sheet = nil; self?.perform(info.command) }
        }
        if query.hasPrefix("/"), let tree = workspace.tree, let node = tree.find(path: paletteQuery.trimmingCharacters(in: .whitespaces)) {
            let target = tree.isDirectory(node) ? node : tree.parent(node)
            entries.insert(PaletteEntry(title: "Go to \(tree.path(node))", key: "") { [weak self] in
                self?.sheet = nil
                self?.workspace.setFocus(target)
                self?.workspace.select([node])
            }, at: 0)
        }
        return entries
    }
}

/// A menu item that runs a closure.
public final class ClosureItem: NSMenuItem {
    private let action_: () -> Void
    private let enabledCheck: () -> Bool

    /// Creates an item. `enabled` is asked each time the menu opens.
    public init(title: String, key: String = "", modifiers: NSEvent.ModifierFlags = .command, enabled: @escaping () -> Bool = { true }, action: @escaping () -> Void) {
        action_ = action
        enabledCheck = enabled
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        target = self
    }

    @available(*, unavailable) required init(coder: NSCoder) { fatalError() }

    /// Runs the closure.
    @objc private func fire() { action_() }

    /// Enabled state for the menu system.
    @objc public func validateMenuItem(_ item: NSMenuItem) -> Bool { enabledCheck() }
}

import AppKit
import DYCore
import SwiftUI

/// Callbacks a canvas raises. All are optional and delivered on the main thread.
public struct CanvasEvents {
    public var onHover: ((NodeID?, CGPoint) -> Void)?
    public var onClick: ((NodeID, NSEvent.ModifierFlags) -> Void)?
    public var onDoubleClick: ((NodeID) -> Void)?
    public var onContextMenu: ((NodeID, NSEvent) -> Void)?
    public var onFocusChanged: ((NodeID) -> Void)?
    /// A drag region in data units: age range (log10 days) and size range (log10 bytes). Raised by the Field canvas.
    public var onBrush: ((ClosedRange<Float>, ClosedRange<Float>) -> Void)?

    /// Creates an empty set of callbacks.
    public init(onHover: ((NodeID?, CGPoint) -> Void)? = nil, onClick: ((NodeID, NSEvent.ModifierFlags) -> Void)? = nil,
                onDoubleClick: ((NodeID) -> Void)? = nil, onContextMenu: ((NodeID, NSEvent) -> Void)? = nil,
                onFocusChanged: ((NodeID) -> Void)? = nil,
                onBrush: ((ClosedRange<Float>, ClosedRange<Float>) -> Void)? = nil) {
        self.onBrush = onBrush
        self.onHover = onHover; self.onClick = onClick; self.onDoubleClick = onDoubleClick
        self.onContextMenu = onContextMenu; self.onFocusChanged = onFocusChanged
    }
}

/// A view that draws a `TreeLens`. Map, Rings and Field all conform, so the app can host any of them the same way.
public protocol DiskCanvas: NSView {
    var events: CanvasEvents { get set }
    /// Replaces what is shown. A new lens animates from the old layout when `animated`.
    func update(lens: TreeLens, style: NodeStyle, metric: Metric, selection: Set<NodeID>, animated: Bool)
    /// Moves the view to frame a node.
    func focus(on: NodeID, animated: Bool)
    /// Renders offscreen with no window, at `size` points and `scale` pixels per point.
    func snapshot(size: CGSize, scale: CGFloat) -> CGImage?
}

/// A generic SwiftUI host for any `DiskCanvas`. The canvas instance is owned by the caller so it survives view updates.
public struct DiskCanvasView: NSViewRepresentable {
    public var canvas: any DiskCanvas
    public var lens: TreeLens
    public var style: NodeStyle
    public var metric: Metric
    public var selection: Set<NodeID>
    public var focus: NodeID?
    public var events: CanvasEvents
    /// Bump to force a style refresh when only the arrays inside `style` changed.
    public var styleRevision: Int

    /// Creates a host for `canvas`.
    public init(canvas: any DiskCanvas, lens: TreeLens, style: NodeStyle, metric: Metric, selection: Set<NodeID> = [],
                focus: NodeID? = nil, events: CanvasEvents = CanvasEvents(), styleRevision: Int = 0) {
        self.canvas = canvas; self.lens = lens; self.style = style; self.metric = metric; self.selection = selection
        self.focus = focus; self.events = events; self.styleRevision = styleRevision
    }

    /// Remembers what was last pushed so unchanged updates cost nothing.
    public final class Coordinator {
        var lens: ObjectIdentifier?
        var metric: Metric?
        var mode: ColorMode?
        var selection: Set<NodeID> = []
        var revision = -1
        var focus: NodeID?
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeNSView(context: Context) -> NSView { canvas }

    public func updateNSView(_ view: NSView, context: Context) {
        var target = canvas
        target.events = events
        let coordinator = context.coordinator
        let changed = coordinator.lens != ObjectIdentifier(lens) || coordinator.metric != metric || coordinator.mode != style.colorMode
            || coordinator.selection != selection || coordinator.revision != styleRevision
        if changed {
            let animate = coordinator.lens != nil && coordinator.lens != ObjectIdentifier(lens)
            target.update(lens: lens, style: style, metric: metric, selection: selection, animated: animate)
            coordinator.lens = ObjectIdentifier(lens); coordinator.metric = metric; coordinator.mode = style.colorMode
            coordinator.selection = selection; coordinator.revision = styleRevision
        }
        if let focus, coordinator.focus != focus {
            target.focus(on: focus, animated: coordinator.focus != nil)
            coordinator.focus = focus
        }
    }
}

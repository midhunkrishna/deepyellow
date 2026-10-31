import AVFoundation
import AVKit
import AppKit
import DYCore
import DYLenses
import DYRender
import DYWorkspace
import SwiftUI

/// Renders one named scenario to a PNG without showing a window. Scenarios run on the sample disk, or on a real folder when the
/// session is `--read-only`.
///
/// The view hierarchy is drawn with `cacheDisplay`. Metal layers and `AVPlayerView` don't appear there, so a canvas is rendered with
/// its own `snapshot` and placed into the hierarchy as an image, and a decoded video frame is drawn over each player.
@MainActor
public enum ShotHarness {
    public static let width = 1600
    public static let height = 1000

    /// Every scenario name the harness knows.
    public static let names = ["app-map", "app-map-safety", "app-map-files", "app-things", "app-spectrum", "app-field", "app-rings", "app-browse",
                               "app-reclaim", "app-worklists", "app-review", "app-plan", "app-ledger", "app-palette", "app-welcome",
                               "app-preview-video", "app-preview-image"]

    /// Renders `name` to `outPath`. `openPath` is the real folder to scan for a read-only session. Returns the process exit code.
    public static func run(name: String, outPath: String?, shell: ShellState, openPath: String? = nil) async -> Int32 {
        guard names.contains(name), let outPath else {
            FileHandle.standardError.write(Data("shot: need --shot <\(names.joined(separator: "|"))> and --out <file>\n".utf8))
            return 64
        }
        if !shell.isDemo, openPath == nil, name != "app-welcome" {
            FileHandle.standardError.write(Data("shot: a read-only shot needs a folder to scan\n".utf8))
            return 64
        }
        shell.isShot = true
        let host = NSHostingView(rootView: RootView(shell: shell))
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))

        if shell.isDemo { await DemoMedia.ensure(in: DemoMedia.folder(in: shell.workspace.environment.dataDirectory)) }
        if name == "app-welcome" {
            shell.recents = ["/Users/demo/Developer", "/Users/demo/Movies", "/Volumes/Backup"]
        } else {
            await prepare(shell, openPath: openPath)
            if shell.isDemo || name == "app-plan" { await stage(shell.workspace) }
        }
        await scenario(name, shell)
        await pause(name == "app-review" || name.hasPrefix("app-preview") ? 3000 : 900)
        if let kind = canvasLens(name), let canvas = shell.canvases.canvas(for: kind), canvas.bounds.width > 10 {
            if kind == .field { shell.syncField(); await pause(300) }
            if let image = canvas.snapshot(size: canvas.bounds.size, scale: 2) {
                shell.shotSnapshot = NSImage(cgImage: image, size: canvas.bounds.size)
                await pause(500)
            }
        }
        host.layoutSubtreeIfNeeded()
        if ProcessInfo.processInfo.environment["DY_SHOT_DEBUG"] != nil { dump(host, depth: 0) }
        let frame = await currentVideoFrame(shell)
        guard let png = capture(host, videoFrame: frame) else {
            FileHandle.standardError.write(Data("shot: capture failed\n".utf8))
            return 1
        }
        do { try png.write(to: URL(fileURLWithPath: outPath)) } catch {
            FileHandle.standardError.write(Data("shot: \(error.localizedDescription)\n".utf8))
            return 1
        }
        return 0
    }

    /// The canvas lens a scenario shows, if any.
    private static func canvasLens(_ name: String) -> LensKind? {
        switch name {
        case "app-map", "app-map-safety", "app-map-files", "app-plan", "app-ledger", "app-palette", "app-preview-video", "app-preview-image": .map
        case "app-field": .field
        case "app-rings": .rings
        default: nil
        }
    }

    /// Waits on the run loop without blocking it.
    private static func pause(_ milliseconds: Int) async { try? await Task.sleep(for: .milliseconds(milliseconds)) }

    /// Opens the sample disk, or the real folder, and waits for the scan and the analyses.
    private static func prepare(_ shell: ShellState, openPath: String?) async {
        let workspace = shell.workspace
        if shell.isDemo { workspace.open(.demo) } else if let openPath { workspace.open(.path(openPath), useCache: false) }
        for _ in 0..<300 {
            await workspace.settle()
            let running = workspace.analysis.values.contains { if case .running = $0 { true } else { false } }
            if workspace.tree != nil, workspace.scanPhase == .finished, !running, workspace.reclaimReport != nil { break }
            await pause(100)
        }
        await workspace.settle()
    }

    /// The first node called `name`.
    private static func node(_ name: String, in workspace: Workspace) -> NodeID? {
        guard let tree = workspace.tree else { return nil }
        return (0..<tree.count).map(NodeID.init).first { tree.name($0) == name }
    }

    /// The largest files of one kind, biggest first.
    private static func largestFiles(of kind: FileKind, in workspace: Workspace, limit: Int) -> [NodeID] {
        guard let tree = workspace.tree else { return [] }
        let files = (1..<max(1, tree.count)).map(NodeID.init).filter { !tree.isDirectory($0) && tree.kind($0) == kind }
        return Array(files.sorted { tree.allocated($0) > tree.allocated($1) }.prefix(limit))
    }

    /// Stages a few items and sets decisions so every sample-disk image shows the same story.
    private static func stage(_ workspace: Workspace) async {
        for (name, decision) in [("DerivedData", Decision.remove), ("Caches", .remove), ("node_modules", .remove), ("Docker.raw", .remove),
                                 ("Taxes", .keep), ("Iceland 2023", .later)] {
            if let id = node(name, in: workspace) { _ = workspace.mark(decision, nodes: [id]) }
        }
        workspace.clearSelection()
        await workspace.settle()
    }

    /// Puts the app into the state a scenario describes.
    private static func scenario(_ name: String, _ shell: ShellState) async {
        let workspace = shell.workspace
        guard name != "app-welcome" else { return }
        let real = !shell.isDemo
        switch name {
        case "app-map":
            workspace.setLens(.map)
            if let first = largestFiles(of: .video, in: workspace, limit: 1).first ?? workspace.tree.map({ $0.children(0).lowerBound }) { workspace.select([first]) }
            if !real { if let movies = node("Movies", in: workspace) { workspace.select([movies]) }; workspace.hover = node("Iceland 2023", in: workspace) }
        case "app-map-safety":
            workspace.setColorMode(.safety)
            if let caches = node("Caches", in: workspace) { workspace.select([caches]) }
            workspace.hover = node("DerivedData", in: workspace)
        case "app-map-files":
            workspace.setMetric(.files)
            workspace.hover = node("node_modules", in: workspace)
        case "app-things": workspace.setLens(.things)
        case "app-spectrum": workspace.setLens(.spectrum)
        case "app-field": workspace.setLens(.field)
        case "app-rings":
            workspace.setLens(.rings)
            if let library = workspace.tree?.find(path: "/Users/demo/Library") { workspace.select([library]) }
        case "app-browse":
            workspace.setLens(.browse)
            if let dev = node("Developer", in: workspace) { workspace.select([dev]) }
        case "app-reclaim": workspace.setLens(.reclaim)
        case "app-worklists":
            workspace.setLens(.reclaim)
            workspace.findDuplicates()
            for _ in 0..<100 { await workspace.settle(); if workspace.duplicateReport != nil { break }; await pause(100) }
        case "app-review":
            workspace.setLens(.reclaim)
            let videos = largestFiles(of: .video, in: workspace, limit: 9)
            if !videos.isEmpty, workspace.startReview(nodes: videos, title: "Footage to look through") {
                _ = workspace.reviewVerdict(.keep)
                _ = workspace.reviewVerdict(.remove)
            }
        case "app-plan":
            workspace.setLens(.map)
            shell.sheet = .plan
        case "app-ledger":
            workspace.setLens(.map)
            if let id = node("node_modules", in: workspace) { workspace.hide(.name, nodes: [id]) }
            workspace.dismissNotice()
            shell.sheet = .ledger
        case "app-palette":
            workspace.setLens(.map)
            shell.paletteQuery = "re"
            shell.sheet = .palette
        case "app-preview-video", "app-preview-image":
            workspace.setLens(.map)
            let kind: FileKind = name == "app-preview-video" ? .video : .image
            if let file = largestFiles(of: kind, in: workspace, limit: 1).first {
                workspace.select([file])
                workspace.hover = nil
                shell.previewOpen = true
            }
        default: break
        }
        await workspace.settle()
        if name == "app-review" { workspace.dismissNotice() }
    }

    /// A decoded frame from the video that is currently previewed or under review, if any.
    private static func currentVideoFrame(_ shell: ShellState) async -> CGImage? {
        let workspace = shell.workspace
        guard let item = workspace.review != nil ? workspace.reviewPreview : (shell.previewOpen ? workspace.selectionPreview : nil), item.kind == .video else { return nil }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: item.url))
        generator.appliesPreferredTrackTransform = true
        return try? await generator.image(at: CMTime(seconds: 2, preferredTimescale: 600)).image
    }

    /// Prints the view tree below `view`, for diagnosing captures.
    private static func dump(_ view: NSView, depth: Int) {
        let name = String(describing: type(of: view))
        if depth < 14, name.contains("Image") || name.contains("Scroll") || name.contains("Player") || depth < 3 {
            FileHandle.standardError.write(Data("\(String(repeating: " ", count: depth))\(name) \(view.frame) hidden=\(view.isHiddenOrHasHiddenAncestor)\((view as? NSImageView).map { " image=\(String(describing: $0.image?.size))" } ?? "")\n".utf8))
        }
        for sub in view.subviews { dump(sub, depth: depth + 1) }
    }

    /// Every `AVPlayerView` below `view`.
    private static func playerViews(in view: NSView) -> [AVPlayerView] {
        (view as? AVPlayerView).map { [$0] } ?? view.subviews.flatMap { playerViews(in: $0) }
    }

    /// Captures the hierarchy, draws `videoFrame` over each player, and scales to exactly 1600 by 1000 pixels as PNG data.
    private static func capture(_ host: NSView, videoFrame: CGImage?) -> Data? {
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let source = rep.cgImage,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        if let videoFrame {
            for player in playerViews(in: host) {
                var rect = player.convert(player.bounds, to: host)
                if host.isFlipped { rect.origin.y = host.bounds.height - rect.maxY }
                context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
                context.fill(rect)
                let scale = min(rect.width / CGFloat(videoFrame.width), rect.height / CGFloat(videoFrame.height))
                let size = CGSize(width: CGFloat(videoFrame.width) * scale, height: CGFloat(videoFrame.height) * scale)
                context.draw(videoFrame, in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
            }
        }
        guard let scaled = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: scaled).representation(using: .png, properties: [:])
    }
}

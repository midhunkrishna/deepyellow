import AVKit
import DYCore
import PDFKit
import Quartz
import SwiftUI

/// Video with no system chrome and the filmstrip scrubber.
struct VideoPreview: View {
    @ObservedObject var controller: PreviewController

    var body: some View {
        VStack(spacing: 0) {
            PlayerLayerView(player: controller.player)
                .onTapGesture { controller.togglePlay() }
            FilmstripView(model: controller.filmstrip, playhead: controller.playhead) { controller.seek(toFraction: $0) }
                .frame(height: 54).padding(8)
        }
    }
}

/// An `AVPlayerView` with controls turned off.
struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer?

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) { view.player = player }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) { view.player = nil }
}

/// A strip of frames with a gold playhead. Hover shows the frame under the cursor; click seeks.
struct FilmstripView: View {
    @ObservedObject var model: FilmstripModel
    let playhead: Double
    let seek: (Double) -> Void
    @State private var hover: Double?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                HStack(spacing: 1) {
                    ForEach(model.frames.indices, id: \.self) { index in
                        Group {
                            if let frame = model.frames[index] {
                                Image(decorative: frame, scale: 1).resizable().aspectRatio(contentMode: .fill)
                            } else { Theme.surface }
                        }
                        .frame(maxWidth: .infinity).clipped()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                Rectangle().fill(Theme.accent).frame(width: 2).offset(x: geo.size.width * playhead)
                if let hover, let frame = model.hoverFrame {
                    Image(decorative: frame, scale: 1).resizable().aspectRatio(contentMode: .fit)
                        .frame(height: 90).overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.hairline))
                        .offset(x: min(max(geo.size.width * hover - 80, 0), max(geo.size.width - 160, 0)), y: -100)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    hover = Double(point.x / max(geo.size.width, 1))
                    model.scrub(to: hover)
                case .ended:
                    hover = nil
                    model.scrub(to: nil)
                }
            }
            .gesture(DragGesture(minimumDistance: 0).onChanged { seek(Double($0.location.x / max(geo.size.width, 1))) })
        }
    }
}

/// Image at screen size, switching to the full decode once zoomed. Pan and zoom use `NSScrollView`.
struct ImagePreview: View {
    @ObservedObject var controller: PreviewController
    let image: CGImage

    var body: some View {
        ZoomableImage(image: controller.fullImage ?? image, scale: controller.zoomScale) { controller.setZoom($0) }
    }
}

/// An `NSScrollView` hosting the image, with pinch magnification reported back.
struct ZoomableImage: NSViewRepresentable {
    let image: CGImage
    let scale: CGFloat
    let onMagnify: (CGFloat) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.allowsMagnification = true
        scroll.minMagnification = 1
        scroll.maxMagnification = 8
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        let imageView = NSImageView()
        imageView.autoresizingMask = [.width, .height]
        scroll.documentView = imageView
        context.coordinator.onMagnify = onMagnify
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.ended(_:)),
                                               name: NSScrollView.didEndLiveMagnifyNotification, object: scroll)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.onMagnify = onMagnify
        if let view = scroll.documentView as? NSImageView {
            view.image = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            view.frame = scroll.contentView.bounds
            view.imageScaling = .scaleProportionallyUpOrDown
        }
        if abs(scroll.magnification - scale) > 0.01, scale == 1 { scroll.magnification = 1 }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        var onMagnify: (CGFloat) -> Void = { _ in }
        /// Reports the pinch result so the controller can decode the full image.
        @objc func ended(_ note: Notification) {
            if let scroll = note.object as? NSScrollView { onMagnify(scroll.magnification) }
        }
    }
}

/// A waveform drawn from peaks in the accent colour.
struct WaveformView: View {
    let waveform: Waveform

    var body: some View {
        Canvas { context, size in
            let count = waveform.peaks.count
            guard count > 0 else { return }
            let step = size.width / CGFloat(count)
            for (index, peak) in waveform.peaks.enumerated() {
                let height = max(2, CGFloat(peak) * size.height * 0.8)
                let rect = CGRect(x: CGFloat(index) * step + 0.5, y: (size.height - height) / 2, width: max(1, step - 1), height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(Theme.accent.opacity(0.85)))
            }
        }
        .padding(20)
        .overlay(alignment: .bottomTrailing) {
            Text(String(format: "%d:%02d", Int(waveform.duration) / 60, Int(waveform.duration) % 60))
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.muted).padding(8)
        }
    }
}

/// PDFKit viewer.
struct PDFPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.backgroundColor = .clear
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
    }

    static func dismantleNSView(_ view: PDFView, coordinator: ()) { view.document = nil }
}

/// The first 256 KB of a text file in monospaced type.
struct TextPreview: View {
    let text: String

    var body: some View {
        ScrollView {
            Text(text).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.primary)
                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(14)
        }
    }
}

/// QuickLook fallback.
struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? NSURL) as URL? != url { view.previewItem = url as NSURL }
    }

    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) {
        view.previewItem = nil
        view.close()
    }
}

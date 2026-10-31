import DYCore
import SwiftUI

/// The right-hand preview: media first, slim metadata underneath.
public struct PreviewPane: View {
    public let item: PreviewItem?
    @ObservedObject public var controller: PreviewController

    /// Creates a pane for an item. The controller loads it and releases the previous one.
    public init(item: PreviewItem?, controller: PreviewController) {
        self.item = item
        self.controller = controller
    }

    public var body: some View {
        VStack(spacing: 0) {
            Group {
                if let item { media(item) } else { Text("Nothing selected").foregroundStyle(Theme.muted) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let item { MetadataBar(item: item) }
        }
        .background(Theme.background)
        .task(id: item) { await controller.show(item) }
        .onDisappear { controller.release() }
    }

    /// Picks the renderer for the loaded content.
    @ViewBuilder private func media(_ item: PreviewItem) -> some View {
        switch controller.content {
        case .empty: ProgressView().controlSize(.small)
        case .dataless: DatalessView(item: item) { controller.requestDownload() }
        case .directory(let children): DirectoryView(children: children)
        case .video: VideoPreview(controller: controller)
        case .image(let image): ImagePreview(controller: controller, image: image)
        case .audio(let wave): WaveformView(waveform: wave)
        case .pdf(let url): PDFPreview(url: url)
        case .text(let text): TextPreview(text: text)
        case .quickLook(let url): QuickLookPreview(url: url)
        }
    }
}

/// Name, size and age on one slim line.
struct MetadataBar: View {
    let item: PreviewItem

    var body: some View {
        HStack(spacing: 10) {
            Text(item.name).lineLimit(1).truncationMode(.middle).foregroundStyle(Theme.primary)
            Spacer(minLength: 8)
            Text(Format.bytes(item.size)).foregroundStyle(Theme.secondary)
            if let modified = item.modified {
                Text(Format.age(Int32(clamping: Int(modified.timeIntervalSince1970)))).foregroundStyle(Theme.muted)
            }
        }
        .font(.system(size: 12).monospacedDigit())
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

/// A placeholder notice with an explicit Download button.
struct DatalessView: View {
    let item: PreviewItem
    let download: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "icloud").font(.system(size: 34)).foregroundStyle(Theme.muted)
            Text("Stored in iCloud").foregroundStyle(Theme.secondary)
            Text("Previewing would download \(Format.bytes(item.size)).").font(.caption).foregroundStyle(Theme.muted)
            Button("Download", action: download).buttonStyle(.bordered).tint(Theme.accent)
        }
    }
}

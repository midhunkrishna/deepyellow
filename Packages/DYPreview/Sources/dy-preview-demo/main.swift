import AppKit
import DYCore
import DYPreview
import SwiftUI

/// Builds the five fixtures in a temp directory and returns items for them.
func makeItems() async throws -> [PreviewItem] {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dy-preview-demo-\(getpid())")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let files: [(String, FileKind)] = [("clip.mov", .video), ("art.png", .image), ("tone.wav", .audio),
                                       ("doc.pdf", .document), ("notes.txt", .document)]
    try await PreviewFixtures.video(at: dir.appendingPathComponent("clip.mov"))
    try PreviewFixtures.image(at: dir.appendingPathComponent("art.png"))
    try PreviewFixtures.audio(at: dir.appendingPathComponent("tone.wav"))
    try PreviewFixtures.pdf(at: dir.appendingPathComponent("doc.pdf"))
    try PreviewFixtures.text(at: dir.appendingPathComponent("notes.txt"), bytes: 4000)
    var items = files.map { name, kind -> PreviewItem in
        let url = dir.appendingPathComponent(name)
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
        return PreviewItem(url: url, name: name, size: size, modified: Date(), kind: kind)
    }
    let children = items.map { PreviewChild(url: $0.url, name: $0.name, size: $0.size, kind: $0.kind, isDirectory: false) }
    items.append(PreviewItem(url: dir, name: "folder", size: children.reduce(0) { $0 + $1.size }, kind: .other,
                             isDirectory: true, largestChildren: children))
    return items
}

struct DemoView: View {
    let items: [PreviewItem]
    @State private var index = 0
    @StateObject private var controller = PreviewController()

    var body: some View {
        HStack(spacing: 0) {
            List(items.indices, id: \.self, selection: Binding(get: { index }, set: { index = $0 ?? 0 })) {
                Text(items[$0].name)
            }.frame(width: 160)
            PreviewPane(item: items[index], controller: controller)
        }
        .onChange(of: index) { _, new in controller.prepare(Array(items.dropFirst(new + 1))) }
        .onKeyPress(.space) { controller.togglePlay(); return .handled }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let items = try await makeItems()
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
                      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
window.title = "DYPreview demo"
window.appearance = NSAppearance(named: .darkAqua)
window.contentView = NSHostingView(rootView: DemoView(items: items))
window.center()
window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
app.run()

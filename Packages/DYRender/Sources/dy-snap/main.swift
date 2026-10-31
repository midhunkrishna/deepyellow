import AppKit
import DYCore
import DYRender
import ImageIO
import UniformTypeIdentifiers

/// Command-line options for `dy-snap`.
struct Options {
    var canvas = "map"
    var focus: String?
    var color: ColorMode = .kind
    var metric: Metric = .bytes
    var out = "snap.png"
    var width = 1600, height = 1000
    var scale: CGFloat = 2
    var bench = false
    var gallery: String?
    var nodes = 5_000_000
    var frames = 360
    var treeScale = 1.0
    var points = 2_000_000
}

/// Parses `--flag value` pairs. Unknown flags stop the run with a usage message.
func parse(_ arguments: [String]) -> Options {
    var options = Options()
    var index = 1
    func next() -> String { index += 1; return index < arguments.count ? arguments[index] : "" }
    while index < arguments.count {
        switch arguments[index] {
        case "--canvas": options.canvas = next()
        case "--focus": options.focus = next()
        case "--color": options.color = ["age": .age, "safety": .safety, "decision": .decision][next()] ?? .kind
        case "--metric": options.metric = next() == "files" ? .files : .bytes
        case "--out": options.out = next()
        case "--size":
            let parts = next().split(separator: "x").compactMap { Int($0) }
            if parts.count == 2 { options.width = parts[0]; options.height = parts[1] }
        case "--scale": options.scale = CGFloat(Double(next()) ?? 2)
        case "--bench": options.bench = true
        case "--gallery": options.gallery = next()
        case "--nodes": options.nodes = Int(next()) ?? options.nodes
        case "--frames": options.frames = Int(next()) ?? options.frames
        case "--tree-scale": options.treeScale = Double(next()) ?? 1
        case "--points": options.points = Int(next()) ?? options.points
        default:
            print("usage: dy-snap --canvas map [--focus <path>] [--color kind|age|safety|decision] [--metric bytes|files] [--size WxH] [--scale 2] --out x.png")
            print("       dy-snap --gallery <dir>    dy-snap --bench [--nodes N] [--frames N]")
            exit(2)
        }
        index += 1
    }
    return options
}

/// Advice and verdicts for the synthetic tree, assigned by name and inherited downward like the real engines do.
enum DemoStyle {
    static let safe: Set<String> = ["Caches", "DerivedData", "Logs", ".DS_Store", "__pycache__"]
    static let rebuild: Set<String> = ["node_modules", "target", ".venv", "iOS DeviceSupport", "Devices", "Backup"]
    static let review: Set<String> = ["Documents", "Movies", "Pictures", "Music", "Downloads", "Developer"]
    static let never: Set<String> = ["Photos Library.photoslibrary", "System", "Applications"]
    static let remove: Set<String> = ["old-mobile-app", "portfolio-2021", "Xcode_15.2.xip", "old-backup.zip", "Install macOS.pkg", "iOS DeviceSupport", "Exports", "Ubuntu-24.04.iso"]
    static let keep: Set<String> = ["Photos Library.photoslibrary", "thesis-final.pages", "wedding-final-master.mov", "Taxes", "storefront"]
    static let later: Set<String> = ["interview-raw.mp4", "ml-experiments", "Docker.raw", "datasets", "Iceland 2023"]

    /// Builds a style for `tree` in the given colour mode.
    static func make(tree: FileTree, lens: TreeLens, mode: ColorMode) -> NodeStyle {
        var safety = [UInt8](repeating: 0, count: tree.count)
        var decisions = [UInt8](repeating: 0, count: tree.count)
        for node in 0..<tree.count {
            let name = tree.name(NodeID(node))
            let parent = node == 0 ? -1 : Int(tree.parent(NodeID(node)))
            var tier: SafetyTier = parent >= 0 ? SafetyTier(rawValue: safety[parent]) ?? .unknown : .unknown
            if tier != .never {
                if never.contains(name) || name.hasSuffix(".app") { tier = .never }
                else if safe.contains(name) { tier = .safe }
                else if rebuild.contains(name) { tier = .rebuild }
                else if review.contains(name) && tier == .unknown { tier = .review }
            }
            safety[node] = tier.rawValue
            var decision: UInt8 = parent >= 0 ? decisions[parent] : 0
            if remove.contains(name) { decision = Decision.remove.rawValue }
            if keep.contains(name) { decision = Decision.keep.rawValue }
            if later.contains(name) { decision = Decision.later.rawValue }
            decisions[node] = decision
        }
        return NodeStyle(colorMode: mode, decisions: decisions, safety: safety, dominantKind: lens.dominantKinds(), now: SyntheticTree.referenceNow)
    }
}

/// Writes an image as PNG.
func writePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    print("wrote \(path) \(image.width)x\(image.height)")
}

/// The Field's raw arrays for every file of `lens`: log10 age in days, log10 bytes, kind and node.
func fieldPoints(tree: FileTree, lens: TreeLens) -> (positions: [SIMD2<Float>], kinds: [UInt8], nodes: [NodeID], age: ClosedRange<Float>, size: ClosedRange<Float>) {
    var positions: [SIMD2<Float>] = [], kinds: [UInt8] = [], nodes: [NodeID] = []
    for node in 0..<tree.count where tree.columns.childCount[node] == 0 && !tree.isDirectory(NodeID(node)) && lens.size[node] > 0 {
        // Demo data only: soften the generator's hard age bands with a deterministic jitter so the field reads like real disks.
        let hash = Double((UInt32(truncatingIfNeeded: node) &* 2_654_435_761) >> 8 & 0xFFFF) / 65_535
        let days = max(Double(SyntheticTree.referenceNow - tree.columns.modified[node]) / 86_400 * pow(10, (hash - 0.5) * 0.5), 0.5)
        positions.append(SIMD2(Float(log10(days)), Float(log10(Double(max(lens.size[node], 1))))))
        kinds.append(tree.columns.kind[node]); nodes.append(NodeID(node))
    }
    let xs = positions.map(\.x), ys = positions.map(\.y)
    return (positions, kinds, nodes, (xs.min() ?? 0)...(xs.max() ?? 1), (ys.min() ?? 0)...(ys.max() ?? 1))
}

/// Builds the canvas named by `--canvas`.
func makeCanvas(_ options: Options, tree: FileTree, lens: TreeLens) -> any DiskCanvas {
    let frame = NSRect(x: 0, y: 0, width: options.width, height: options.height)
    switch options.canvas {
    case "rings": return RingsCanvas(frame: frame)
    case "field":
        let canvas = FieldCanvas(frame: frame)
        let data = fieldPoints(tree: tree, lens: lens)
        canvas.setPoints(positions: data.positions, kinds: data.kinds, nodes: data.nodes, ageRange: data.age, sizeRange: data.size)
        return canvas
    default: return MapCanvas(frame: frame)
    }
}

/// Renders one snapshot of the synthetic tree.
func renderShot(tree: FileTree, lens: TreeLens, options: Options, focus: String?, out: String) {
    let canvas = makeCanvas(options, tree: tree, lens: lens)
    let style = DemoStyle.make(tree: tree, lens: lens, mode: options.color)
    canvas.update(lens: lens, style: style, metric: options.metric, selection: [], animated: false)
    if let focus {
        guard let node = tree.find(path: focus) else { print("no such path in the synthetic tree: \(focus)"); return }
        canvas.focus(on: node, animated: false)
    }
    guard let image = canvas.snapshot(size: CGSize(width: options.width, height: options.height), scale: options.scale) else {
        print("snapshot failed (no Metal device?)"); exit(1)
    }
    writePNG(image, to: out)
}

/// Measures the Field with `count` synthetic points: clustered swarms plus a few giants.
func runFieldBench(_ options: Options) {
    var positions: [SIMD2<Float>] = [], kinds: [UInt8] = [], nodes: [NodeID] = []
    var state: UInt64 = 7
    func unit() -> Float { state = state &* 6364136223846793005 &+ 1442695040888963407; return Float(state >> 40) / Float(1 << 24) }
    func gauss() -> Float { (unit() + unit() + unit() + unit() - 2) * 1.7 }
    let centres: [(Float, Float, Float)] = [(1.2, 3.8, 0.35), (2.4, 4.6, 0.5), (2.9, 5.4, 0.4), (0.6, 4.1, 0.3), (3.0, 6.8, 0.3), (1.8, 7.5, 0.6)]
    for index in 0..<options.points {
        let c = centres[index % centres.count]
        positions.append(SIMD2(min(max(c.0 + gauss() * c.2, -0.3), 3.6), min(max(c.1 + gauss() * c.2 * 1.6, 2), 11)))
        kinds.append(UInt8(index % 8)); nodes.append(NodeID(index % 1_000_000))
    }
    let canvas = FieldCanvas(frame: NSRect(x: 0, y: 0, width: options.width, height: options.height))
    canvas.setPoints(positions: positions, kinds: kinds, nodes: nodes, ageRange: -0.3...3.6, sizeRange: 2...11)
    let size = CGSize(width: options.width, height: options.height)
    _ = canvas.renderOffscreen(size: size, scale: options.scale, readBack: false)
    var gpu: [Double] = [], wall: [Double] = []
    for pass in 0..<(options.frames * 2) {
        if pass < options.frames { canvas.invalidateStars() }
        let begin = CFAbsoluteTimeGetCurrent()
        let result = canvas.renderOffscreen(size: size, scale: options.scale, readBack: false)
        wall.append((CFAbsoluteTimeGetCurrent() - begin) * 1000); gpu.append(result.gpuSeconds * 1000)
    }
    let split = options.frames
    for (name, values) in [("field full redraw gpu", Array(gpu[..<split])), ("field full redraw wall", Array(wall[..<split])), ("field cached (brush/hover) gpu", Array(gpu[split...])), ("field cached wall", Array(wall[split...]))] {
        let sorted = values.sorted()
        print(String(format: "%@ (%d points, %dx%d px): mean %.2f ms  p50 %.2f  p95 %.2f  max %.2f", name, options.points, Int(size.width * options.scale), Int(size.height * options.scale),
                     values.reduce(0, +) / Double(values.count), sorted[sorted.count / 2], sorted[Int(Double(sorted.count) * 0.95)], sorted.last!))
    }
}

/// Renders the standard set of screenshots.
func runGallery(_ directory: String, base: Options) {
    let tree = SyntheticTree.make(scale: base.treeScale)
    let lens = TreeLens(tree: tree)
    var shots: [(String, ColorMode, Metric, String?)] = [
        ("map-bytes-overview", .kind, .bytes, nil),
        ("map-color-age", .age, .bytes, nil),
        ("map-color-safety", .safety, .bytes, nil),
        ("map-color-decision", .decision, .bytes, nil),
        ("map-zoom-developer", .kind, .bytes, "/Users/demo/Developer"),
        ("map-zoom-dust", .kind, .bytes, "/Users/demo/Developer/storefront/node_modules"),
        ("map-zoom-library-safety", .safety, .bytes, "/Users/demo/Library"),
        ("map-files-metric", .kind, .files, nil),
    ]
    shots.append(("map-files-zoom", .kind, .files, "/Users/demo/Developer"))
    for shot in shots {
        var options = base
        options.scale = 1
        options.color = shot.1
        options.metric = shot.2
        renderShot(tree: tree, lens: lens, options: options, focus: shot.3, out: "\(directory)/\(shot.0).png")
    }
}

/// Measures frame times while zooming into dense dust of a large tree and back out.
func runBench(_ options: Options) {
    let started = Date()
    let tree = SyntheticTree.make(scale: Double(options.nodes) / 50_000)
    print("tree: \(tree.count) nodes built in \(String(format: "%.1f", Date().timeIntervalSince(started))) s")
    let lens = TreeLens(tree: tree)
    let canvas = MapCanvas(frame: NSRect(x: 0, y: 0, width: options.width, height: options.height))
    canvas.update(lens: lens, style: NodeStyle(colorMode: .kind, now: SyntheticTree.referenceNow), metric: .bytes, selection: [], animated: false)
    let size = CGSize(width: options.width, height: options.height)
    _ = canvas.renderOffscreen(size: size, scale: options.scale, readBack: false)
    let model = canvas.model
    guard let layout = model.layout else { print("no layout"); return }
    let node = tree.find(path: "/Users/demo/Pictures/Photos Library.photoslibrary/originals") ?? 0
    let target = layout.rect(of: node) ?? layout.worldRect
    let viewPx = SIMD2(Double(options.width) * Double(options.scale), Double(options.height) * Double(options.scale))
    let ppu = model.camera.pixelsPerUnit(viewWidth: viewPx.x, world: layout.worldRect)
    let anchor = SIMD2((target.x + target.w / 2 - model.camera.centerX) * ppu + viewPx.x / 2, (target.y + target.h / 2 - model.camera.centerY) * ppu + viewPx.y / 2)
    let finalScale = max(1.0, min(Camera.maxScale, 6 * viewPx.x / (target.w * ppu)))
    let half = options.frames / 2
    let factor = pow(finalScale, 1.0 / Double(half))
    var typeAreas: [[Float]] = []
    var bestDust: Float = 0
    var dustDump: [TileInstance] = []
    var diag: [(ms: Double, overdraw: Double, dust: Int, tiles: Int)] = []
    var cpu: [Double] = [], gpu: [Double] = [], wall: [Double] = [], tiles = 0
    for frame in 0..<options.frames {
        model.zoom(by: frame < half ? factor : 1 / factor, anchorPx: anchor, viewPx: viewPx)
        let begin = CFAbsoluteTimeGetCurrent()
        let result = canvas.renderOffscreen(size: size, scale: options.scale, readBack: false)
        wall.append((CFAbsoluteTimeGetCurrent() - begin) * 1000)
        cpu.append(canvas.lastSceneSeconds * 1000)
        gpu.append(result.gpuSeconds * 1000)
        tiles = max(tiles, canvas.lastCounts.tiles)
        var area: Float = 0, dust = 0
        var typeArea: [Float] = [0, 0, 0]
        for t in model.lastScene.tiles {
            let w = min(t.rect.x + t.rect.z, Float(viewPx.x)) - max(t.rect.x, 0), h = min(t.rect.y + t.rect.w, Float(viewPx.y)) - max(t.rect.y, 0)
            if w > 0 && h > 0 { area += w * h; typeArea[Int(t.params.y)] += w * h / Float(viewPx.x * viewPx.y) }
            if t.params.y == 2 { dust += 1 }
        }
        typeAreas.append(typeArea)
        if typeArea[2] > bestDust { bestDust = typeArea[2]; dustDump = model.lastScene.tiles.filter { $0.params.y == 2 } }
        diag.append((result.gpuSeconds * 1000, Double(area / Float(viewPx.x * viewPx.y)), dust, model.lastScene.tiles.count))
    }
    if let worst = diag.indices.max(by: { diag[$0].ms < diag[$1].ms }) { print("worst frame type coverage (tile, plate, dust):", typeAreas[worst]) }
    for t in dustDump.prefix(12) { print(String(format: "dust rect %.0f,%.0f %.0fx%.0f alpha %.2f depth %.0f density %.2f", t.rect.x, t.rect.y, t.rect.z, t.rect.w, t.color.w, t.extra.y, t.params.z)) }
    for d in diag.sorted(by: { $0.ms > $1.ms }).prefix(4) { print(String(format: "slow frame: %.0f ms overdraw %.1fx dust tiles %d of %d", d.ms, d.overdraw, d.dust, d.tiles)) }
    func stats(_ name: String, _ values: [Double]) {
        let sorted = values.sorted()
        let mean = values.reduce(0, +) / Double(values.count)
        print(String(format: "%@: mean %.2f ms  p50 %.2f  p95 %.2f  max %.2f", name, mean, sorted[sorted.count / 2], sorted[Int(Double(sorted.count) * 0.95)], sorted.last!))
    }
    print("zoom 1x to \(Int(finalScale))x and back, \(options.frames) frames at \(Int(viewPx.x))x\(Int(viewPx.y)) px, peak \(tiles) tiles")
    stats("scene build (cpu)", cpu)
    stats("gpu", gpu)
    stats("frame wall (cpu+gpu+sync)", wall)
    let busy = zip(cpu, gpu).map { max($0, $1) }
    print(String(format: "pipelined estimate: %.0f fps at p95 (budget 120 fps = 8.33 ms)", 1000 / busy.sorted()[Int(Double(busy.count) * 0.95)]))
}

_ = NSApplication.shared
let options = parse(CommandLine.arguments)
if options.bench {
    if options.canvas == "field" { runFieldBench(options) } else { runBench(options) }
} else if let gallery = options.gallery {
    runGallery(gallery, base: options)
} else {
    let tree = SyntheticTree.make(scale: options.canvas == "field" && options.treeScale == 1 ? 6 : options.treeScale)
    renderShot(tree: tree, lens: TreeLens(tree: tree), options: options, focus: options.focus, out: options.out)
}

// Renders the DeepYellow app icon: a tiny treemap in deep yellow on warm near-black,
// inside a macOS squircle. Usage: swift scripts/make-icon.swift <output-dir>
// Writes <output-dir>/AppIcon.iconset/*.png plus web-icon.png (512) and web-favicon.png (64).
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Builds an sRGB colour from a 0xRRGGBB value.
func hex(_ value: UInt32, alpha: CGFloat = 1) -> CGColor {
    let r = CGFloat((value >> 16) & 0xFF) / 255
    let g = CGFloat((value >> 8) & 0xFF) / 255
    let b = CGFloat(value & 0xFF) / 255
    return CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [r, g, b, alpha])!
}

/// A superellipse path approximating the macOS icon squircle inside `rect`.
func squircle(in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let n: CGFloat = 5
    let steps = 360
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = rect.midX + rect.width / 2 * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = rect.midY + rect.height / 2 * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

/// Treemap tiles in unit coordinates (x, y, w, h) with their fill colour, largest first.
let tiles: [(CGRect, UInt32)] = [
    (CGRect(x: 0.00, y: 0.00, width: 0.56, height: 1.00), 0xFFB800),
    (CGRect(x: 0.56, y: 0.00, width: 0.44, height: 0.46), 0xD99A00),
    (CGRect(x: 0.56, y: 0.46, width: 0.24, height: 0.54), 0x9C6F00),
    (CGRect(x: 0.80, y: 0.46, width: 0.20, height: 0.28), 0x6E4D00),
    (CGRect(x: 0.80, y: 0.74, width: 0.20, height: 0.26), 0x483300),
]

/// Draws the icon at `size` pixels; `margin` is the transparent border fraction (0 for web use).
func render(size: Int, margin: CGFloat) -> CGImage {
    let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let full = CGFloat(size)
    let body = CGRect(x: full * margin, y: full * margin, width: full * (1 - 2 * margin), height: full * (1 - 2 * margin))
    ctx.addPath(squircle(in: body))
    ctx.clip()
    ctx.setFillColor(hex(0x0E0D0B))
    ctx.fill(body)

    let inset = body.width * 0.15
    let area = body.insetBy(dx: inset, dy: inset)
    let gap = max(1, area.width * 0.035)
    let radius = area.width * 0.035
    for (unit, color) in tiles {
        let r = CGRect(
            x: area.minX + unit.minX * area.width, y: area.minY + unit.minY * area.height,
            width: unit.width * area.width, height: unit.height * area.height
        ).insetBy(dx: gap / 2, dy: gap / 2)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.setFillColor(hex(color))
        ctx.fillPath()
    }
    return ctx.makeImage()!
}

/// Writes `image` as a PNG at `url`.
func writePNG(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(url.path)") }
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output-dir>\n".utf8))
    exit(2)
}
let out = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = out.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    writePNG(render(size: base, margin: 0.098), to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    writePNG(render(size: base * 2, margin: 0.098), to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
writePNG(render(size: 512, margin: 0), to: out.appendingPathComponent("web-icon.png"))
writePNG(render(size: 64, margin: 0), to: out.appendingPathComponent("web-favicon.png"))

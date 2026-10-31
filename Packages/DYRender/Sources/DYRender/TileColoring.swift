import DYCore
import Foundation
import simd

/// Chooses tile colours from `Palette` only. Hues are never altered here; the shader only scales brightness.
public struct TileColoring {
    public let tree: FileTree
    public let style: NodeStyle
    public let dominantKind: [UInt8]

    /// Creates a colouring over `tree`. `dominantKind` gives each directory's colour in kind mode.
    public init(tree: FileTree, style: NodeStyle, dominantKind: [UInt8]) {
        self.tree = tree; self.style = style; self.dominantKind = dominantKind
    }

    /// The file kind that colours a node: its own for files, the dominant one for directories.
    public func kind(of node: NodeID) -> FileKind {
        if tree.isDirectory(node), !dominantKind.isEmpty { return FileKind(rawValue: dominantKind[Int(node)]) ?? .other }
        return tree.kind(node)
    }

    /// The decision recorded for a node, or `.none`.
    public func decision(of node: NodeID) -> Decision {
        style.decisions.isEmpty ? .none : Decision(rawValue: style.decisions[Int(node)]) ?? .none
    }

    /// The safety tier recorded for a node, or `.unknown`.
    public func tier(of node: NodeID) -> SafetyTier {
        style.safety.isEmpty ? .unknown : SafetyTier(rawValue: style.safety[Int(node)]) ?? .unknown
    }

    /// The fill colour for a node under the active colour mode.
    public func color(of node: NodeID) -> SIMD3<Float> {
        switch style.colorMode {
        case .kind: return Palette.kind(kind(of: node))
        case .age:
            let modified = tree.modified(node)
            return Palette.age(seconds: modified > 0 ? max(style.now - modified, 0) : Int32.max / 2)
        case .safety: return Palette.safety(tier(of: node))
        case .decision:
            switch decision(of: node) {
            case .keep: return Palette.keep
            case .remove: return Palette.remove
            case .later: return Palette.later
            case .none: return simd_mix(Palette.hairline, Palette.textMuted, SIMD3(repeating: 0.22))
            }
        }
    }

    /// How strongly a node glows gold. Only safety mode glows, and only for removable tiers.
    public func glow(of node: NodeID) -> Float {
        guard style.colorMode == .safety else { return 0 }
        switch tier(of: node) {
        case .safe: return 1
        case .rebuild: return 0.5
        default: return 0
        }
    }

    /// Whether dark text reads better than light text on this fill.
    public static func prefersDarkText(_ color: SIMD3<Float>) -> Bool {
        0.2126 * color.x + 0.7152 * color.y + 0.0722 * color.z > 0.52
    }

    /// Cheap per-directory colour: the kind of the largest child, followed down the tree in one linear pass.
    public static func approximateDominantKinds(_ tree: FileTree) -> [UInt8] {
        var result = tree.columns.kind
        let columns = tree.columns
        for index in stride(from: tree.count - 1, through: 0, by: -1) where columns.childCount[index] > 0 {
            result[index] = result[Int(columns.firstChild[index])]
        }
        return result
    }
}

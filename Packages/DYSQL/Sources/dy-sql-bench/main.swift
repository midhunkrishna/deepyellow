import DYCore
import DYSQL
import Foundation

/// Times `body` in milliseconds.
func milliseconds(_ body: () throws -> Void) rethrows -> Double {
    let started = DispatchTime.now().uptimeNanoseconds
    try body()
    return Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
}

print("Building SyntheticTree.make(scale: 100)...")
var tree: FileTree!
let buildTime = milliseconds { tree = SyntheticTree.make(scale: 100) }
var lens: TreeLens!
let lensTime = milliseconds { lens = TreeLens(tree: tree) }
let context = SQLContext(tree: tree, lens: lens, now: SyntheticTree.referenceNow)
print("nodes: \(tree.count)  tree build: \(Int(buildTime)) ms  lens: \(Int(lensTime)) ms\n")

/// Best of three setup timings: open, register, create views, install the authorizer, prepare a trivial statement.
var setupColumns: [String] = []
let setup = (0..<5).map { _ in milliseconds { setupColumns = (try? SQLEngine.validate("SELECT id FROM files", context: context)) ?? [] } }.min() ?? 0
precondition(setupColumns == ["id"], "setup failed")
print(String(format: "connection setup            %8.2f ms   (budget 20 ms)", setup))

let queries: [(String, String, String)] = [
    ("group by kind", "SELECT kind, SUM(size), COUNT(*) FROM files GROUP BY kind", "budget 1000 ms"),
    ("filter and sort", "SELECT id, size FROM files WHERE age_days(modified) > 365 ORDER BY size DESC LIMIT 100", ""),
    ("group by extension", "SELECT ext, ids(id) AS ids, SUM(size) FROM files GROUP BY ext", ""),
    ("join to parent", "SELECT p.id, SUM(f.size) AS s FROM files f JOIN dirs p ON p.id = f.parent GROUP BY p.id ORDER BY s DESC LIMIT 100", ""),
    ("path of the 100 biggest", "SELECT id, path FROM files ORDER BY size DESC LIMIT 100", ""),
]
for (title, sql, note) in queries {
    var rows = 0
    let time = milliseconds {
        rows = (try? SQLEngine.run(sql, context: context, rowLimit: 100).rowCount) ?? -1
    }
    print(title.padding(toLength: 26, withPad: " ", startingAt: 0) + String(format: " %8.1f ms   %d rows  ", time, rows) + note)
}

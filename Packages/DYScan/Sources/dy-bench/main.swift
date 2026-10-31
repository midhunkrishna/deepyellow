import DYCore
import DYScan
import Foundation

/// Scans a path and prints aggregate throughput only; no file names are ever printed.
func bench(path: String, workers: Int?) async {
    var options = ScanOptions(root: path)
    if let workers { options.workers = workers }
    let start = ContinuousClock.now
    var tree: FileTree?
    for await event in DiskScanner(options: options).start() {
        if case .finished(let finished) = event { tree = finished }
    }
    let components = (ContinuousClock.now - start).components
    let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
    guard let tree else { return }
    var directories = 0
    for node in 0..<Int32(tree.count) where tree.isDirectory(node) { directories += 1 }
    let files = Int(tree.fileCount(0))
    print("files:       \(files)")
    print("directories: \(directories)")
    print("bytes:       \(tree.allocated(0))")
    print(String(format: "seconds:     %.3f", seconds))
    print(String(format: "files/sec:   %.0f", Double(files) / seconds))
    print("unreadable:  \(tree.meta.unreadableDirectories)")
}

let arguments = Array(CommandLine.arguments.dropFirst())
var path = NSHomeDirectory()
var repeats = 1
var workers: Int?
var index = 0
while index < arguments.count {
    switch arguments[index] {
    case "--repeat": index += 1; repeats = Int(arguments[safe: index] ?? "") ?? 1
    case "--workers": index += 1; workers = Int(arguments[safe: index] ?? "")
    default: path = arguments[index]
    }
    index += 1
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

for run in 1...max(1, repeats) {
    if repeats > 1 { print("run \(run)") }
    await bench(path: path, workers: workers)
}


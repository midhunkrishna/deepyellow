import DYAdvisor
import DYCore
import DYDecide
import DYScan
import Foundation
import XCTest
@testable import DYWorkspace

/// Creates a temp directory that is removed when the test ends. Tests never write anywhere else.
func makeTempDirectory(_ test: XCTestCase) -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("dyworkspace-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    test.addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
}

/// A workspace on the demo environment, opened and fully analysed.
@MainActor
func openDemo(_ test: XCTestCase, dataDirectory: URL? = nil) async -> Workspace {
    let workspace = Workspace(environment: .demo(dataDirectory: dataDirectory ?? makeTempDirectory(test)))
    workspace.open(.demo)
    await workspace.settle()
    return workspace
}

/// An environment on a small synthetic tree, with the scan stream supplied by the test.
func plainEnvironment(directory: URL, scan: @escaping @Sendable (String) -> ScanHandle) -> WorkspaceEnvironment {
    let tree = SyntheticTree.make(scale: 0.05)
    let trash = DemoTrash(fingerprint: { path in tree.find(path: path).map { Fingerprint(tree: tree, node: $0) } })
    return WorkspaceEnvironment(
        homePath: "/Users/demo", dataDirectory: directory, mover: trash, appCatalog: DemoAppCatalog(),
        reader: DemoFileReader(groups: [:], sizes: [:], headers: [:]), probe: DemoProbe(measured: [:]),
        clock: { Date(timeIntervalSince1970: TimeInterval(SyntheticTree.referenceNow)) }, startScan: scan)
}

/// A scan stream that yields the given events and finishes.
func finishedScan(_ tree: FileTree) -> @Sendable (String) -> ScanHandle {
    { _ in
        ScanHandle(events: AsyncStream { continuation in
            continuation.yield(.progress(ScanProgress(files: 10, directories: 2, bytes: 100, unreadable: 0, elapsed: 0.1, currentPath: "/x")))
            continuation.yield(.finished(tree))
            continuation.finish()
        }, cancel: {})
    }
}

/// Waits for a condition on the main actor, failing the test if it doesn't come true.
@MainActor
func eventually(_ message: String = "condition", _ condition: @MainActor () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
    for _ in 0..<500 {
        if condition() { return }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("Timed out waiting for \(message)", file: file, line: line)
}

extension Workspace {
    /// The node at `path` in the current tree.
    func node(_ path: String) -> NodeID { tree!.find(path: path)! }
}

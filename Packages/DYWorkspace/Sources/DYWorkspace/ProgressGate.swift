import Foundation

/// Drops progress updates that moved less than one percent, so a worker thread doesn't flood the main actor.
final class ProgressGate: @unchecked Sendable {
    private let lock = NSLock()
    private var last = 0.0

    /// True when `fraction` is at least 0.01 past the last accepted value, or is 1 or more. Records accepted values.
    func accept(_ fraction: Double) -> Bool {
        lock.withLock {
            guard fraction >= 1 || fraction - last >= 0.01 else { return false }
            last = fraction
            return true
        }
    }
}

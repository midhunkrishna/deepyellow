import Foundation

/// A blocking queue shared between threads. Closing it wakes every waiter.
final class WorkQueue<Element> {
    private let condition = NSCondition()
    private var items: [Element] = []
    private var closed = false

    /// Adds one element and wakes a waiter.
    func push(_ element: Element) {
        condition.lock()
        items.append(element)
        condition.unlock()
        condition.signal()
    }

    /// Adds several elements and wakes every waiter.
    func push(contentsOf elements: [Element]) {
        guard !elements.isEmpty else { return }
        condition.lock()
        items.append(contentsOf: elements)
        condition.unlock()
        condition.broadcast()
    }

    /// Removes the newest element, blocking until one arrives. Returns nil once the queue is closed and empty.
    func popLast() -> Element? {
        condition.lock()
        defer { condition.unlock() }
        while items.isEmpty && !closed { condition.wait() }
        return items.popLast()
    }

    /// Removes everything queued, blocking until something arrives or `deadline` passes. Empty means timeout or closed.
    func popAll(until deadline: Date) -> [Element] {
        condition.lock()
        defer { condition.unlock() }
        while items.isEmpty && !closed {
            if !condition.wait(until: deadline) { break }
        }
        let taken = items
        items = []
        return taken
    }

    /// Stops the queue: waiters return and later pops see it as empty.
    func close() {
        condition.lock()
        closed = true
        condition.unlock()
        condition.broadcast()
    }
}

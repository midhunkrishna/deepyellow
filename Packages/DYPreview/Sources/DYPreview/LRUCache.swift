import Foundation

/// A least-recently-used cache bounded by total cost.
public struct LRUCache<Key: Hashable, Value> {
    private var values: [Key: (value: Value, cost: Int)] = [:]
    private var order: [Key] = []
    public private(set) var totalCost = 0
    public let maxCost: Int

    /// Creates a cache that evicts oldest entries once `totalCost` exceeds `maxCost`.
    public init(maxCost: Int) { self.maxCost = maxCost }

    /// Number of entries held.
    public var count: Int { values.count }

    /// Returns a value and marks it most recently used.
    public mutating func get(_ key: Key) -> Value? {
        guard let entry = values[key] else { return nil }
        touch(key)
        return entry.value
    }

    /// Stores a value, then evicts least recently used entries until within budget. The newest entry always stays.
    public mutating func set(_ key: Key, _ value: Value, cost: Int = 1) {
        if let old = values[key] { totalCost -= old.cost }
        values[key] = (value, cost)
        totalCost += cost
        touch(key)
        while totalCost > maxCost, order.count > 1 {
            let oldest = order.removeFirst()
            if let gone = values.removeValue(forKey: oldest) { totalCost -= gone.cost }
        }
    }

    /// Whether a key is held, without changing recency.
    public func contains(_ key: Key) -> Bool { values[key] != nil }

    private mutating func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}

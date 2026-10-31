import Darwin

/// Bounds how much memory one query may add, because the system SQLite is built without memory accounting and so ignores
/// `sqlite3_hard_heap_limit64`. Measures the process footprint instead.
struct MemoryGuard {
    /// The most a run may add to the process footprint, in bytes.
    nonisolated(unsafe) static var budget: Int64 = 2 << 30
    /// Progress callbacks between footprint readings. A reading costs about a microsecond and a callback comes every couple of thousand opcodes.
    private static let callbacksPerReading = 1

    private let baseline: Int64
    private var callbacks = 0
    private(set) var exceeded = false

    /// Starts measuring from the current footprint.
    init() { baseline = Self.footprint() }

    /// Called from the progress handler. Returns true once the run has used more than the budget.
    mutating func isOverBudget() -> Bool {
        callbacks += 1
        guard !exceeded, callbacks % Self.callbacksPerReading == 0 else { return exceeded }
        exceeded = Self.footprint() - baseline > Self.budget
        return exceeded
    }

    /// The process's physical footprint in bytes, or 0 if the system won't say.
    static func footprint() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? Int64(info.phys_footprint) : 0
    }
}

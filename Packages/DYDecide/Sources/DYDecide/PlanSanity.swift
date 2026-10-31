import Foundation

/// A second check on a plan's items, applied by the executor in case a plan was built by hand.
enum PlanSanity {
    /// Splits `items` into those safe to attempt and those refused with a reason.
    ///
    /// Refused: relative paths, `/`, paths with `.` or `..`, duplicates, and anything inside another item of the same plan.
    static func partition(_ items: [PlanItem]) -> (accepted: [PlanItem], refused: [(path: String, reason: String)]) {
        let allPaths = Set(items.map(\.id))
        var seen = Set<String>()
        var accepted: [PlanItem] = []
        var refused: [(path: String, reason: String)] = []
        for item in items {
            if let problem = PlannerGuards.pathProblem(item.id) {
                refused.append((item.id, problem))
            } else if !seen.insert(item.id).inserted {
                refused.append((item.id, "Listed twice in the plan"))
            } else if hasAncestor(in: allPaths, of: item.id) {
                refused.append((item.id, "Inside another item of the same plan"))
            } else {
                accepted.append(item)
            }
        }
        return (accepted, refused)
    }

    /// Whether any proper ancestor of `path` is in `paths`.
    private static func hasAncestor(in paths: Set<String>, of path: String) -> Bool {
        var parts = path.split(separator: "/", omittingEmptySubsequences: true)
        while parts.count > 1 {
            parts.removeLast()
            if paths.contains("/" + parts.joined(separator: "/")) { return true }
        }
        return false
    }
}

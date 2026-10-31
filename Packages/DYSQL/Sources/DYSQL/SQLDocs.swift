/// The text shown in menus, popovers and the docs: examples and function descriptions.
enum SQLDocs {
    /// The function list.
    static let functions: [SQLColumnDoc] = [
        SQLColumnDoc(name: "kb", type: "kb(n) -> number", meaning: "n kilobytes in bytes (n x 1,000)"),
        SQLColumnDoc(name: "mb", type: "mb(n) -> number", meaning: "n megabytes in bytes (n x 1,000,000)"),
        SQLColumnDoc(name: "gb", type: "gb(n) -> number", meaning: "n gigabytes in bytes (n x 1,000,000,000)"),
        SQLColumnDoc(name: "tb", type: "tb(n) -> number", meaning: "n terabytes in bytes (n x 1,000,000,000,000)"),
        SQLColumnDoc(name: "human", type: "human(bytes) -> text", meaning: "A size as the app prints it, such as 1.2 GB"),
        SQLColumnDoc(name: "age_days", type: "age_days(seconds) -> integer", meaning: "Whole days between a timestamp and now"),
        SQLColumnDoc(name: "ids", type: "ids(id) -> blob", meaning: "Aggregate: the ids of a group. Alias it as ids to let a row drive the views"),
    ]

    /// The example list.
    static let examples: [SQLExample] = [
        SQLExample(title: "Biggest files",
                   sql: "SELECT id, name, human(size) AS readable FROM files ORDER BY size DESC LIMIT 100"),
        SQLExample(title: "Big files untouched for a year",
                   sql: "SELECT id, name, human(size) AS readable, age_days(modified) AS days FROM files\nWHERE size > mb(100) AND age_days(modified) > 365\nORDER BY size DESC"),
        SQLExample(title: "Video over 1 GB",
                   sql: "SELECT id, name, human(size) AS readable FROM files WHERE kind = 'video' AND size > gb(1) ORDER BY size DESC"),
        SQLExample(title: "Biggest folders",
                   sql: "SELECT id, name, human(size) AS readable, file_count FROM dirs WHERE depth > 0 ORDER BY size DESC LIMIT 100"),
        SQLExample(title: "Files in the five biggest folders",
                   sql: "SELECT f.id, f.name, human(f.size) AS readable FROM files f\nJOIN (SELECT id FROM dirs ORDER BY size DESC LIMIT 5) d ON f.parent = d.id\nORDER BY f.size DESC"),
        SQLExample(title: "Everything inside the biggest top-level folder",
                   sql: "WITH RECURSIVE inside(id) AS (\n  SELECT id FROM (SELECT id FROM dirs WHERE depth = 1 ORDER BY size DESC LIMIT 1)\n  UNION ALL\n  SELECT n.id FROM nodes n JOIN inside ON n.parent = inside.id\n)\nSELECT n.id, n.name, human(n.size) AS readable FROM nodes n JOIN inside USING (id) WHERE n.is_dir = 0"),
        SQLExample(title: "Marked for removal",
                   sql: "SELECT id, name, human(size) AS readable FROM nodes WHERE mark = 'remove' ORDER BY size DESC"),
        SQLExample(title: "Safe or rebuildable",
                   sql: "SELECT id, name, safety, human(size) AS readable FROM nodes WHERE safety IN ('safe', 'rebuild') ORDER BY size DESC LIMIT 200"),
        SQLExample(title: "Space by kind",
                   sql: "SELECT kind, ids(id) AS ids, COUNT(*) AS files, human(SUM(size)) AS total FROM files GROUP BY kind ORDER BY SUM(size) DESC"),
        SQLExample(title: "Space by extension",
                   sql: "SELECT ext, ids(id) AS ids, COUNT(*) AS files, human(SUM(size)) AS total FROM files WHERE ext IS NOT NULL\nGROUP BY ext ORDER BY SUM(size) DESC LIMIT 50"),
        SQLExample(title: "Same name and size",
                   sql: "SELECT name, ids(id) AS ids, COUNT(*) AS copies, human(size) AS each_size FROM files WHERE size > mb(1)\nGROUP BY name, size HAVING COUNT(*) > 1 ORDER BY SUM(size) DESC"),
        SQLExample(title: "Cumulative share of the 20 biggest files (table only)",
                   sql: "SELECT name, human(size) AS readable,\n  ROUND(100.0 * SUM(size) OVER (ORDER BY size DESC, id) / (SELECT SUM(size) FROM files), 1) AS cumulative_percent\nFROM (SELECT id, name, size FROM files ORDER BY size DESC, id LIMIT 20)"),
    ]
}

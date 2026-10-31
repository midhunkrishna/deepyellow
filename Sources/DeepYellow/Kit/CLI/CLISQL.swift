import DYAdvisor
import DYCore
import DYSQL
import DYWorkspace
import Foundation

/// Text for one SQL cell, shared by the terminal table, CSV and the app's results table.
public enum SQLValueText {
    /// The cell as plain text. NULL reads "NULL".
    public static func text(_ value: SQLValue) -> String {
        switch value {
        case .null: "NULL"
        case .integer(let number): String(number)
        case .real(let number): number.isFinite ? String(number) : "NULL"
        case .text(let string): string
        case .blob(let count): "<\(count) bytes>"
        }
    }

    /// True for the cell types that are right-aligned.
    public static func isNumber(_ value: SQLValue) -> Bool {
        switch value {
        case .integer, .real: true
        default: false
        }
    }

    /// The plain words for a failed query.
    public static func message(of failure: SQLFailure) -> String {
        switch failure {
        case .invalid(let message), .refused(let message), .multipleStatements(let message), .tooLarge(let message): message
        case .cancelled: "The query was cancelled."
        }
    }
}

/// `deepyellow sql`: runs a read-only query and prints it as a table, JSON or CSV.
public enum CLISQL {
    /// The sample disk, built the same way as in `--demo`.
    public static func demoDisk() -> (tree: FileTree, now: Int32, home: String) {
        let environment = WorkspaceEnvironment.demo(dataDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("DeepYellowCLIDemo"))
        let tree = environment.sampleDisk?() ?? SyntheticTree.make()
        return (tree, Int32(environment.clock().timeIntervalSince1970), environment.homePath)
    }

    /// Runs the request on the sample disk.
    static func run(_ request: SQLRequest, tree disk: (tree: FileTree, now: Int32, home: String), context: CLIContext, style: OutputStyle) -> Int32 {
        run(request, tree: disk.tree, now: disk.now, home: disk.home, context: context, style: style)
    }

    /// Runs the request on a scanned folder.
    static func run(_ request: SQLRequest, tree: FileTree, context: CLIContext, style: OutputStyle) -> Int32 {
        run(request, tree: tree, now: Int32(Date().timeIntervalSince1970), home: context.home, context: context, style: style)
    }

    /// Builds the read-only context and prints the result. `safety` is computed only when the query mentions it.
    private static func run(_ request: SQLRequest, tree: FileTree, now: Int32, home: String, context: CLIContext, style: OutputStyle) -> Int32 {
        let lens = TreeLens(tree: tree)
        var safety: [UInt8] = []
        if request.query.lowercased().contains("safety") {
            safety = ReclaimEngine.analyze(lens: lens, home: home, rules: ReclaimEngine.builtinRules, isCancelled: { false })?.nodeTier ?? []
        }
        let sql = SQLContext(tree: tree, lens: lens, decisions: [], safety: safety, now: now)
        do {
            switch request.format {
            case .table: try printTable(request, sql, context, style)
            case .json: try stream(request, sql, context, json: true)
            case .csv: try stream(request, sql, context, json: false)
            }
            return 0
        } catch let failure as SQLFailure {
            context.err("deepyellow: \(SQLValueText.message(of: failure))\n")
            return 65
        } catch {
            context.err("deepyellow: \(error.localizedDescription)\n")
            return 65
        }
    }

    // MARK: Table

    /// Prints up to `top` rows, then how many more there are.
    private static func printTable(_ request: SQLRequest, _ sql: SQLContext, _ context: CLIContext, _ style: OutputStyle) throws {
        let result = try SQLEngine.run(request.query, context: sql, rowLimit: request.top)
        context.out(table(columns: result.columns, rows: result.rows, total: result.rowCount, elapsed: result.elapsed, style: style))
    }

    /// Lays out a result as aligned columns. Numbers are right-aligned and long cells are cut in the middle.
    public static func table(columns: [String], rows: [[SQLValue]], total: Int, elapsed: TimeInterval, style: OutputStyle) -> String {
        let cells = rows.map { $0.map { cut(SQLValueText.text($0), 48) } }
        let widths = columns.indices.map { index in max(columns[index].count, cells.map { $0[index].count }.max() ?? 0) }
        let numeric = columns.indices.map { index in rows.first.map { SQLValueText.isNumber($0[index]) } ?? false }
        func line(_ values: [String]) -> String {
            values.indices.map { numeric[$0] ? CLIRender.right(values[$0], widths[$0]) : values[$0].padding(toLength: widths[$0], withPad: " ", startingAt: 0) }
                .joined(separator: "  ").replacingOccurrences(of: " +$", with: "", options: .regularExpression)
        }
        var lines = [CLIRender.dim(line(columns), style), CLIRender.dim(widths.map { String(repeating: "-", count: $0) }.joined(separator: "  "), style)]
        lines.append(contentsOf: cells.map(line))
        let more = total - rows.count
        lines.append("")
        lines.append(more > 0 ? "\(Format.count(more)) more rows (\(Format.count(total)) in all). Use --top N, or --json or --csv for every row."
                              : "\(Format.count(total)) \(total == 1 ? "row" : "rows") in \(String(format: "%.2f", elapsed)) s")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Cuts `text` to `limit` characters with an ellipsis in the middle.
    static func cut(_ text: String, _ limit: Int) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        guard flat.count > limit else { return flat }
        let head = (limit - 1) / 2 + (limit - 1) % 2
        return String(flat.prefix(head)) + "…" + String(flat.suffix(limit - 1 - head))
    }

    // MARK: Streaming

    /// Writes every row as it is produced, in 64 KB pieces, so a large result never sits in memory.
    private static func stream(_ request: SQLRequest, _ sql: SQLContext, _ context: CLIContext, json: Bool) throws {
        let columns = try SQLEngine.validate(request.query, context: sql)
        let buffer = StreamBuffer(flush: context.out)
        buffer.append(json ? "{\n  \"columns\": \(jsonArray(columns.map(jsonString))),\n  \"rows\": [" : columns.map(csvField).joined(separator: ",") + "\n")
        var first = true
        let result = try SQLEngine.run(request.query, context: sql, rowLimit: 0, onRow: { row in
            if json {
                buffer.append((first ? "\n    " : ",\n    ") + jsonArray(row.map(jsonValue)))
            } else {
                buffer.append(row.map { csvField($0 == .null ? "" : SQLValueText.text($0)) }.joined(separator: ",") + "\n")
            }
            first = false
        })
        if json { buffer.append("\n  ],\n  \"rowCount\": \(result.rowCount),\n  \"elapsedSeconds\": \(String(format: "%.3f", result.elapsed))\n}\n") }
        buffer.finish()
    }

    /// A JSON string literal.
    static func jsonString(_ text: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: text, options: [.fragmentsAllowed, .withoutEscapingSlashes])
        return data.map { String(decoding: $0, as: UTF8.self) } ?? "\"\""
    }

    /// A JSON literal for one cell. Blobs become a short description and non-finite numbers become null.
    static func jsonValue(_ value: SQLValue) -> String {
        switch value {
        case .null: "null"
        case .integer(let number): String(number)
        case .real(let number): number.isFinite ? String(number) : "null"
        case .text(let text): jsonString(text)
        case .blob(let count): jsonString("<\(count) bytes>")
        }
    }

    /// `[a, b, c]` from pieces already in JSON form.
    static func jsonArray(_ pieces: [String]) -> String { "[" + pieces.joined(separator: ", ") + "]" }

    /// One CSV field, quoted when it holds a comma, quote or line break.
    static func csvField(_ text: String) -> String {
        guard text.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: Schema

    /// What `--schema` prints.
    public static func schemaText() -> String {
        func rows(_ docs: [SQLColumnDoc], typeWidth: Int) -> [String] {
            let nameWidth = docs.map(\.name.count).max() ?? 0
            return docs.map { "  \($0.name.padding(toLength: nameWidth, withPad: " ", startingAt: 0))  \($0.type.padding(toLength: typeWidth, withPad: " ", startingAt: 0))  \($0.meaning)" }
        }
        var lines = ["Table nodes: one row per file or folder. Views: files (visible files), dirs (visible folders).", ""]
        lines += rows(SQLEngine.schema, typeWidth: 8)
        lines += ["", "Functions"]
        lines += rows(SQLEngine.functions, typeWidth: 28)
        lines += ["", "Examples"]
        for example in SQLEngine.examples { lines += ["", "  -- \(example.title)"] + example.sql.split(separator: "\n").map { "  \($0)" } }
        return lines.joined(separator: "\n") + "\n"
    }
}

/// Collects text and hands it on in pieces of about 64 KB.
final class StreamBuffer {
    private var text = ""
    private let flush: (String) -> Void

    /// Creates a buffer that writes through `flush`.
    init(flush: @escaping (String) -> Void) { self.flush = flush }

    /// Adds text, writing out a piece when enough has gathered.
    func append(_ piece: String) {
        text += piece
        if text.utf8.count >= 65_536 { finish() }
    }

    /// Writes whatever is left.
    func finish() {
        guard !text.isEmpty else { return }
        flush(text)
        text = ""
    }
}

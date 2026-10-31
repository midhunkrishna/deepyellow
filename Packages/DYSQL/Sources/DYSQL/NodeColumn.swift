/// The columns of the `nodes` table, in declaration order. The single source for the table definition and the documented schema.
enum NodeColumn: Int32, CaseIterable {
    case id, parent, name, ext, path, depth, size, logical, fileCount, modified, accessed, kind
    case isDir, isPackage, isSymlink, isClone, isHardlink, isDataless, visible, mark, safety

    /// The column's name in SQL.
    var sqlName: String {
        switch self {
        case .id: "id"
        case .parent: "parent"
        case .name: "name"
        case .ext: "ext"
        case .path: "path"
        case .depth: "depth"
        case .size: "size"
        case .logical: "logical"
        case .fileCount: "file_count"
        case .modified: "modified"
        case .accessed: "accessed"
        case .kind: "kind"
        case .isDir: "is_dir"
        case .isPackage: "is_package"
        case .isSymlink: "is_symlink"
        case .isClone: "is_clone"
        case .isHardlink: "is_hardlink"
        case .isDataless: "is_dataless"
        case .visible: "visible"
        case .mark: "mark"
        case .safety: "safety"
        }
    }

    /// The declared SQL type.
    var sqlType: String {
        switch self {
        case .name, .ext, .path, .kind, .mark, .safety: "TEXT"
        default: "INTEGER"
        }
    }

    /// One plain sentence on what the column holds.
    var meaning: String {
        switch self {
        case .id: "Node id"
        case .parent: "Parent's id; NULL for the root"
        case .name: "File or folder name"
        case .ext: "Lower-case extension without the dot; NULL for none or for folders"
        case .path: "Full path, built only when read"
        case .depth: "0 for the root"
        case .size: "Bytes on disk as the views count them"
        case .logical: "Logical bytes"
        case .fileCount: "Files at or under the node"
        case .modified: "Modification time, seconds since 1970"
        case .accessed: "Access time, seconds since 1970 (approximate)"
        case .kind: "video, image, audio, document, code, application, archive or other"
        case .isDir: "1 for a folder or package, else 0"
        case .isPackage: "1 for a macOS package such as an .app"
        case .isSymlink: "1 for a symbolic link"
        case .isClone: "1 for a later full clone whose bytes are counted elsewhere"
        case .isHardlink: "1 for a later hard link whose bytes are counted elsewhere"
        case .isDataless: "1 for an iCloud placeholder that isn't stored locally"
        case .visible: "1 when no ignore rule or Trash removal hides the node"
        case .mark: "keep, remove or later; NULL for none"
        case .safety: "safe, rebuild, review or never; NULL for no advice"
        }
    }

    /// The `CREATE TABLE` text handed to `sqlite3_declare_vtab`.
    static var declaration: String {
        "CREATE TABLE nodes(" + allCases.map { "\($0.sqlName) \($0.sqlType)" }.joined(separator: ", ") + ")"
    }
}

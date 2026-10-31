import DYAnalysis
import DYCore
import DYScan
import Foundation

/// How much one ignore rule hid.
public struct HiddenRuleLine: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var label: String
    public var pattern: String
    public var bytes: UInt64
    public var files: UInt64
}

/// Where every byte of the scan went. A figure that isn't known is nil, never zero.
public struct Reconciliation: Equatable, Sendable {
    /// Bytes and files shown by the current views.
    public var visibleBytes: UInt64
    public var visibleFiles: UInt64
    /// Bytes and files hidden by ignore rules. Hidden is never gone.
    public var hiddenBytes: UInt64
    public var hiddenFiles: UInt64
    /// Per-rule totals, largest first, for rules that hid something.
    public var hiddenByRule: [HiddenRuleLine]
    /// Bytes and files not matching the current query.
    public var filteredBytes: UInt64
    public var filteredFiles: UInt64
    /// Bytes moved to the Trash in this session. They still occupy the volume until the Trash is emptied.
    public var removedThisSessionBytes: UInt64
    /// Bytes the scan counted once but that occur under several names.
    public var hardlinkBytesSaved: UInt64
    /// Bytes shared between APFS clones that the scan counted once.
    public var cloneBytesSaved: UInt64
    public var unreadableDirectories: Int
    /// True when Full Disk Access was missing, so `unreadableDirectories` is likely an undercount.
    public var limitedByPermissions: Bool
    /// What the scan found in total, before hiding, filtering and removal.
    public var scannedBytes: UInt64
    /// The volume's size and free space. Nil unless the scan root is a volume.
    public var volumeTotal: UInt64?
    public var volumeAvailable: UInt64?
    /// Used space on the volume that the scan doesn't account for. Negative when the scan holds more than the volume reports,
    /// which happens when the root is a folder that includes shared data. Nil when the volume is unknown.
    public var remainderBytes: Int64?
    public var remainderLabel: String
    /// True when the volume and savings figures are the demo's explicit sample values.
    public var usesSampleValues: Bool

    /// Builds the reconciliation for a lens over a tree.
    static func make(lens: TreeLens, ignore: IgnoreResult?, rules: IgnoreRuleSet, volume: VolumeInfo?,
                     sample: SampleLedger?) -> Reconciliation {
        let tree = lens.tree
        let meta = tree.meta
        let scanned = tree.count > 0 ? tree.allocated(0) : 0
        var lines: [HiddenRuleLine] = []
        for rule in rules.rules {
            guard let totals = ignore?.perRule[rule.id], totals.bytes > 0 || totals.files > 0 else { continue }
            lines.append(HiddenRuleLine(id: rule.id, label: rule.label.isEmpty ? rule.pattern : rule.label, pattern: rule.pattern,
                                        bytes: totals.bytes, files: totals.files))
        }
        lines.sort { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.label < $1.label }
        let volumeInfo = sample?.volume ?? volume
        var remainder: Int64?
        var label = "Unknown: this scan didn't start at a volume, so used space can't be compared."
        if let volumeInfo {
            let used = volumeInfo.total &- min(volumeInfo.total, volumeInfo.available)
            remainder = Int64(clamping: used) - Int64(clamping: scanned)
            label = (remainder ?? 0) >= 0
                ? "Not in this scan: local snapshots, purgeable space, other users and system files."
                : "The scan holds more than the volume reports as used, usually because it includes shared data."
        }
        return Reconciliation(
            visibleBytes: lens.size.first ?? 0, visibleFiles: UInt64(lens.files.first ?? 0),
            hiddenBytes: lens.hiddenBytes, hiddenFiles: lens.hiddenFiles, hiddenByRule: lines,
            filteredBytes: lens.filteredBytes, filteredFiles: lens.filteredFiles, removedThisSessionBytes: lens.removedBytes,
            hardlinkBytesSaved: sample?.hardlinkBytesSaved ?? meta.hardlinkBytesSaved,
            cloneBytesSaved: sample?.cloneBytesSaved ?? meta.cloneBytesSaved,
            unreadableDirectories: sample?.unreadableDirectories ?? meta.unreadableDirectories,
            limitedByPermissions: meta.limitedByPermissions, scannedBytes: scanned,
            volumeTotal: volumeInfo?.total, volumeAvailable: volumeInfo?.available,
            remainderBytes: remainder, remainderLabel: label, usesSampleValues: sample != nil)
    }
}

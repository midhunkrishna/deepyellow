import DYCore
import DYLenses
import DYScan
import DYWorkspace
import SwiftUI

/// The first screen: pick something to read, with honest notes about permissions.
struct WelcomeView: View {
    let shell: ShellState

    var body: some View {
        HStack(alignment: .top, spacing: 56) {
            VStack(alignment: .leading, spacing: 18) {
                Text("DeepYellow").font(.system(size: 34, weight: .bold)).foregroundStyle(Theme.accent)
                Text("See what's on your disk, understand it at the right level of detail, and clear it without fear.")
                    .font(.system(size: 14)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    ChipButton(title: "Choose a folder…", key: "⌘O", prominent: true) { shell.perform(.chooseFolder) }
                    ChipButton(title: "Try the sample disk") { shell.perform(.openDemo) }
                }
                accessCard
                if shell.isReadOnly {
                    Label("Read-only session: scans are real, but nothing can be moved to the Trash.", systemImage: "lock.fill")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                }
                Text("Reading only. Items you remove go to the Trash, never straight to deletion. No network code, no telemetry.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 400, alignment: .leading)
            VStack(alignment: .leading, spacing: 22) {
                volumeList
                if !shell.recents.isEmpty { recentList }
            }
            .frame(width: 420, alignment: .leading)
        }
        .padding(.horizontal, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// What Full Disk Access means for this machine, and the button to the right Settings pane.
    private var accessCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Full Disk Access", systemImage: shell.fullDiskAccess == .granted ? "checkmark.circle" : "lock").font(.system(size: 12.5, weight: .semibold))
            Text(accessText).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            if shell.fullDiskAccess != .granted {
                ChipButton(title: "Open Full Disk Access settings") { FullDiskAccess.openSettings() }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline))
    }

    private var accessText: String {
        switch shell.fullDiskAccess {
        case .granted: "On. Scans can read protected folders, so totals match what is really there."
        case .denied: "Off. You can still scan, but protected folders such as parts of ~/Library, Mail and Safari can't be read. They are counted and shown as unreadable, so totals will be lower than Finder's until you allow it. Add DeepYellow under Privacy & Security > Full Disk Access, then reopen the app."
        case .unknown: "Couldn't tell. If a scan reports unreadable folders, add DeepYellow under Privacy & Security > Full Disk Access and reopen the app."
        }
    }

    /// Mounted volumes with how full they are.
    private var volumeList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Volumes").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            ForEach(shell.volumes) { volume in
                Button { shell.open(path: volume.path) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Image(systemName: volume.isInternal ? "internaldrive" : "externaldrive").foregroundStyle(Theme.textMuted)
                            Text(volume.name).font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text("\(Format.bytes(volume.available)) free of \(Format.bytes(volume.total))").font(Theme.number(size: 11)).foregroundStyle(Theme.textSecondary)
                        }
                        UsageBar(fraction: volume.total == 0 ? 0 : Double(volume.total - min(volume.available, volume.total)) / Double(volume.total))
                    }
                    .padding(12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Recently scanned folders.
    private var recentList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            ForEach(shell.recents, id: \.self) { path in
                Button { shell.open(path: path) } label: {
                    HStack {
                        Image(systemName: "folder").foregroundStyle(Theme.textMuted)
                        Text(path).font(Theme.mono(size: 11.5)).foregroundStyle(Theme.textPrimary).lineLimit(1).truncationMode(.head)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

import DYCore
import DYDecide
import DYLenses
import DYScan
import DYWorkspace
import SwiftUI

/// Shows whichever panel is open.
struct SheetHost: View {
    let shell: ShellState

    var body: some View {
        switch shell.sheet {
        case .plan: ModalPanel(width: 680, close: { shell.sheet = nil }) { PlanSheet(shell: shell) }
        case .ledger: ModalPanel(width: 640, close: { shell.sheet = nil }) { LedgerSheet(shell: shell) }
        case .palette: ModalPanel(width: 560, close: { shell.sheet = nil }) { PaletteSheet(shell: shell) }
        case nil: EmptyView()
        }
    }
}

/// The exact list that Apply would move to the Trash, with what is protected and blocked. Apply needs a click here.
struct PlanSheet: View {
    let shell: ShellState
    private var workspace: Workspace { shell.workspace }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Plan").font(.system(size: 16, weight: .semibold))
                Spacer()
                KeyCap(text: "Esc")
            }
            if let plan = workspace.plan, !plan.items.isEmpty {
                Text(workspace.planEstimateText).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.accent)
                if shell.isReadOnly {
                    Label("Read-only: nothing can be moved", systemImage: "lock.fill").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Text("This session was started with --read-only, so the plan below is only a list. Open DeepYellow normally to move anything to the Trash.")
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("These \(Format.count(plan.items.count)) items are moved to the Trash. Moving to the Trash frees nothing until you empty it. Nothing is deleted permanently.")
                    .font(.system(size: 12)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                if shell.isDemo {
                    Text("Sample disk: the Trash here is simulated and no file is touched.").font(.system(size: 11.5)).foregroundStyle(Theme.textMuted)
                }
                itemList(plan)
                if !plan.protected.isEmpty { section("Protected inside these items", "\(Format.count(plan.protected.count)) kept items stay where they are.", plan.protected.map { ($0, "kept") }) }
                if !plan.blocked.isEmpty { section("Blocked", "These will not be moved.", plan.blocked.map { ($0.path, $0.reason) }) }
            } else {
                Text("Nothing is staged.").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                Text("Select items and press x to stage them for removal. Nothing changes on disk until you apply a plan.")
                    .font(.system(size: 12)).foregroundStyle(Theme.textMuted)
                if let plan = workspace.plan, !plan.blocked.isEmpty { section("Blocked", "These will not be moved.", plan.blocked.map { ($0.path, $0.reason) }) }
            }
            if let progress = workspace.applyProgress, workspace.isApplying { ProgressView(value: progress).tint(Theme.accent) }
            footer
        }
        .padding(18)
        .foregroundStyle(Theme.textPrimary)
    }

    /// One row per plan item, biggest first.
    private func itemList(_ plan: RemovalPlan) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(plan.items.sorted { $0.bytes > $1.bytes }) { item in
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal.decrease").font(.system(size: 9)).foregroundStyle(Theme.remove)
                        VStack(alignment: .leading, spacing: 1) {
                            Text((item.id as NSString).lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Text((item.id as NSString).deletingLastPathComponent).font(Theme.mono(size: 10)).foregroundStyle(Theme.textMuted).lineLimit(1).truncationMode(.head)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(Format.bytes(item.bytes)).font(Theme.number(size: 12))
                            Text((item.reclaimIsLowerBound ? "frees at least " : "frees ") + Format.bytes(item.reclaimable))
                                .font(.system(size: 10)).foregroundStyle(Theme.textMuted)
                        }
                    }
                    .padding(.vertical, 5)
                    Divider().overlay(Theme.hairline)
                }
            }
        }
        .frame(maxHeight: 300)
    }

    /// A titled short list of paths with a reason each.
    private func section(_ title: String, _ detail: String, _ rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 12, weight: .semibold))
            Text(detail).font(.system(size: 11)).foregroundStyle(Theme.textMuted)
            ForEach(Array(rows.prefix(4).enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    Text((row.0 as NSString).lastPathComponent).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    Text(row.1).font(.system(size: 10.5)).foregroundStyle(Theme.textMuted).lineLimit(1)
                }
            }
            if rows.count > 4 { Text("and \(rows.count - 4) more").font(.system(size: 10.5)).foregroundStyle(Theme.textMuted) }
        }
    }

    /// Cancel, undo and the explicit Apply button.
    private var footer: some View {
        HStack {
            ChipButton(title: "Close", key: "Esc") { shell.sheet = nil }
            if workspace.canUndoApply, !shell.isReadOnly { ChipButton(title: "Undo last apply") { Task { _ = await workspace.undoApply() } } }
            Spacer()
            if !workspace.canApply, !shell.isReadOnly, workspace.plan?.items.isEmpty == false {
                Text("Waiting for safety advice").font(.system(size: 11)).foregroundStyle(Theme.textMuted)
            }
            if !shell.isReadOnly {
                ChipButton(title: "Move \(Format.count(workspace.plan?.items.count ?? 0)) items to Trash", prominent: true,
                           enabled: workspace.canApply && !workspace.isApplying && !(workspace.plan?.items.isEmpty ?? true)) {
                    Task {
                        _ = await workspace.applyPlan()
                        if workspace.plan?.items.isEmpty ?? true { shell.sheet = nil }
                    }
                }
            }
        }
    }
}

/// The reconciliation: every byte accounted for, with the reason it differs from Finder.
struct LedgerSheet: View {
    let shell: ShellState
    private var workspace: Workspace { shell.workspace }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Ledger").font(.system(size: 16, weight: .semibold)); Spacer(); KeyCap(text: "Esc") }
            if let r = workspace.reconciliation {
                Text("Every byte the scan found is in one line below. Hidden is not gone: it is still counted.")
                    .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                VStack(spacing: 6) {
                    line("Scanned", Format.bytes(r.scannedBytes), strong: true)
                    line("Visible", "\(Format.bytes(r.visibleBytes)) in \(Format.count(r.visibleFiles)) files")
                    line("Hidden by rules", "\(Format.bytes(r.hiddenBytes)) in \(Format.count(r.hiddenFiles)) files")
                    ForEach(r.hiddenByRule) { rule in line("   \(rule.label)", Format.bytes(rule.bytes), dim: true) }
                    if r.filteredBytes > 0 { line("Filtered out by the query", Format.bytes(r.filteredBytes)) }
                    if r.removedThisSessionBytes > 0 { line("Moved to Trash this session", Format.bytes(r.removedThisSessionBytes)) }
                    Divider().overlay(Theme.hairline)
                    line("Hard links counted once", "saves \(Format.bytes(r.hardlinkBytesSaved))")
                    line("Clones counted once", "saves \(Format.bytes(r.cloneBytesSaved))")
                    line("Unreadable folders", r.unreadableDirectories == 0 ? "none" : Format.count(r.unreadableDirectories))
                    if let total = r.volumeTotal {
                        Divider().overlay(Theme.hairline)
                        line("Volume size", Format.bytes(total) + (r.usesSampleValues ? " (sample values)" : ""))
                        if let free = r.volumeAvailable { line("Free", Format.bytes(free)) }
                        if let rest = r.remainderBytes { line(r.remainderLabel, (rest < 0 ? "-" : "") + Format.bytes(UInt64(abs(rest)))) }
                    }
                }
                if r.limitedByPermissions {
                    Text("Some folders could not be read, so the real total is higher than shown.").font(.system(size: 11.5)).foregroundStyle(Theme.accent)
                }
                rules
            } else {
                Text("The ledger appears when the scan has data.").font(.system(size: 12)).foregroundStyle(Theme.textMuted)
            }
        }
        .padding(18)
        .foregroundStyle(Theme.textPrimary)
    }

    /// One label and value.
    private func line(_ label: String, _ value: String, strong: Bool = false, dim: Bool = false) -> some View {
        HStack {
            Text(label).font(.system(size: 12, weight: strong ? .semibold : .regular)).foregroundStyle(dim ? Theme.textMuted : Theme.textSecondary)
            Spacer()
            Text(value).font(Theme.number(size: 12, weight: strong ? .semibold : .regular)).foregroundStyle(dim ? Theme.textMuted : Theme.textPrimary)
        }
    }

    /// The hide rules with switches.
    private var rules: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Hide rules").font(.system(size: 12, weight: .semibold))
            ForEach(workspace.ignoreRules.rules.prefix(6)) { rule in
                Toggle(isOn: Binding(get: { rule.enabled }, set: { workspace.setRule(rule.id, enabled: $0) })) {
                    HStack { Text(rule.label).font(.system(size: 11.5)); Text(rule.pattern).font(Theme.mono(size: 10)).foregroundStyle(Theme.textMuted) }
                }
                .toggleStyle(.switch).controlSize(.mini)
            }
        }
    }
}

/// Type to find any command and run it.
struct PaletteSheet: View {
    let shell: ShellState
    @FocusState private var focused: Bool
    @State private var selected = 0

    var body: some View {
        let entries = shell.paletteEntries()
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "command").foregroundStyle(Theme.textMuted)
                TextField("", text: Binding(get: { shell.paletteQuery }, set: { shell.paletteQuery = $0; selected = 0 }),
                          prompt: Text("Type a command, or a path that starts with /").foregroundColor(Theme.textMuted))
                    .textFieldStyle(.plain).font(.system(size: 14)).focused($focused)
                    .onSubmit { if entries.indices.contains(selected) { entries[selected].run() } }
                KeyCap(text: "Esc")
            }
            .padding(14)
            Divider().overlay(Theme.hairline)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(entries.prefix(12).enumerated()), id: \.offset) { index, entry in
                        HStack {
                            Text(entry.title).font(.system(size: 12.5))
                            Spacer()
                            if !entry.key.isEmpty { KeyCap(text: entry.key) }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(index == selected ? Theme.surfaceRaised : Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { entry.run() }
                    }
                    if entries.isEmpty { Text("No command matches.").font(.system(size: 12)).foregroundStyle(Theme.textMuted).padding(14) }
                }
            }
            .frame(maxHeight: 340)
        }
        .foregroundStyle(Theme.textPrimary)
        .onAppear { focused = true }
        .onKeyPress(.downArrow) { selected = min(selected + 1, max(0, min(entries.count, 12) - 1)); return .handled }
        .onKeyPress(.upArrow) { selected = max(0, selected - 1); return .handled }
    }
}

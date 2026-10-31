import AppKit
import DYCore
import DYWorkspace

/// Builds the full menu bar. Items with a bare key (k, x, l) have no key equivalent here: those keys go through the key monitor.
@MainActor
enum MenuBuilder {
    /// Installs the menu bar for `shell`.
    static func install(shell: ShellState) {
        let main = NSMenu()
        main.addItem(submenu(appMenu(shell)))
        main.addItem(submenu(fileMenu(shell)))
        main.addItem(submenu(editMenu(shell)))
        main.addItem(submenu(markMenu(shell)))
        main.addItem(submenu(viewMenu(shell)))
        main.addItem(submenu(windowMenu()))
        NSApp.mainMenu = main
    }

    /// Wraps a menu in a top-level item.
    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    /// A command item that calls `shell.perform`.
    private static func item(_ title: String, _ command: ShellCommand, _ shell: ShellState, key: String = "",
                             modifiers: NSEvent.ModifierFlags = .command, enabled: @escaping @MainActor () -> Bool = { true }) -> NSMenuItem {
        ClosureItem(title: title, key: key, modifiers: modifiers, enabled: { MainActor.assumeIsolated { enabled() } }) { shell.perform(command) }
    }

    private static func appMenu(_ shell: ShellState) -> NSMenu {
        let menu = NSMenu(title: "DeepYellow")
        menu.addItem(withTitle: "About DeepYellow", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(item("Install Command Line Tool…", .installCLI, shell))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide DeepYellow", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        menu.addItem(withTitle: "Quit DeepYellow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private static func fileMenu(_ shell: ShellState) -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(item("Choose Folder to Scan…", .chooseFolder, shell, key: "o"))
        menu.addItem(item("Open Sample Disk", .openDemo, shell))
        menu.addItem(item("Rescan", .rescan, shell, key: "r", enabled: { if case .path? = shell.workspace.source { true } else { false } }))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        return menu
    }

    private static func editMenu(_ shell: ShellState) -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(ClosureItem(title: "Undo", key: "z") {
            if NSApp.keyWindow?.firstResponder is NSText { NSApp.sendAction(Selector(("undo:")), to: nil, from: nil) } else { shell.perform(.undo) }
        })
        menu.addItem(ClosureItem(title: "Redo", key: "z", modifiers: [.command, .shift]) {
            if NSApp.keyWindow?.firstResponder is NSText { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) } else { shell.perform(.redo) }
        })
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        menu.addItem(.separator())
        menu.addItem(item("Find in Query Field", .focusQuery, shell, key: "f"))
        menu.addItem(item("Command Palette…", .openPalette, shell, key: "k"))
        return menu
    }

    private static func markMenu(_ shell: ShellState) -> NSMenu {
        let menu = NSMenu(title: "Mark")
        let hasSelection: @MainActor () -> Bool = { shell.workspace.selectionCount > 0 || shell.workspace.review != nil }
        menu.addItem(item("Keep (k)", .mark(.keep), shell, enabled: hasSelection))
        menu.addItem(item("Mark for Removal (x)", .mark(.remove), shell, enabled: hasSelection))
        menu.addItem(item("Decide Later (l)", .mark(.later), shell, enabled: hasSelection))
        menu.addItem(item("Clear Mark (u)", .mark(.none), shell, enabled: hasSelection))
        menu.addItem(.separator())
        menu.addItem(item("Review the Current Set (r)", .review, shell))
        menu.addItem(item("Hide Selection (h)", .hide, shell, enabled: hasSelection))
        menu.addItem(.separator())
        menu.addItem(item("Open the Plan…", .openPlan, shell, key: "\r", enabled: { shell.workspace.tree != nil }))
        return menu
    }

    private static func viewMenu(_ shell: ShellState) -> NSMenu {
        let menu = NSMenu(title: "View")
        for (index, kind) in LensKind.allCases.enumerated() {
            menu.addItem(item(ShellCommand.lensTitle(kind), .lens(kind), shell, key: "\(index + 1)", enabled: { shell.workspace.tree != nil }))
        }
        menu.addItem(.separator())
        menu.addItem(item("Toggle Preview (Space)", .togglePreview, shell))
        menu.addItem(item("Size or File Count (m)", .toggleMetric, shell))
        menu.addItem(item("Cycle Colour Mode (c)", .cycleColor, shell))
        menu.addItem(item("Open the Ledger", .openLedger, shell, enabled: { shell.workspace.tree != nil }))
        menu.addItem(item("Show or Hide Shortcut Hints", .toggleHints, shell))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        NSApp.windowsMenu = menu
        return menu
    }
}

/// The Install Command Line Tool… dialog. Nothing is linked until the user clicks Install.
@MainActor
enum InstallPrompt {
    /// Explains what will happen, then links only after an explicit click.
    static func run() {
        guard let installer = CLIInstaller.forRunningApp() else { return alert("The command line tool can't be found.", "DeepYellow isn't running from an app bundle.") }
        let destination = CLIInstaller.defaultDirectory
        let prompt = NSAlert()
        prompt.messageText = "Install the deepyellow command?"
        prompt.informativeText = "This creates one symbolic link, \(destination.path)/deepyellow, pointing into this app. It needs no administrator rights and nothing else is changed. The command is read-only: it can list and report, never delete."
        prompt.addButton(withTitle: "Install in ~/.local/bin")
        prompt.addButton(withTitle: "Choose Another Folder…")
        prompt.addButton(withTitle: "Cancel")
        switch prompt.runModal() {
        case .alertFirstButtonReturn: report(installer.install(into: destination))
        case .alertSecondButtonReturn:
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.prompt = "Install Here"
            if panel.runModal() == .OK, let url = panel.url { report(installer.install(into: url)) }
        default: break
        }
    }

    /// Tells the user what happened.
    private static func report(_ outcome: CLIInstaller.Outcome) {
        switch outcome {
        case .installed(let link, let onPath):
            alert("Installed \(link)", onPath ? "Open a new terminal and run: deepyellow --version" : "That folder isn't on your PATH yet. Add it to your shell profile, or run the link by its full path.")
        case .alreadyInstalled(let link): alert("Already installed", "\(link) already points into this app.")
        case .refused(let reason): alert("Nothing was installed", reason)
        }
    }

    /// Shows a one-button message.
    private static func alert(_ title: String, _ detail: String) {
        let box = NSAlert()
        box.messageText = title
        box.informativeText = detail
        box.runModal()
    }
}

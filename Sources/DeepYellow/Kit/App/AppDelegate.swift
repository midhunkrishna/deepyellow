import AppKit
import DYCore
import DYLenses
import DYScan
import DYWorkspace
import SwiftUI

/// Starts the GUI. The real Trash mover is chosen here and nowhere else, only for a normal launch.
@MainActor
public enum GUILauncher {
    private static var delegate: AppDelegate?

    /// Runs the application until it quits. Returns the exit code.
    public static func run(options: LaunchOptions) -> Int32 {
        let directory = Composition.dataDirectory(options: options)
        let environment = Composition.environment(for: options, demoDirectory: directory)
        let workspace = Workspace(environment: environment)
        let fda: FullDiskAccess = options.shot != nil ? .denied : FullDiskAccess.probe()
        let shell = ShellState(workspace: workspace, isDemo: options.isDemo, isReadOnly: options.readOnly, fullDiskAccess: fda)
        let app = NSApplication.shared
        let appDelegate = AppDelegate(options: options, shell: shell)
        delegate = appDelegate
        app.delegate = appDelegate
        app.setActivationPolicy(options.shot != nil ? .prohibited : .regular)
        app.run()
        return 0
    }
}

/// Owns the window, the menu bar and the key monitor.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    let options: LaunchOptions
    let shell: ShellState
    var window: NSWindow?
    var keyMonitor: Any?

    /// Creates the delegate for one launch.
    init(options: LaunchOptions, shell: ShellState) {
        self.options = options
        self.shell = shell
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        if let name = options.shot {
            Task { @MainActor in
                let code = await ShotHarness.run(name: name, outPath: options.out, shell: shell, openPath: options.paths.first.flatMap(CLI.resolveFolder))
                exit(code)
            }
            return
        }
        MenuBuilder.install(shell: shell)
        makeWindow()
        installKeyMonitor()
        if let path = options.paths.first.flatMap(CLI.resolveFolder) { shell.open(path: path) } else if options.isDemo { shell.workspace.open(.demo) }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Opens folders handed over by Finder, the Dock, `open -a` or the CLI.
    public func application(_ application: NSApplication, open urls: [URL]) {
        guard let path = urls.compactMap({ CLI.resolveFolder($0.path) }).first else { return }
        shell.open(path: path)
        window?.makeKeyAndOrderFront(nil)
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Creates the main window with the toolbar-less, full-size-content look.
    private func makeWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1360, height: 860),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 980, height: 620)
        window.backgroundColor = NSColor(Theme.background)
        window.title = "DeepYellow"
        window.setFrameAutosaveName("DeepYellowMain")
        let host = NSHostingView(rootView: RootView(shell: shell))
        host.sizingOptions = []
        window.contentView = host
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    /// Routes plain keys to commands, except while a text field is being edited.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            return MainActor.assumeIsolated { self.handle(event) }
        }
    }

    /// Returns nil when the key was consumed.
    private func handle(_ event: NSEvent) -> NSEvent? {
        if event.type == .flagsChanged {
            shell.hintsHeld = event.modifierFlags.contains(.option)
            return event
        }
        guard event.window === window || event.window?.isKeyWindow == true else { return event }
        let typing = event.window?.firstResponder is NSText
        guard let command = KeyMap.command(characters: event.charactersIgnoringModifiers, keyCode: event.keyCode, flags: event.modifierFlags) else { return event }
        // Browse moves its own selection with the arrow keys, so one press must not move it twice.
        if case .move = command, shell.workspace.lensKind == .browse, shell.workspace.review == nil { return event }
        // Outside Review, ⌘C stays the ordinary Copy.
        if command == .copyReviewPath, shell.workspace.review == nil { return event }
        switch KeyRouter.route(command, typing: typing, sqlEditorFocused: event.window?.firstResponder is SQLTextView) {
        case .passThrough: return event
        case .leaveTextField:
            event.window?.makeFirstResponder(nil)
            if shell.sheet == .palette { shell.sheet = nil }
        case .perform(let routed): shell.perform(routed)
        }
        return nil
    }
}

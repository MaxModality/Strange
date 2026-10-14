import AppKit
import StrangeCore
import StrangeMac

@main @MainActor struct StrangeApp {
    static func main() {
        if CommandLine.arguments.dropFirst() == ["--version"] {
            print("0.4.1")
            return
        }
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.count == 2, arguments[0] == "--export-icons" {
            do {
                try StrangeIcon.export(to: URL(fileURLWithPath: arguments[1], isDirectory: true))
                print("Strange icon images exported.")
            } catch {
                print("Icon export failed.")
                exit(1)
            }
            return
        }
        let application = NSApplication.shared
        application.applicationIconImage = StrangeIcon.image(style: .application)
        application.setActivationPolicy(.accessory)
        if CommandLine.arguments.dropFirst() == ["--check-shortcuts"] {
            let keys = GlobalHotKeys { _ in }
            do {
                try keys.start()
                keys.stop()
                print("All \(HotKeyBinding.defaults.count) shortcuts registered and released.")
            } catch {
                print("Shortcut registration failed: \(error)")
                exit(1)
            }
            return
        }
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor private final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let manager = WindowManager()
    private var hotKeys: GlobalHotKeys?
    private var statusItem: NSStatusItem?
    private let status = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    private var activeTarget: WindowTarget?
    private lazy var placementQueue = makePlacementQueue()
    private var registrationFailure: String?
    private var queueFailure: String?
    private var placementMessage: String?

    private func makePlacementQueue() -> PlacementQueue {
        PlacementQueue(commandOperation: { [weak self, manager] command, processID in
            if self?.activeTarget == nil {
                let target = try await manager.captureActiveWindow(expectedProcessID: processID)
                try Task.checkCancellation()
                self?.activeTarget = target
            }
            try Task.checkCancellation()
            guard let target = self?.activeTarget else { throw CancellationError() }
            guard target.processID == processID else { throw PlacementError.focusChanged }
            _ = try await manager.performWindowCommand(target, command: command)
        }, onCommandSuccess: { [weak self] _ in
            self?.placementMessage = "Window placed."
        }, onFailure: { [weak self] error in
            self?.placementMessage = Self.message(for: error)
            if error is PlacementQueueError { self?.queueFailure = Self.message(for: error) }
            self?.refreshStatus()
        }, onIdle: { [weak self] in
            self?.activeTarget = nil
            self?.refreshStatus()
        })
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = StrangeIcon.image(style: .menuBar)
        item.button?.toolTip = "Strange"
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(NSMenuItem(title: "Strange 0.4.1", action: nil, keyEquivalent: ""))
        menu.addItem(status)
        menu.addItem(.separator())
        let permission = menu.addItem(withTitle: "Enable Accessibility Access…", action: #selector(requestPermission), keyEquivalent: "")
        permission.target = self
        let retry = menu.addItem(withTitle: "Retry Shortcut Registration", action: #selector(registerShortcuts), keyEquivalent: "")
        retry.target = self
        let shortcuts = NSMenuItem(title: "Shortcuts", action: nil, keyEquivalent: "")
        let shortcutMenu = NSMenu()
        for binding in HotKeyBinding.defaults {
            shortcutMenu.addItem(NSMenuItem(title: "\(binding.label) → \(binding.command.label)", action: nil, keyEquivalent: ""))
        }
        shortcuts.submenu = shortcutMenu
        menu.addItem(shortcuts)
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit Strange", action: #selector(quitApp), keyEquivalent: "")
        quit.target = self
        item.menu = menu
        statusItem = item
        registerShortcuts()
    }

    @objc private func registerShortcuts() {
        hotKeys?.stop()
        let keys = GlobalHotKeys { [weak self] command in self?.place(command) }
        do {
            try keys.start()
            hotKeys = keys
            registrationFailure = nil
            refreshStatus()
        } catch HotKeyError.registration(let shortcut, _) {
            hotKeys = nil
            registrationFailure = "Shortcut unavailable: \(shortcut)"
            refreshStatus()
        } catch {
            hotKeys = nil
            registrationFailure = "Could not register shortcuts. Try again."
            refreshStatus()
        }
    }

    private func place(_ command: WindowCommand) {
        guard WindowManager.hasAccessibilityPermission else {
            refreshStatus()
            return
        }
        guard let processID = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            placementMessage = "No active window is available."
            refreshStatus()
            return
        }
        if !placementQueue.isRunning { queueFailure = nil }
        placementMessage = nil
        status.title = "Placing window…"
        placementQueue.enqueue(command: command, processID: processID)
    }

    private static func message(for error: Error) -> String {
        if error is PlacementQueueError { return "Too many queued shortcuts; this press was not accepted." }
        return switch error as? PlacementError {
        case .accessibilityPermissionRequired: "Enable Accessibility access to move windows."
        case .focusChanged: "Focus changed; placement stopped."
        case .frameNotAccepted: "The app could not fit its window into this zone."
        case .unsupportedWindow: "This window cannot be moved or resized."
        case .noActiveWindow: "No active window is available."
        case .noDisplay: "No display is available."
        case .busy: "A placement is already in progress."
        default: "Window placement failed. Try again."
        }
    }

    private func refreshStatus() {
        if let registrationFailure {
            status.title = registrationFailure
        } else if !WindowManager.hasAccessibilityPermission {
            status.title = "Enable Accessibility access to move windows."
        } else if let queueFailure {
            status.title = queueFailure
        } else if placementQueue.isRunning {
            status.title = "Placing window…"
        } else {
            status.title = placementMessage ?? "Shortcuts ready."
        }
    }

    func menuWillOpen(_ menu: NSMenu) { refreshStatus() }

    @objc private func requestPermission() {
        _ = WindowManager.requestAccessibilityPermission()
        refreshStatus()
    }

    @objc private func quitApp() { NSApplication.shared.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        placementQueue.cancel()
        hotKeys?.stop()
        hotKeys = nil
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }
}

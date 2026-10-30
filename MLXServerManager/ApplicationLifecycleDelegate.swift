import AppKit

@MainActor
final class ApplicationLifecycleDelegate: NSObject, NSApplicationDelegate {
    weak var viewModel: AppViewModel?
    private var isSystemShutdownRequested = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceWillPowerOff(_:)),
            name: NSWorkspace.willPowerOffNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeMain(_:)),
            name: NSWindow.didBecomeMainNotification,
            object: nil
        )
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        restoreDockIconIfNeeded()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isSystemShutdownRequested else {
            return viewModel?.applicationShouldTerminateForSystemShutdownRequested() ?? .terminateNow
        }
        return viewModel?.applicationShouldTerminateRequested() ?? .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    /// Called when the menu bar icon is removed (e.g. ⌘-dragged out). If the Dock icon is hidden
    /// at that moment the app would be unreachable, so bring the Dock icon back.
    func menuBarIconWasRemoved() {
        restoreDockIconIfNeeded()
    }

    // MARK: - Last window closed

    @objc private func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, Self.isContentWindow(closing) else { return }
        // Evaluate after AppKit has finished closing the window.
        Task { @MainActor [weak self] in
            self?.handleWindowClosed(closing)
        }
    }

    @objc private func windowDidBecomeMain(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, Self.isContentWindow(window) else { return }
        restoreDockIconIfNeeded()
    }

    private func handleWindowClosed(_ closing: NSWindow) {
        guard let settings = viewModel?.settings else { return }
        let action = LastWindowCloseAction.resolve(
            backgroundOnLastWindowClose: settings.backgroundOnLastWindowClose,
            showMenuBarIcon: settings.showMenuBarIcon
        )
        guard action != .keepInDock else { return }

        let hasOtherWindows = NSApp.windows.contains { window in
            window !== closing
                && Self.isContentWindow(window)
                && (window.isVisible || window.isMiniaturized)
        }
        guard !hasOtherWindows else { return }

        switch action {
        case .hideDockIcon:
            NSApp.setActivationPolicy(.accessory)
        case .quit:
            // No menu bar icon to come back to: quit through the normal path
            // (same confirmation / server shutdown handling as ⌘Q).
            NSApp.terminate(nil)
        case .keepInDock:
            break
        }
    }

    private func restoreDockIconIfNeeded() {
        guard NSApp.activationPolicy() != .regular else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// The main app window, as opposed to the status item, sheets, panels and alerts.
    private static func isContentWindow(_ window: NSWindow) -> Bool {
        window.canBecomeMain
            && window.level == .normal
            && window.sheetParent == nil
            && !(window is NSPanel)
    }

    @objc private func workspaceWillPowerOff(_ notification: Notification) {
        isSystemShutdownRequested = true
    }
}

import AppKit

/// Single place that knows what "the main window" is and how the Dock icon is shown or hidden.
///
/// Used by the lifecycle delegate, the app commands and the menu bar view so they all agree
/// on which windows count and nothing outside this type touches the activation policy.
@MainActor
enum MainWindowPresenter {
    /// The main app window, as opposed to the status item, sheets, panels and alerts.
    static func isContentWindow(_ window: NSWindow) -> Bool {
        window.canBecomeMain
            && window.level == .normal
            && window.sheetParent == nil
            && !(window is NSPanel)
    }

    /// Brings an already-created main window to the front instead of opening a duplicate.
    /// Returns `true` when an existing window was shown.
    static func presentExistingWindow() -> Bool {
        let window = NSApplication.shared.windows.first { candidate in
            isContentWindow(candidate)
                && (candidate.isVisible || candidate.isMiniaturized)
        }
        guard let window else {
            return false
        }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        return true
    }

    /// Whether any main window other than `excluding` is still open (a minimized window counts).
    static func hasOtherContentWindows(excluding closing: NSWindow) -> Bool {
        NSApplication.shared.windows.contains { window in
            window !== closing
                && isContentWindow(window)
                && (window.isVisible || window.isMiniaturized)
        }
    }

    /// Hides the Dock icon; the app keeps running from the menu bar.
    static func hideDockIcon() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    /// Shows the Dock icon again if it was hidden. Returns `true` when the policy changed.
    @discardableResult
    static func restoreDockIconIfNeeded() -> Bool {
        guard NSApplication.shared.activationPolicy() != .regular else { return false }
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        return true
    }
}

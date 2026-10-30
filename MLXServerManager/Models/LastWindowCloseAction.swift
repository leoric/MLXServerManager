import Foundation

/// What happens when the last main window is closed.
nonisolated enum LastWindowCloseAction: Equatable, Sendable {
    /// Default: the app stays running with its Dock icon.
    case keepInDock
    /// Menu bar icon is on: hide the Dock icon and keep running in the menu bar.
    case hideDockIcon
    /// Menu bar icon is off: nothing could bring the app back, so quit.
    case quit

    static func resolve(backgroundOnLastWindowClose: Bool, showMenuBarIcon: Bool) -> LastWindowCloseAction {
        guard backgroundOnLastWindowClose else { return .keepInDock }
        return showMenuBarIcon ? .hideDockIcon : .quit
    }
}

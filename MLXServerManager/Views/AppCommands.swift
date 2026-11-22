import AppKit
import SwiftUI

/// Menu bar commands for the app.
///
/// Replaces the standard "Settings…" slot in the application menu so
/// Command-Comma opens the in-window Settings destination.
struct AppCommands: Commands {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button(AppCommandShortcut.openSettings.title(language: viewModel.settings.uiLanguage)) {
                openSettings()
            }
            .keyboardShortcut(
                AppCommandShortcut.openSettings.key,
                modifiers: AppCommandShortcut.openSettings.modifiers
            )
        }
    }

    private func openSettings() {
        viewModel.openSettingsRequested()
        if !MainWindowPresenter.presentExistingWindow() {
            openWindow(id: "main")
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

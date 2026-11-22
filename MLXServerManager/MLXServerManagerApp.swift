//
//  MLXServerManagerApp.swift
//  MLXServerManager
//
//  Created by yoinkun on 2026/06/11.
//

import SwiftUI

@main
struct MLXServerManagerApp: App {
    @NSApplicationDelegateAdaptor(ApplicationLifecycleDelegate.self) private var applicationDelegate
    @StateObject private var viewModel = AppViewModel()
    @StateObject private var externalMonitor = ExternalServerMonitor()

    var body: some Scene {
        WindowGroup("MLX Server Manager", id: "main") {
            ContentView(viewModel: viewModel)
                .onAppear {
                    applicationDelegate.viewModel = viewModel
                }
        }
        .defaultSize(width: 1280, height: 820)
        .windowStyle(.hiddenTitleBar)
        .commands {
            AppCommands(viewModel: viewModel)
        }

        MenuBarExtra(isInserted: showMenuBarIcon) {
            MenuBarView(viewModel: viewModel, externalMonitor: externalMonitor)
        } label: {
            Image(systemName: viewModel.menuBarIconState
                .withExternalServers(!externalMonitor.servers.isEmpty)
                .symbolName)
                .accessibilityLabel(viewModel.menuBarTitle)
        }
    }

    /// Driven by the setting; also written back if the user removes the icon with ⌘-drag.
    private var showMenuBarIcon: Binding<Bool> {
        Binding(
            get: { viewModel.settings.showMenuBarIcon },
            set: { newValue in
                viewModel.menuBarIconVisibilityChanged(newValue)
                if !newValue {
                    // Whatever the save outcome, the icon is gone for now: keep the app reachable.
                    MainWindowPresenter.restoreDockIconIfNeeded()
                }
            }
        )
    }
}

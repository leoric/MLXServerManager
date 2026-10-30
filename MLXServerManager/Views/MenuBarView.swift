import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var externalMonitor: ExternalServerMonitor
    @Environment(\.openWindow) private var openWindow

    private var strings: AppLocalization {
        AppLocalization(language: viewModel.settings.uiLanguage)
    }

    private func t(_ english: String, _ japanese: String) -> String {
        strings.text(english: english, japanese: japanese)
    }

    /// The managed-server status says "Stopped" for a server the app didn't start.
    /// Only in that case, report the outside server instead.
    private var outsideServerOnly: ExternalServerProcess? {
        guard case .stopped = viewModel.runtimeState,
              viewModel.runningModelIDs.isEmpty
        else { return nil }
        return externalMonitor.servers.first
    }

    private var menuBarTitle: String {
        if outsideServerOnly != nil {
            return t("MLX: Running outside the app", "MLX: アプリ外で実行中")
        }
        return viewModel.menuBarTitle
    }

    private var menuBarDetail: String {
        if let server = outsideServerOnly {
            return externalServerSummary(server)
        }
        return viewModel.runtimeState.localizedBadgeDetail(language: viewModel.settings.uiLanguage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(menuBarTitle)
                .font(.headline)

            Text(menuBarDetail)
                .font(.caption)
                .foregroundStyle(.secondary)

            if viewModel.runningModelIDs.count > 1 {
                Text(viewModel.runningModelText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button(strings.text(.start)) {
                viewModel.startRequested()
            }
            .disabled(!viewModel.canStartSelectedModel)

            Button(strings.text(.stop)) {
                viewModel.stopRequested()
            }
            .disabled(!viewModel.canStopManagedServer)

            Button(strings.text(.restart)) {
                viewModel.restartRequested()
            }
            .disabled(!viewModel.canRestartManagedServer)

            if viewModel.canAdoptExternalServer {
                Button(t("Adopt External Server", "外部サーバーを採用")) {
                    viewModel.adoptExternalServerRequested()
                }
            }

            if viewModel.canForgetExternalServer {
                Button(t("Forget External Server", "外部サーバーを解除")) {
                    viewModel.forgetExternalServerRequested()
                }
            }

            Button(strings.text(.runDiagnostics)) {
                viewModel.runDiagnosticsRequested()
            }
            .disabled(viewModel.isDiagnosticsRunning)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text(t("Connection Settings", "接続設定"))
                    .font(.caption.weight(.semibold))
                Text(viewModel.baseURL)
                    .font(.caption)
                    .textSelection(.enabled)
                Text(viewModel.selectedModelIdentifier)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            if !externalMonitor.servers.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("Running outside the app", "アプリ外で実行中"))
                        .font(.caption.weight(.semibold))
                    ForEach(externalMonitor.servers) { server in
                        Text(externalServerSummary(server))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            Button(t("Manage…", "管理…")) {
                openMainWindow()
            }

            Divider()

            Button(t("Quit", "終了")) {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.vertical, 6)
        .frame(width: 280, alignment: .leading)
    }

    private func externalServerSummary(_ server: ExternalServerProcess) -> String {
        var parts = [server.backend.localizedTitle(language: viewModel.settings.uiLanguage)]
        if let port = server.port {
            parts.append(":\(port)")
        }
        if let model = server.model {
            parts.append(model)
        }
        parts.append("pid \(server.processIdentifier)")
        return parts.joined(separator: " · ")
    }

    private func openMainWindow() {
        // The Dock icon is hidden while only the menu bar icon is running.
        NSApplication.shared.setActivationPolicy(.regular)
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

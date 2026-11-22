import Foundation

/// Keeps a live list of inference servers running outside the app.
/// Polls the process table while scanning is enabled; cheap (one `ps` every few seconds).
///
/// Scanning is only useful while something displays the result, so it can be switched off
/// (the menu bar icon is the only consumer). While disabled the loop only wakes up to check
/// again and spawns no processes.
@MainActor
final class ExternalServerMonitor: ObservableObject {
    @Published private(set) var servers: [ExternalServerProcess] = []

    /// Asked before every scan. Defaults to always scanning.
    var isScanningEnabled: @MainActor () -> Bool = { true }

    private let scan: @Sendable () async -> [ExternalServerProcess]

    /// - Parameters:
    ///   - interval: time between scans.
    ///   - startsPolling: pass `false` to drive `refresh()` by hand (tests).
    ///   - scan: the process scan; replaceable so tests need no real processes.
    init(
        interval: Duration = .seconds(5),
        startsPolling: Bool = true,
        scan: @escaping @Sendable () async -> [ExternalServerProcess] = { await ExternalServerScanner.scan() }
    ) {
        self.scan = scan
        guard startsPolling else { return }
        Task { [weak self] in
            while !Task.isCancelled {
                // Don't hold `self` across the sleep, so the loop ends if the monitor goes away.
                guard (await self?.refresh()) != nil else { return }
                try? await Task.sleep(for: interval)
            }
        }
    }

    func refresh() async {
        guard isScanningEnabled() else {
            if !servers.isEmpty {
                servers = []
            }
            return
        }
        let scanned = await scan()
        // The setting may have been switched off while the scan was running.
        guard isScanningEnabled() else {
            if !servers.isEmpty {
                servers = []
            }
            return
        }
        if scanned != servers {
            servers = scanned
        }
    }
}

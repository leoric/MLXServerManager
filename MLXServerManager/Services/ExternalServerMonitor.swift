import Foundation

/// Keeps a live list of inference servers running outside the app.
/// Polls the process table for as long as the app is alive; cheap (one `ps` every few seconds).
@MainActor
final class ExternalServerMonitor: ObservableObject {
    @Published private(set) var servers: [ExternalServerProcess] = []

    init(interval: Duration = .seconds(5)) {
        Task { [weak self] in
            while !Task.isCancelled {
                // Don't hold `self` across the sleep, so the loop ends if the monitor goes away.
                guard (await self?.refresh()) != nil else { return }
                try? await Task.sleep(for: interval)
            }
        }
    }

    func refresh() async {
        let scanned = await ExternalServerScanner.scan()
        if scanned != servers {
            servers = scanned
        }
    }
}

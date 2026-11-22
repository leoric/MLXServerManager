import XCTest
@testable import MLXServerManager

/// The monitor only scans while something displays the result. Uses a fake scan, so nothing
/// here starts a process.
@MainActor
final class ExternalServerMonitorTests: XCTestCase {
    private actor ScanCounter {
        private(set) var count = 0
        func increment() { count += 1 }
    }

    private let server = ExternalServerProcess(
        processIdentifier: 700,
        backend: .rapidMLX,
        port: 8080,
        model: "m"
    )

    private func makeMonitor(counter: ScanCounter) -> ExternalServerMonitor {
        let server = server
        return ExternalServerMonitor(startsPolling: false) {
            await counter.increment()
            return [server]
        }
    }

    func testRefreshPublishesScanResultWhenEnabled() async {
        let counter = ScanCounter()
        let monitor = makeMonitor(counter: counter)

        await monitor.refresh()

        XCTAssertEqual(monitor.servers, [server])
        let count = await counter.count
        XCTAssertEqual(count, 1)
    }

    func testDisabledMonitorDoesNotScanAndClearsServers() async {
        let counter = ScanCounter()
        let monitor = makeMonitor(counter: counter)
        await monitor.refresh()
        XCTAssertFalse(monitor.servers.isEmpty)

        monitor.isScanningEnabled = { false }
        await monitor.refresh()

        XCTAssertEqual(monitor.servers, [])
        let count = await counter.count
        XCTAssertEqual(count, 1, "no further scan while disabled")
    }

    func testScanningResumesWhenReEnabled() async {
        let counter = ScanCounter()
        let monitor = makeMonitor(counter: counter)
        monitor.isScanningEnabled = { false }
        await monitor.refresh()

        monitor.isScanningEnabled = { true }
        await monitor.refresh()

        XCTAssertEqual(monitor.servers, [server])
        let count = await counter.count
        XCTAssertEqual(count, 1)
    }
}

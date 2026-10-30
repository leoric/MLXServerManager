import XCTest
@testable import MLXServerManager

/// The menu bar icon is `.on` when any profile is serving (Rapid-MLX or mlx_lm alike),
/// `.busy` while profiles are starting/stopping, `.external` when only a server outside
/// the app is running, and `.off` otherwise.
@MainActor
final class MenuBarIconStateTests: XCTestCase {
    private let host = "127.0.0.1"

    private func profile(
        _ state: ModelRuntimeState,
        running: Bool = false,
        transitioning: Bool = false
    ) -> MenuBarProfileSnapshot {
        MenuBarProfileSnapshot(runtimeState: state, isProcessRunning: running, isTransitioning: transitioning)
    }

    // MARK: - Symbols

    func testEachStateHasItsOwnSymbol() {
        XCTAssertEqual(MenuBarIconState.off.symbolName, "bolt.circle")
        XCTAssertEqual(MenuBarIconState.on.symbolName, "bolt.circle.fill")
        XCTAssertEqual(MenuBarIconState.busy.symbolName, "arrow.triangle.2.circlepath.circle")
        XCTAssertEqual(MenuBarIconState.external.symbolName, "arrow.up.right.circle")

        let symbols: [MenuBarIconState] = [.off, .on, .busy, .external]
        XCTAssertEqual(Set(symbols.map(\.symbolName)).count, symbols.count, "symbols must be distinguishable")
    }

    // MARK: - Managed state

    func testNoProfilesIsOff() {
        XCTAssertEqual(MenuBarIconState.resolve(profiles: []), .off)
    }

    func testStoppedProfilesAreOff() {
        let profiles = [profile(.stopped), profile(.stopped)]
        XCTAssertEqual(MenuBarIconState.resolve(profiles: profiles), .off)
    }

    func testReadyProfileIsOn() {
        let state = ModelRuntimeState.ready(host: host, port: 8080, processIdentifier: 42)
        XCTAssertEqual(MenuBarIconState.resolve(profiles: [profile(state, running: true)]), .on)
    }

    func testDegradedProfileIsStillOn() {
        let state = ModelRuntimeState.degraded(host: host, port: 8080, processIdentifier: 42, message: "slow")
        XCTAssertEqual(MenuBarIconState.resolve(profiles: [profile(state, running: true)]), .on)
    }

    func testAdoptedExternalServerCountsAsOn() {
        let state = ModelRuntimeState.adoptedExternalServer(
            host: host, port: 8080, baseURL: "http://127.0.0.1:8080", message: "adopted"
        )
        XCTAssertEqual(MenuBarIconState.resolve(profiles: [profile(state)]), .on)
    }

    func testLiveProcessWithOtherStateIsOn() {
        // A process the app started is alive even though readiness has not been confirmed.
        let state = ModelRuntimeState.readyCheckFailed(host: host, port: 8080, message: "no answer")
        XCTAssertEqual(MenuBarIconState.resolve(profiles: [profile(state, running: true)]), .on)
    }

    func testDetectedButNotAdoptedServerIsNotOn() {
        let detected = ModelRuntimeState.externalServerDetected(
            host: host, port: 8080, baseURL: "http://127.0.0.1:8080", message: "found"
        )
        let busyPort = ModelRuntimeState.portBusy(host: host, port: 8081)
        XCTAssertEqual(MenuBarIconState.resolve(profiles: [profile(detected), profile(busyPort)]), .off)
    }

    func testErrorWithoutProcessIsOff() {
        XCTAssertEqual(MenuBarIconState.resolve(profiles: [profile(.error(message: "boom"))]), .off)
    }

    // MARK: - Busy

    func testStartingProfileIsBusy() {
        let state = ModelRuntimeState.starting(host: host, port: 8080)
        XCTAssertEqual(MenuBarIconState.resolve(profiles: [profile(state, transitioning: true)]), .busy)
    }

    func testLoadingProfileWithLiveProcessIsBusyNotOn() {
        let state = ModelRuntimeState.loading(host: host, port: 8080, processIdentifier: 42)
        XCTAssertEqual(
            MenuBarIconState.resolve(profiles: [profile(state, running: true, transitioning: true)]),
            .busy
        )
    }

    func testStoppingProfileIsBusy() {
        let state = ModelRuntimeState.stopping(processIdentifier: 42)
        XCTAssertEqual(
            MenuBarIconState.resolve(profiles: [profile(state, running: true, transitioning: true)]),
            .busy
        )
    }

    func testServingProfileWinsOverTransitioningProfile() {
        let serving = ModelRuntimeState.ready(host: host, port: 8080, processIdentifier: 1)
        let loading = ModelRuntimeState.loading(host: host, port: 8081, processIdentifier: 2)
        let profiles = [
            profile(loading, running: true, transitioning: true),
            profile(serving, running: true),
        ]
        XCTAssertEqual(MenuBarIconState.resolve(profiles: profiles), .on)
    }

    // MARK: - Servers outside the app

    func testExternalServersOnlyChangeAnIdleIcon() {
        XCTAssertEqual(MenuBarIconState.off.withExternalServers(true), .external)
        XCTAssertEqual(MenuBarIconState.off.withExternalServers(false), .off)
        XCTAssertEqual(MenuBarIconState.on.withExternalServers(true), .on)
        XCTAssertEqual(MenuBarIconState.busy.withExternalServers(true), .busy)
        XCTAssertEqual(MenuBarIconState.external.withExternalServers(false), .external)
    }
}

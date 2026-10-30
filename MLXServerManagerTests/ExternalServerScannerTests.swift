import XCTest
@testable import MLXServerManager

/// Detection of `rapid-mlx` / `mlx_lm` servers running outside the app. Uses canned `ps` and
/// `lsof` output, so nothing here starts a process.
@MainActor
final class ExternalServerScannerTests: XCTestCase {
    private let ownPID: Int32 = 500

    /// Homebrew and python.org Python show up in `ps` as `.../Python.app/Contents/MacOS/Python`.
    private let homebrewPython =
        "/opt/homebrew/Cellar/python@3.12/3.12.8/Frameworks/Python.framework/Versions/3.12/Resources/Python.app/Contents/MacOS/Python"

    /// Runs the same steps as `ExternalServerScanner.scan()` with canned process-table and
    /// listening-socket results. `listening == nil` means `lsof` was unavailable.
    private func detect(_ ps: String, listening: [Int32: [Int]]?) -> [ExternalServerProcess] {
        let rows = ExternalServerScanner.parseProcessTable(ps)
        let candidates = ExternalServerScanner.candidates(in: rows, ownProcessIdentifier: ownPID)
        return ExternalServerScanner.resolve(candidates: candidates, listeningPorts: listening)
    }

    // MARK: - Detection

    func testDetectsRapidMLXRunningOnHomebrewPython() {
        let ps = """
          500     1 /Applications/MLXServerManager.app/Contents/MacOS/MLXServerManager
          700   300 \(homebrewPython) /Users/me/.local/bin/rapid-mlx serve mlx-community/Qwen3 --port 8080
        """

        let servers = detect(ps, listening: [700: [8080]])

        XCTAssertEqual(servers, [
            ExternalServerProcess(
                processIdentifier: 700,
                backend: .rapidMLX,
                port: 8080,
                model: "mlx-community/Qwen3"
            ),
        ])
    }

    func testDetectsMLXLMInItsCommonForms() {
        let ps = """
          800   300 /opt/homebrew/bin/python3 -m mlx_lm.server --model mlx-community/Qwen3-8B-4bit --port=8081
          810   300 /Users/me/.venv/bin/mlx_lm.server --model foo
          820   300 /Users/me/.venv/bin/python3 -m mlx_lm server --model bar
          830   300 /bin/bash /opt/homebrew/bin/mlx_lm.server --model baz
        """

        let servers = detect(ps, listening: [800: [8081], 810: [8082], 820: [8083], 830: [8084]])

        XCTAssertEqual(servers.map(\.processIdentifier), [800, 810, 820, 830])
        XCTAssertTrue(servers.allSatisfy { $0.backend == .mlxLM })
        XCTAssertEqual(servers.map(\.port), [8081, 8082, 8083, 8084])
        XCTAssertEqual(servers.map(\.model), ["mlx-community/Qwen3-8B-4bit", "foo", "bar", "baz"])
    }

    func testDetectsRapidMLXThroughUV() {
        let ps = "  900   300 uv run rapid-mlx serve qwen3-0.6b"

        let servers = detect(ps, listening: [900: [8000]])

        XCTAssertEqual(servers.first?.backend, .rapidMLX)
        XCTAssertEqual(servers.first?.model, "qwen3-0.6b")
        XCTAssertEqual(servers.first?.port, 8000, "the listening port is used even without --port")
    }

    func testResultsAreSortedAndUseLowestListeningPort() {
        let ps = """
          900   300 /Users/me/.venv/bin/mlx_lm.server --model b
          700   300 /Users/me/.venv/bin/rapid-mlx serve a
        """

        let servers = detect(ps, listening: [900: [9001], 700: [8002, 8001]])

        XCTAssertEqual(servers.map(\.processIdentifier), [700, 900])
        XCTAssertEqual(servers.first?.port, 8001)
    }

    // MARK: - What must not be reported

    func testServersStartedByTheAppAreIgnored() {
        let ps = """
          500     1 /Applications/MLXServerManager.app/Contents/MacOS/MLXServerManager
          610   500 /x/bin/python3 /x/bin/rapid-mlx serve managed --port 8001
          620   610 /x/bin/python3 /x/bin/rapid-mlx serve managed --port 8001
        """

        XCTAssertEqual(detect(ps, listening: [610: [8001], 620: [8001]]), [])
    }

    func testForkedWorkersAreListedOnce() {
        let ps = """
          700   300 \(homebrewPython) /Users/me/.local/bin/rapid-mlx serve m --port 8080
          701   700 \(homebrewPython) /Users/me/.local/bin/rapid-mlx serve m --port 8080
          702   700 /x/bin/python3 -c from multiprocessing.resource_tracker import main;main(5)
        """

        let servers = detect(ps, listening: [700: [8080], 701: [8080]])

        XCTAssertEqual(servers.map(\.processIdentifier), [700])
    }

    func testProcessesThatAreNotListeningAreIgnored() {
        let ps = """
          901   300 /Users/me/.venv/bin/rapid-mlx --help
          902   300 /Users/me/.venv/bin/rapid-mlx models
          903   300 grep rapid-mlx
          904   300 /Users/me/.venv/bin/pip install rapid-mlx
        """

        XCTAssertEqual(detect(ps, listening: [:]), [])
    }

    func testUnrelatedProcessesMentioningRapidMLXAreIgnored() {
        let ps = """
          910   300 /Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper (Plugin).app/x --folder /Users/me/pro/rapid-mlx
          911   300 /usr/bin/vim notes-rapid-mlx-serve.md
          912   300 tmux new-session rapid-mlx serve foo
        """

        XCTAssertEqual(detect(ps, listening: [910: [51234], 911: [1], 912: [2]]), [])
    }

    // MARK: - When lsof is unavailable

    func testFallsBackToStrictCommandLineMatching() {
        let ps = """
          700   300 /Users/me/.venv/bin/rapid-mlx serve m --port 8001
          701   300 /Users/me/.venv/bin/rapid-mlx --help
          702   300 /bin/bash /opt/homebrew/bin/some-wrapper rapid-mlx
        """

        let servers = detect(ps, listening: nil)

        XCTAssertEqual(servers.map(\.processIdentifier), [700])
        XCTAssertEqual(servers.first?.port, 8001, "the --port argument is used as a fallback")
    }

    // MARK: - Parsing

    func testParsesProcessTableAndSkipsMalformedLines() {
        let rows = ExternalServerScanner.parseProcessTable("""
            1     0 /sbin/launchd
          222   111   /usr/bin/python3   -m   mlx_lm.server
        not-a-row
          333
        """)

        XCTAssertEqual(rows.map(\.pid), [1, 222])
        XCTAssertEqual(rows.map(\.ppid), [0, 111])
        XCTAssertEqual(rows[1].command, "/usr/bin/python3   -m   mlx_lm.server")
    }

    func testParsesLsofFieldOutput() {
        let output = """
        p700
        f12
        n127.0.0.1:8080
        p903
        n*:8081
        n[::1]:8082
        """

        XCTAssertEqual(
            ExternalServerScanner.parseListeningPorts(output),
            [700: [8080], 903: [8081, 8082]]
        )
    }

    func testParsingEmptyLsofOutputFindsNothing() {
        XCTAssertEqual(ExternalServerScanner.parseListeningPorts(""), [:])
    }
}

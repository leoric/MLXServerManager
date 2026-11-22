#!/usr/bin/env bash
#
# Run the Rapid-MLX `serve --help` probe checks WITHOUT Xcode — only the Command Line
# Tools are needed. Builds a temporary SwiftPM harness under build/clt-tests that compiles
# the app sources (minus the @main file and the asset catalog); nothing in the repository
# is modified.
#
# Usage:
#   scripts/run_tests_clt.sh [--check | --xctest] [TestFile.swift ...]
#
# Modes:
#   (default)  Use XCTest if this toolchain has it, otherwise fall back to --check.
#   --xctest   Run MLXServerManagerTests/<TestFile> with `swift test`
#              (default file: RapidMLXServeHelpProbeTests.swift). Needs XCTest.
#   --check    Run a standalone executable that performs the same scenarios as
#              RapidMLXServeHelpProbeTests against the real app code, with no test
#              framework. The Command Line Tools alone do not ship XCTest on every setup.
#
# This is a quick check. The full suite, static analysis and release build described in
# AGENTS.md still need Xcode.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS="$ROOT/build/clt-tests"
MODE="auto"
TESTS=()

die() { echo "error: $*" >&2; exit 1; }

while (( $# )); do
  case "$1" in
    --check)  MODE="check" ;;
    --xctest) MODE="xctest" ;;
    -h|--help) sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)       die "unknown option: $1" ;;
    *)        TESTS+=("$1") ;;
  esac
  shift
done
(( ${#TESTS[@]} )) || TESTS=("RapidMLXServeHelpProbeTests.swift")

[[ "$(uname -s)" == "Darwin" ]] || die "must be run on macOS"
command -v swift >/dev/null 2>&1 || die "swift not found — run: xcode-select --install"
[[ -d "$ROOT/MLXServerManager" ]] || die "MLXServerManager/ not found (run from the repository root)"

has_xctest() {
  local dev
  dev="$(xcode-select -p 2>/dev/null)" || return 1
  [[ -d "$dev/Library/Developer/Frameworks/XCTest.framework" \
    || -d "$dev/Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework" ]]
}

if [[ "$MODE" == "auto" ]]; then
  if has_xctest; then MODE="xctest"; else MODE="check"; echo "XCTest not found in $(xcode-select -p); using --check"; fi
fi

rm -rf "$HARNESS"
mkdir -p "$HARNESS/Tests" "$HARNESS/Check"
ln -s "$ROOT/MLXServerManager" "$HARNESS/App"
for test in "${TESTS[@]}"; do
  [[ -f "$ROOT/MLXServerManagerTests/$test" ]] || die "test file not found: MLXServerManagerTests/$test"
  ln -s "$ROOT/MLXServerManagerTests/$test" "$HARNESS/Tests/$test"
done

# Same concurrency settings as the Xcode project (see scripts/build_app_clt.sh).
cat > "$HARNESS/Package.swift" <<'SWIFT'
// swift-tools-version: 6.2
import PackageDescription

let settings: [SwiftSetting] = [
    .swiftLanguageMode(.v5),
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("DisableOutwardActorInference"),
    .enableUpcomingFeature("GlobalActorIsolatedTypesUsability"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("InferSendableFromCaptures"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

let package = Package(
    name: "MLXServerManagerCLTTests",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "MLXServerManager",
            path: "App",
            exclude: ["Assets.xcassets", "MLXServerManagerApp.swift"],
            swiftSettings: settings
        ),
        .executableTarget(
            name: "ProbeCheck",
            dependencies: ["MLXServerManager"],
            path: "Check",
            swiftSettings: settings
        ),
        .testTarget(
            name: "MLXServerManagerTests",
            dependencies: ["MLXServerManager"],
            path: "Tests",
            swiftSettings: settings
        ),
    ]
)
SWIFT

# Framework-free mirror of RapidMLXServeHelpProbeTests.
cat > "$HARNESS/Check/main.swift" <<'SWIFT'
import Foundation
@testable import MLXServerManager

var failures = 0

func check(_ condition: Bool, _ message: String) {
    if condition {
        print("  ok    \(message)")
    } else {
        failures += 1
        print("  FAIL  \(message)")
    }
}

struct FakeRuntime {
    let executablePath: String
    let invocationLogPath: String

    func invocations() -> [String] {
        guard let contents = try? String(contentsOfFile: invocationLogPath, encoding: .utf8) else { return [] }
        return contents.split(separator: "\n").map(String.init)
    }
}

/// Mimics Rapid-MLX's help layout: `--no-thinking` is only listed under `serve --help`.
func makeFakeRuntime(in directory: URL, serveHelpSucceeds: Bool = true) throws -> FakeRuntime {
    let executablePath = directory.appendingPathComponent("rapid-mlx").path
    let logPath = directory.appendingPathComponent("invocations.log").path
    let serveHelp = serveHelpSucceeds
        ? "echo \"usage: rapid-mlx serve [--host HOST] [--port PORT] [--no-thinking]\""
        : "echo \"serve help unavailable\" >&2; exit 2"
    let script = """
    #!/bin/sh
    echo "$*" >> '\(logPath)'
    case "$1" in
    --version)
      echo "rapid-mlx 0.16.10"
      ;;
    --help)
      echo "usage: rapid-mlx [--version] [--help] {serve,chat}"
      ;;
    serve)
      if [ "$2" = "--help" ]; then
        \(serveHelp)
      fi
      ;;
    esac

    """
    try script.write(toFile: executablePath, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executablePath)
    return FakeRuntime(executablePath: executablePath, invocationLogPath: logPath)
}

let base = FileManager.default.temporaryDirectory
    .appendingPathComponent("rapid-mlx-help-probe-check-\(UUID().uuidString)", isDirectory: true)

func scenario(_ name: String, _ body: (URL) async throws -> Void) async {
    print(name)
    let directory = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try await body(directory)
    } catch {
        failures += 1
        print("  FAIL  threw \(error)")
    }
}

await scenario("Rapid-MLX probe includes serve-only flags") { directory in
    let runtime = try makeFakeRuntime(in: directory)
    let provider = RuntimeOptionCapabilityProvider(timeout: 5)
    let result = await provider.capabilities(executablePath: runtime.executablePath, backend: .rapidMLX)
    guard case let .available(flags) = result else { return check(false, "flags detected (got \(result))") }
    check(flags.contains("--no-thinking"), "serve-only flag --no-thinking detected")
    check(flags.contains("--host"), "--host detected")
    check(flags.contains("--version"), "top-level flags still merged in")
    check(runtime.invocations() == ["--help", "serve --help"], "ran --help then serve --help (got \(runtime.invocations()))")
}

await scenario("mlx-lm probe only runs top-level help") { directory in
    let runtime = try makeFakeRuntime(in: directory)
    let provider = RuntimeOptionCapabilityProvider(timeout: 5)
    let result = await provider.capabilities(executablePath: runtime.executablePath, backend: .mlxLM)
    guard case let .available(flags) = result else { return check(false, "flags detected (got \(result))") }
    check(!flags.contains("--no-thinking"), "--no-thinking not reported for mlx-lm")
    check(runtime.invocations() == ["--help"], "never ran serve --help (got \(runtime.invocations()))")
}

await scenario("Failing serve --help keeps top-level flags") { directory in
    let runtime = try makeFakeRuntime(in: directory, serveHelpSucceeds: false)
    let provider = RuntimeOptionCapabilityProvider(timeout: 5)
    let result = await provider.capabilities(executablePath: runtime.executablePath, backend: .rapidMLX)
    guard case let .available(flags) = result else { return check(false, "flags still detected (got \(result))") }
    check(flags.contains("--version"), "top-level flags kept")
    check(!flags.contains("--no-thinking"), "--no-thinking absent")
    check(runtime.invocations() == ["--help", "serve --help"], "both invocations attempted (got \(runtime.invocations()))")
}

await scenario("Probe results are cached per backend") { directory in
    let runtime = try makeFakeRuntime(in: directory)
    let provider = RuntimeOptionCapabilityProvider(timeout: 5)
    let mlxLM = await provider.capabilities(executablePath: runtime.executablePath, backend: .mlxLM)
    let rapid = await provider.capabilities(executablePath: runtime.executablePath, backend: .rapidMLX)
    let rapidAgain = await provider.capabilities(executablePath: runtime.executablePath, backend: .rapidMLX)
    guard case let .available(mlxLMFlags) = mlxLM, case let .available(rapidFlags) = rapid else {
        return check(false, "both probes detected flags")
    }
    check(!mlxLMFlags.contains("--no-thinking"), "mlx-lm result lacks --no-thinking")
    check(rapidFlags.contains("--no-thinking"), "mlx-lm cache entry not reused for Rapid-MLX")
    check(rapidAgain == rapid, "repeat Rapid-MLX probe returns the same result")
    check(runtime.invocations() == ["--help", "--help", "serve --help"], "repeat probe served from cache (got \(runtime.invocations()))")
}

await scenario("Missing executable is unavailable") { directory in
    let provider = RuntimeOptionCapabilityProvider(timeout: 5)
    let result = await provider.capabilities(
        executablePath: directory.appendingPathComponent("does-not-exist").path,
        backend: .rapidMLX
    )
    check(result == .unavailable, "unavailable")
}

await scenario("Compatibility matrix detects reasoning control from serve --help") { directory in
    let runtime = try makeFakeRuntime(in: directory)
    var settings = AppSettings.defaults
    settings.rapidMLXExecutablePath = runtime.executablePath
    let reports = await RuntimeCompatibilityService(timeout: 5).assess(settings: settings)
    guard let report = reports.first(where: { $0.backend == .rapidMLX }) else {
        return check(false, "Rapid-MLX report present")
    }
    check(report.supportedFlags?.contains("--no-thinking") == true, "supported flags include --no-thinking")
    let reasoning = report.features.first { $0.feature == .reasoningControl }
    check(reasoning?.support == .supported, "reasoning control supported")
    check(reasoning?.detectedFlags == ["--no-thinking"], "detected flag is --no-thinking")
}

try? FileManager.default.removeItem(at: base)
print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
SWIFT

cd "$HARNESS"
if [[ "$MODE" == "xctest" ]]; then
  exec swift test
else
  exec swift run ProbeCheck
fi

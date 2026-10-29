import Darwin
import Foundation

/// An `mlx_lm.server` or `rapid-mlx serve` process that was NOT started by this app.
nonisolated struct ExternalServerProcess: Identifiable, Hashable, Sendable {
    let processIdentifier: Int32
    let backend: InferenceBackend
    /// The TCP port the process is listening on (from `lsof`), or the `--port` argument as a fallback.
    let port: Int?
    let model: String?

    var id: Int32 { processIdentifier }
}

/// Finds inference servers running outside the app.
///
/// 1. Read the process table (`ps`) and keep processes whose command line looks like
///    Rapid-MLX or mlx-lm, launched directly or through Python / uv / a shell wrapper.
/// 2. Confirm with `lsof` that they are actually LISTENing on a TCP port, which weeds out
///    `rapid-mlx --help`, `pip install`, editors, `grep` and so on, and gives the real port.
///    If `lsof` can't run, fall back to a stricter command-line match (`rapid-mlx serve`, …).
///
/// Servers started by the app are descendants of the app's own process and are ignored.
nonisolated enum ExternalServerScanner {
    struct ProcessRow: Equatable, Sendable {
        let pid: Int32
        let ppid: Int32
        let command: String
    }

    static func scan() async -> [ExternalServerProcess] {
        guard let result = await ShortLivedProcessRunner.runAsync(
            executablePath: "/bin/ps",
            arguments: ["-axww", "-o", "pid=,ppid=,command="],
            timeout: 3
        ),
            !result.timedOut,
            !result.cancelled,
            result.terminationStatus == 0,
            let output = String(data: result.standardOutput, encoding: .utf8)
        else {
            return []
        }

        let rows = parseProcessTable(output)
        let candidates = candidates(in: rows, ownProcessIdentifier: getpid())
        guard !candidates.isEmpty else { return [] }

        let ports = await listeningPorts(for: candidates.map(\.pid))
        return resolve(candidates: candidates, listeningPorts: ports)
    }

    // MARK: - Pure steps (no I/O)

    static func parseProcessTable(_ psOutput: String) -> [ProcessRow] {
        psOutput.split(whereSeparator: \.isNewline).compactMap(parseRow)
    }

    static func candidates(in rows: [ProcessRow], ownProcessIdentifier: Int32) -> [ProcessRow] {
        let parentByPID = Dictionary(rows.map { ($0.pid, $0.ppid) }, uniquingKeysWith: { first, _ in first })
        return rows.filter { row in
            row.pid != ownProcessIdentifier
                && looksLikeInferenceServer(row.command)
                && !isDescendant(row.pid, of: ownProcessIdentifier, parentByPID: parentByPID)
        }
    }

    /// - Parameter listeningPorts: PID -> listening TCP ports, or `nil` if `lsof` was unavailable.
    static func resolve(
        candidates: [ProcessRow],
        listeningPorts: [Int32: [Int]]?
    ) -> [ExternalServerProcess] {
        var matches: [Int32: (ppid: Int32, server: ExternalServerProcess)] = [:]

        for row in candidates {
            let details = classify(processIdentifier: row.pid, command: row.command)
            let ports = listeningPorts?[row.pid] ?? []

            if listeningPorts != nil {
                guard !ports.isEmpty else { continue }
            } else {
                guard details != nil else { continue }
            }

            matches[row.pid] = (
                row.ppid,
                ExternalServerProcess(
                    processIdentifier: row.pid,
                    backend: details?.backend ?? inferredBackend(from: row.command),
                    port: ports.min() ?? details?.port,
                    model: details?.model
                )
            )
        }

        // A server that forks workers sharing its socket should be listed once.
        return matches.values
            .filter { matches[$0.ppid] == nil }
            .map(\.server)
            .sorted { $0.processIdentifier < $1.processIdentifier }
    }

    /// Strict, command-line-only identification (also used to extract the model and `--port`).
    static func classify(processIdentifier: Int32, command: String) -> ExternalServerProcess? {
        let tokens = command.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let first = tokens.first, isKnownLauncher(basename(first)) else { return nil }
        let names = tokens.map { basename($0) }

        // Rapid-MLX: `rapid-mlx serve <model> ...`, `python -m rapid_mlx serve`, `uv run rapid-mlx serve`.
        for index in names.indices where isRapidMLXName(names[index]) {
            guard index + 1 < names.count, names[index + 1] == "serve" else { continue }
            let arguments = Array(tokens[(index + 2)...])
            return ExternalServerProcess(
                processIdentifier: processIdentifier,
                backend: .rapidMLX,
                port: optionValue("--port", in: arguments).flatMap { Int($0) },
                model: arguments.first { !$0.hasPrefix("-") }
            )
        }

        // mlx-lm: `mlx_lm.server ...`, `python -m mlx_lm.server ...`, `mlx_lm server ...`.
        for index in names.indices {
            let isServer = names[index].lowercased() == "mlx_lm.server"
                || (names[index].lowercased() == "mlx_lm" && index + 1 < names.count && names[index + 1] == "server")
            guard isServer else { continue }
            let arguments = Array(tokens[(index + 1)...])
            return ExternalServerProcess(
                processIdentifier: processIdentifier,
                backend: .mlxLM,
                port: optionValue("--port", in: arguments).flatMap { Int($0) },
                model: optionValue("--model", in: arguments)
            )
        }

        return nil
    }

    /// Parses `lsof -Fpn` output (`p<pid>` then `n<address>:<port>` lines).
    static func parseListeningPorts(_ lsofOutput: String) -> [Int32: [Int]] {
        var ports: [Int32: [Int]] = [:]
        var currentPID: Int32?

        for line in lsofOutput.split(whereSeparator: \.isNewline) {
            guard let tag = line.first else { continue }
            let value = line.dropFirst()
            switch tag {
            case "p":
                currentPID = Int32(value)
            case "n":
                if let pid = currentPID,
                   let colon = value.lastIndex(of: ":"),
                   let port = Int(value[value.index(after: colon)...]) {
                    ports[pid, default: []].append(port)
                }
            default:
                break
            }
        }
        return ports
    }

    // MARK: - I/O helper

    private static func listeningPorts(for processIdentifiers: [Int32]) async -> [Int32: [Int]]? {
        guard let result = await ShortLivedProcessRunner.runAsync(
            executablePath: "/usr/sbin/lsof",
            arguments: [
                "-nP", "-a", "-iTCP", "-sTCP:LISTEN",
                "-p", processIdentifiers.map(String.init).joined(separator: ","),
                "-Fpn",
            ],
            timeout: 5
        ),
            !result.timedOut,
            !result.cancelled,
            let output = String(data: result.standardOutput, encoding: .utf8)
        else {
            return nil
        }

        // lsof exits 1 when nothing matches; an error with no output means it couldn't run properly.
        if result.terminationStatus != 0, output.isEmpty, !result.standardError.isEmpty {
            return nil
        }
        return parseListeningPorts(output)
    }

    // MARK: - Helpers

    private static func looksLikeInferenceServer(_ command: String) -> Bool {
        let tokens = command.split(separator: " ", omittingEmptySubsequences: true)
        guard let first = tokens.first, isKnownLauncher(basename(String(first))) else { return false }
        return tokens.contains { token in
            let name = basename(String(token)).lowercased()
            return isRapidMLXName(name) || name == "mlx_lm.server" || name == "mlx_lm" || name.hasPrefix("mlx_lm.")
        }
    }

    /// Matches case-insensitively: Homebrew / python.org Python shows up in `ps` as `.../Python.app/.../Python`.
    private static func isKnownLauncher(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return lowered.hasPrefix("python")
            || ["rapid-mlx", "rapid_mlx", "mlx_lm.server", "mlx_lm", "uv", "uvx", "pipx", "env", "bash", "sh", "zsh", "dash"]
            .contains(lowered)
    }

    private static func isRapidMLXName(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return lowered == "rapid-mlx" || lowered == "rapid_mlx" || lowered.hasPrefix("rapid_mlx.")
    }

    private static func inferredBackend(from command: String) -> InferenceBackend {
        let lowered = command.lowercased()
        return lowered.contains("rapid-mlx") || lowered.contains("rapid_mlx") ? .rapidMLX : .mlxLM
    }

    private static func parseRow(_ line: Substring) -> ProcessRow? {
        var rest = line.drop(while: { $0 == " " })
        guard let pidEnd = rest.firstIndex(of: " "), let pid = Int32(rest[..<pidEnd]) else { return nil }
        rest = rest[pidEnd...].drop(while: { $0 == " " })
        guard let ppidEnd = rest.firstIndex(of: " "), let ppid = Int32(rest[..<ppidEnd]) else { return nil }
        let command = rest[ppidEnd...].trimmingCharacters(in: .whitespaces)
        guard !command.isEmpty else { return nil }
        return ProcessRow(pid: pid, ppid: ppid, command: command)
    }

    private static func isDescendant(
        _ processIdentifier: Int32,
        of ancestor: Int32,
        parentByPID: [Int32: Int32]
    ) -> Bool {
        var current = processIdentifier
        for _ in 0..<64 {
            guard let parent = parentByPID[current], parent > 0 else { return false }
            if parent == ancestor { return true }
            current = parent
        }
        return false
    }

    private static func basename(_ token: String) -> String {
        String(token.split(separator: "/").last ?? "")
    }

    private static func optionValue(_ name: String, in arguments: [String]) -> String? {
        for (index, argument) in arguments.enumerated() {
            if argument == name, index + 1 < arguments.count {
                return arguments[index + 1]
            }
            if argument.hasPrefix(name + "=") {
                return String(argument.dropFirst(name.count + 1))
            }
        }
        return nil
    }
}

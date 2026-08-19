import Foundation

public enum AppInfo {
    public static let clientName = "aiusagemonitor"
    public static let clientTitle = "AI Usage Monitor"
    public static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }
}

/// Reads the Codex plan quota from a short-lived `codex app-server`.
///
/// The app-server answers `account/rateLimits/read` from account state it already
/// holds, so the probe costs no plan quota and stays pollable while the plan is
/// exhausted. The child is spawned per probe rather than kept alive: a resident
/// Rust process is the larger cost of the two, and a watchdog reaps a child that
/// stops answering.
public enum CodexProbe {
    /// Spawn plus handshake is around 1.5-3s on a warm machine.
    private static let timeout: TimeInterval = 20

    /// JSON-RPC's "method not found", which is how an older CLI declines.
    private static let methodNotFound = -32601

    private enum Failure: Error {
        case closed
        case rpc(code: Int, message: String)
    }

    public static func run() async -> ProviderUsage {
        await Background.run { runBlocking() }
    }

    static func runBlocking() -> ProviderUsage {
        guard let binary = BinaryResolver.resolve("codex", override: Preferences.codexBinaryPath) else {
            return .empty(.codex, .unsupported, "The Codex CLI is not installed on this machine.")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["app-server"]
        if ProcessInfo.processInfo.environment["AUM_DEBUG"] != nil {
            FileHandle.standardError.write("AUM_DEBUG binary=\(binary)\n".data(using: .utf8)!)
        }
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        if ProcessInfo.processInfo.environment["AUM_DEBUG"] != nil {
            process.standardError = FileHandle(fileDescriptor: STDERR_FILENO)
        }

        do {
            try process.run()
        } catch {
            return .empty(
                .codex,
                .unavailable,
                "Could not start `codex app-server`: \(error.localizedDescription)"
            )
        }

        // Killing the child is what unblocks a stuck read, so the watchdog is the
        // timeout: there is no separate deadline to honour on the read itself.
        let watchdog = Subprocess.watchdog(for: process, timeout: timeout)
        defer {
            watchdog.cancel()
            if process.isRunning { process.terminate() }
        }

        var session = RPCSession(
            input: stdin.fileHandleForWriting,
            output: stdout.fileHandleForReading
        )

        do {
            // All requests go out before the first await: the app-server can
            // stop reading stdin once it has answered `initialize`, so a write
            // issued after that response lands on a closed pipe (EPIPE). This
            // is the same pipelined order the CLI's own clients use.
            try session.request(id: 1, method: "initialize", params: [
                "clientInfo": [
                    "name": AppInfo.clientName,
                    "title": AppInfo.clientTitle,
                    "version": AppInfo.version,
                ],
                "capabilities": ["experimentalApi": true],
            ])
            try session.notify(method: "initialized")
            try session.request(id: 2, method: "account/read", params: [:])
            try session.request(id: 3, method: "account/rateLimits/read")

            _ = try session.awaitResponse(id: 1)

            // Only a ChatGPT plan has a rolling quota. An API key bills per token,
            // so reporting "no windows" there would read as a bug.
            let account = try session.awaitResponse(id: 2)
            guard let accountType = JSON.string(JSON.object(account["account"])?["type"]) else {
                return .empty(.codex, .unauthenticated, "Codex is not signed in on this machine.")
            }
            guard accountType == "chatgpt" else {
                return .empty(
                    .codex,
                    .unauthenticated,
                    "Codex is signed in without a ChatGPT plan, so it has no plan quota."
                )
            }

            let limits = try session.awaitResponse(id: 3)
            return CodexUsageParser.parse(result: limits, fetchedAt: Date())
        } catch Failure.rpc(let code, let message) {
            return code == methodNotFound
                ? .empty(.codex, .unsupported, "This Codex CLI is too old to report a plan quota.")
                : .empty(.codex, .unavailable, "Codex refused the quota request: \(message)")
        } catch {
            // The watchdog's kill is what closes the pipe, so a signalled child is
            // the timeout case rather than a crash.
            let timedOut = !process.isRunning && process.terminationReason == .uncaughtSignal
            let detail = timedOut
                ? "`codex app-server` did not answer in time."
                : "`codex app-server` closed before answering."
            // The underlying error is only worth its width when debugging.
            let extra = ProcessInfo.processInfo.environment["AUM_DEBUG"] != nil ? " \(error)" : ""
            return .empty(.codex, .unavailable, detail + extra)
        }
    }

    /// Newline-delimited JSON-RPC over the child's stdio. Blocking by design: it
    /// runs on ``Background``'s thread, and the watchdog owns the deadline.
    private struct RPCSession {
        let input: FileHandle
        let output: FileHandle
        private var buffer = Data()

        init(input: FileHandle, output: FileHandle) {
            self.input = input
            self.output = output
        }

        func request(id: Int, method: String, params: Any? = nil) throws {
            var message: [String: Any] = ["jsonrpc": "2.0", "method": method, "id": id]
            if let params { message["params"] = params }
            try write(message)
        }

        func notify(method: String) throws {
            try write(["jsonrpc": "2.0", "method": method])
        }

        private func write(_ message: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: message)
            data.append(0x0A)
            try input.write(contentsOf: data)
        }

        /// Waits for the response to `id`, dropping the notifications in between.
        mutating func awaitResponse(id: Int) throws -> [String: Any] {
            while true {
                let message = try nextMessage()
                guard JSON.number(message["id"]).map({ Int($0) }) == id else { continue }
                if let error = JSON.object(message["error"]) {
                    throw Failure.rpc(
                        code: JSON.number(error["code"]).map { Int($0) } ?? 0,
                        message: JSON.string(error["message"]) ?? "unknown error"
                    )
                }
                return JSON.object(message["result"]) ?? [:]
            }
        }

        private mutating func nextMessage() throws -> [String: Any] {
            while true {
                if let newline = buffer.firstIndex(of: 0x0A) {
                    let line = Data(buffer[buffer.startIndex..<newline])
                    buffer.removeSubrange(buffer.startIndex...newline)
                    if let object = JSON.object(try? JSONSerialization.jsonObject(with: line)) {
                        return object
                    }
                    continue
                }
                guard let chunk = try output.read(upToCount: 16 * 1024), !chunk.isEmpty else {
                    throw Failure.closed
                }
                buffer.append(chunk)
            }
        }
    }
}

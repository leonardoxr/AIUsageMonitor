import Foundation

/// Runs blocking work off the cooperative pool.
///
/// Both probes block on pipes, and a probe that parks a cooperative thread starves
/// the actor that owns the UI. A short-lived thread costs less than the two CLI
/// spawns it is waiting on.
public enum Background {
    public static func run<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            let thread = Thread { continuation.resume(returning: work()) }
            thread.name = "AIUsageMonitor.probe"
            thread.start()
        }
    }
}

/// Blocking process helpers. Called from ``Background``, never from the main actor.
public enum Subprocess {
    /// Captures stdout of a short command, or nil on any failure.
    ///
    /// A watchdog kills the child at the deadline: EOF is what unblocks the read,
    /// so a hung binary cannot wedge the probe.
    public static func capture(
        executable: String,
        arguments: [String],
        timeout: TimeInterval = 5,
        environment: [String: String]? = nil
    ) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment { process.environment = environment }
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }
        let watchdog = watchdog(for: process, timeout: timeout)
        defer { watchdog.cancel() }

        let data = (try? output.fileHandleForReading.readToEnd()) ?? Data()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Terminates, then hard-kills, a child that outlives its deadline.
    public static func watchdog(for process: Process, timeout: TimeInterval) -> DispatchWorkItem {
        let item = DispatchWorkItem {
            guard process.isRunning else { return }
            process.terminate()
            let pid = process.processIdentifier
            // A child that ignores SIGTERM is not worth waiting on.
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if process.isRunning { kill(pid, SIGKILL) }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: item)
        return item
    }
}

/// Finds a provider CLI from a GUI app, whose `PATH` is the bare launchd default.
///
/// Resolution is cached for the process lifetime: a login-shell spawn to learn one
/// path is acceptable once, not on every poll.
public enum BinaryResolver {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: String] = [:]

    private static let commonDirectories = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "~/.local/bin",
        "~/.bun/bin",
        "~/.cargo/bin",
        "~/.volta/bin",
        "~/.npm-global/bin",
    ]

    public static func resolve(_ name: String, override: String? = nil) -> String? {
        if let override, !override.isEmpty {
            let expanded = (override as NSString).expandingTildeInPath
            return FileManager.default.isExecutableFile(atPath: expanded) ? expanded : nil
        }

        lock.lock()
        let cached = cache[name]
        lock.unlock()
        if let cached { return cached }

        guard let resolved = search(name) else { return nil }
        lock.lock()
        cache[name] = resolved
        lock.unlock()
        return resolved
    }

    private static func search(_ name: String) -> String? {
        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        for directory in pathEntries + commonDirectories {
            let candidate = ((directory as NSString).expandingTildeInPath as NSString)
                .appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        // Last resort: ask the user's login shell, which knows their version manager.
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard
            let output = capture(executable: shell, arguments: ["-lc", "command -v \(name)"]),
            let line = output.split(separator: "\n").first
        else { return nil }
        let path = String(line).trimmingCharacters(in: .whitespaces)
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    private static func capture(executable: String, arguments: [String]) -> String? {
        Subprocess.capture(executable: executable, arguments: arguments, timeout: 8)
    }
}

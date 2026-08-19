import Foundation

/// The handful of knobs worth persisting. `UserDefaults` is thread-safe, so this
/// stays unisolated and both probes can read it.
public enum Preferences {
    private enum Key {
        static let refreshInterval = "refreshIntervalSeconds"
        static let codexBinaryPath = "codexBinaryPath"
    }

    /// Codex costs a CLI spawn per poll, so the default leans slow. Quota windows
    /// move in hours; a ten-minute-old figure is still the right one.
    public static let intervalOptions: [TimeInterval] = [300, 600, 1800]
    public static let defaultInterval: TimeInterval = 600

    public static var refreshInterval: TimeInterval {
        get {
            let stored = UserDefaults.standard.double(forKey: Key.refreshInterval)
            return intervalOptions.contains(stored) ? stored : defaultInterval
        }
        set { UserDefaults.standard.set(newValue, forKey: Key.refreshInterval) }
    }

    /// Escape hatch for an install the resolver cannot find.
    public static var codexBinaryPath: String? {
        UserDefaults.standard.string(forKey: Key.codexBinaryPath)
    }
}

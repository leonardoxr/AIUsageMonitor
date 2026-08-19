import Foundation

/// Tolerant reads over `JSONSerialization` output.
///
/// Both providers hand back open-ended shapes — Anthropic keeps adding codenamed
/// windows, Codex reports one bucket per model family, and both mix value types
/// inside the same map — so nothing here enumerates expected keys. An unknown or
/// malformed entry yields nil instead of failing the whole read.
public enum JSON {
    public static func object(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    public static func array(_ value: Any?) -> [Any]? {
        value as? [Any]
    }

    public static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber else { return nil }
        let double = number.doubleValue
        return double.isFinite ? double : nil
    }

    public static func bool(_ value: Any?) -> Bool? {
        (value as? NSNumber)?.boolValue
    }

    /// Non-empty strings only: an empty label is worse than no label.
    public static func string(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// ISO-8601 parsing that survives Anthropic's six-digit fractional seconds.
public enum ISODate {
    public static func parse(_ value: String?) -> Date? {
        guard let value = JSON.string(value) else { return nil }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: value) { return date }

        // `2026-08-19T23:09:59.971307+00:00`: more fractional digits than
        // `withFractionalSeconds` accepts, so drop the fraction and retry.
        guard let dot = value.firstIndex(of: "."),
              let fractionEnd = value[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" })
        else { return nil }
        var trimmed = value
        trimmed.removeSubrange(dot..<fractionEnd)
        return plain.date(from: trimmed)
    }

    /// Codex stamps resets in epoch seconds.
    public static func fromEpochSeconds(_ value: Double?) -> Date? {
        guard let value, value > 0 else { return nil }
        return Date(timeIntervalSince1970: value)
    }

    /// Claude Code stores credential expiry in epoch milliseconds.
    public static func fromEpochMilliseconds(_ value: Double?) -> Date? {
        guard let value, value > 0 else { return nil }
        return Date(timeIntervalSince1970: value / 1000)
    }
}

import Foundation

/// Text the menu bar and the menu render. Pure, so the wording is testable.
public enum Format {
    /// `44%`. Integers only: a menu bar that repaints on a decimal is noise.
    public static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    /// `10080` reads as `Weekly` and `300` as `5 hour`; every other duration
    /// falls out of the same whole-unit rules.
    public static func windowDuration(minutes: Double?) -> String? {
        guard let minutes, minutes.isFinite, minutes > 0 else { return nil }
        let total = Int(minutes.rounded())
        if total % 1440 == 0 {
            let days = total / 1440
            if days == 1 { return "Daily" }
            if days == 7 { return "Weekly" }
            return "\(days) day"
        }
        if total % 60 == 0 { return "\(total / 60) hour" }
        return "\(total) minute"
    }

    /// `resets in 2h 10m` while that is actionable, an absolute time past a day.
    public static func reset(_ date: Date, now: Date = Date()) -> String {
        let seconds = date.timeIntervalSince(now)
        if seconds <= 60 { return "resets now" }
        if seconds < 3600 { return "resets in \(Int(seconds / 60))m" }
        if seconds < 86_400 {
            let hours = Int(seconds / 3600)
            let minutes = Int(seconds.truncatingRemainder(dividingBy: 3600) / 60)
            return minutes == 0 ? "resets in \(hours)h" : "resets in \(hours)h \(minutes)m"
        }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE jj:mm")
        return "resets \(formatter.string(from: date))"
    }

    /// `updated 2 min ago`, for the footer of the menu.
    public static func age(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 45 { return "updated just now" }
        if seconds < 5400 { return "updated \(Int((seconds / 60).rounded())) min ago" }
        return "updated \(Int((seconds / 3600).rounded()))h ago"
    }

    /// `max` reads as `Max`; provider plan names arrive lowercased.
    public static func planLabel(_ value: String?) -> String? {
        guard let value = JSON.string(value) else { return nil }
        return value.split(separator: " ").map { part in
            part.count <= 3 && part.uppercased() == String(part)
                ? String(part)
                : part.prefix(1).uppercased() + part.dropFirst()
        }.joined(separator: " ")
    }

    /// `nimbus_quill` reads as `Nimbus Quill` until we learn its real name.
    public static func titleCaseKey(_ key: String) -> String {
        key
            .split(whereSeparator: { $0 == "_" || $0 == "-" })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// Ten-cell bar, e.g. `████░░░░░░`. Static text: no animation, no repaint.
    public static func bar(_ percent: Double, cells: Int = 10) -> String {
        let filled = min(cells, max(0, Int((percent / 100 * Double(cells)).rounded())))
        return String(repeating: "█", count: filled) + String(repeating: "░", count: cells - filled)
    }
}

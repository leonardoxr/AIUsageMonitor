import Foundation

/// Maps Anthropic's `GET /api/oauth/usage` body onto ``ProviderUsage``.
///
/// The response carries the same plan twice: a modern `limits` array and a legacy
/// flat map of buckets. The array wins where present because it is the only one
/// that reports model-scoped weekly limits (regularly the binding one); the map
/// is the fallback. They are not merged, because merging double-counts the
/// session and weekly windows under two different ids.
public enum ClaudeUsageParser {
    /// Buckets we have names for; anything else is title-cased from its key.
    private static let bucketLabels: [String: String] = [
        "five_hour": "5 hour",
        "seven_day": "Weekly",
        "seven_day_opus": "Weekly (Opus)",
        "seven_day_sonnet": "Weekly (Sonnet)",
    ]

    /// `kind` values from the `limits` array. Scoped limits name their model instead.
    private static let limitKindLabels: [String: String] = [
        "session": "5 hour",
        "weekly_all": "Weekly",
    ]

    /// Keys the flat map exposes that the `limits` array already covers.
    private static let limitKindIDs: [String: String] = [
        "session": "five_hour",
        "weekly_all": "seven_day",
    ]

    /// A purchased credit balance, not a rolling window, so never a gauge.
    private static let creditBalanceKey = "extra_usage"

    public static func parse(
        body: Data,
        planLabel: String?,
        fetchedAt: Date
    ) -> ProviderUsage {
        guard
            let raw = try? JSONSerialization.jsonObject(with: body),
            let root = JSON.object(raw)
        else {
            return .empty(.claude, .unavailable, "Anthropic returned an unreadable quota response.")
        }

        return ProviderUsage(
            provider: .claude,
            status: .ok,
            planLabel: Format.planLabel(planLabel),
            windows: windowsFromLimits(root) ?? windowsFromBuckets(root),
            fetchedAt: fetchedAt,
            detail: nil
        )
    }

    /// Windows from the modern `limits` array, or nil when it is absent or unreadable.
    private static func windowsFromLimits(_ root: [String: Any]) -> [UsageWindow]? {
        guard let limits = JSON.array(root["limits"]) else { return nil }

        var windows: [UsageWindow] = []
        var seen: Set<String> = []
        for entry in limits {
            guard
                let limit = JSON.object(entry),
                let kind = JSON.string(limit["kind"]),
                let percent = JSON.number(limit["percent"])
            else { continue }

            let model = JSON.string(JSON.object(JSON.object(limit["scope"])?["model"])?["display_name"])
            let id = limitKindIDs[kind] ?? (model.map { "\(kind):\($0.lowercased())" } ?? kind)
            // A plan can report several scoped limits; the id keeps them apart,
            // and a repeated id would render the same row twice.
            if seen.contains(id) { continue }

            let label = limitKindLabels[kind]
                ?? (model.map { "Weekly (\($0))" } ?? Format.titleCaseKey(kind))
            guard let window = UsageWindow.make(
                id: id,
                label: label,
                usedPercent: percent,
                resetsAt: ISODate.parse(limit["resets_at"] as? String)
            ) else { continue }

            seen.insert(id)
            windows.append(window)
        }
        return windows.isEmpty ? nil : windows
    }

    /// Windows from the legacy flat bucket map, for responses without `limits`.
    private static func windowsFromBuckets(_ root: [String: Any]) -> [UsageWindow] {
        var windows: [UsageWindow] = []
        // Sorted, so windows never reshuffle between polls.
        for key in root.keys.sorted() {
            guard key != creditBalanceKey, key != "limits" else { continue }
            guard
                let bucket = JSON.object(root[key]),
                let percent = JSON.number(bucket["utilization"])
            else { continue }
            guard let window = UsageWindow.make(
                id: key,
                label: bucketLabels[key] ?? Format.titleCaseKey(key),
                usedPercent: percent,
                resetsAt: ISODate.parse(bucket["resets_at"] as? String)
            ) else { continue }
            windows.append(window)
        }
        return windows
    }
}

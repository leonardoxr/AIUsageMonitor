import Foundation

/// Maps Codex's `account/rateLimits/read` result onto ``ProviderUsage``.
///
/// `rateLimits` is the single-bucket view of the binding limit, so it names which
/// entry of `rateLimitsByLimitId` is the plan's own quota. The remaining entries
/// are per-model allowances (a Spark bucket, say): they are a different allowance
/// rather than more of the same one, so they are reported separately and never
/// feed the headline number.
public enum CodexUsageParser {
    /// Codex's own bucket. Its windows read better without the redundant name.
    private static let defaultLimitID = "codex"

    public static func parse(result: [String: Any], fetchedAt: Date) -> ProviderUsage {
        guard let single = JSON.object(result["rateLimits"]) else {
            return .empty(.codex, .unavailable, "Codex returned an unreadable quota response.")
        }

        let limitID = JSON.string(single["limitId"]) ?? defaultLimitID
        let byLimitID = JSON.object(result["rateLimitsByLimitId"]) ?? [:]
        let planBucket = JSON.object(byLimitID[limitID]) ?? single

        var extras: [UsageWindow] = []
        // Sorted, so the extra allowances never reshuffle between polls.
        for key in byLimitID.keys.sorted() where key != limitID {
            guard let bucket = JSON.object(byLimitID[key]) else { continue }
            extras.append(contentsOf: windows(limitKey: key, bucket: bucket))
        }

        return ProviderUsage(
            provider: .codex,
            status: .ok,
            planLabel: Format.planLabel(JSON.string(planBucket["planType"])),
            windows: windows(limitKey: limitID, bucket: planBucket),
            extraWindows: extras,
            fetchedAt: fetchedAt,
            detail: nil
        )
    }

    /// A bucket carries up to two windows; the secondary takes an id suffix so
    /// the pair stays distinguishable.
    private static func windows(limitKey: String, bucket: [String: Any]) -> [UsageWindow] {
        let limitName = JSON.string(bucket["limitName"])
        return [("", "primary"), (":secondary", "secondary")].compactMap { suffix, key in
            guard
                let slot = JSON.object(bucket[key]),
                let percent = JSON.number(slot["usedPercent"])
            else { return nil }
            return UsageWindow.make(
                id: "\(limitKey)\(suffix)",
                label: label(
                    limitKey: limitKey,
                    limitName: limitName,
                    minutes: JSON.number(slot["windowDurationMins"])
                ),
                usedPercent: percent,
                resetsAt: ISODate.fromEpochSeconds(JSON.number(slot["resetsAt"]))
            )
        }
    }

    private static func label(limitKey: String, limitName: String?, minutes: Double?) -> String {
        let name = limitName ?? (limitKey == defaultLimitID ? nil : limitKey)
        let duration = Format.windowDuration(minutes: minutes)
        guard let name else { return duration ?? limitKey }
        guard let duration else { return name }
        return "\(name) \(duration)"
    }
}

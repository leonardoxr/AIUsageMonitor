import Foundation

/// A provider whose subscription quota this app can read.
public enum ProviderKind: String, Sendable, CaseIterable {
    case claude
    case codex

    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    /// One-glyph prefix, kept for narrow contexts and as a no-icon fallback.
    public var badge: String {
        switch self {
        case .claude: "C"
        case .codex: "X"
        }
    }

    /// Bundled brand-mark resource (template PNG) for the menu bar title.
    public var iconResourceName: String {
        switch self {
        case .claude: "ClaudeIcon"
        case .codex: "CodexIcon"
        }
    }
}

/// Why a provider has no figures, when it has none.
public enum ProviderStatus: String, Sendable {
    /// Figures are present and current.
    case ok
    /// The CLI is not signed in to a plan (or is on an API key, which has no plan quota).
    case unauthenticated
    /// Signed in, but this account or CLI version does not report a rolling quota.
    case unsupported
    /// The probe itself failed: no binary, no network, unreadable answer.
    case unavailable
}

/// One rolling quota window, e.g. Claude's five-hour session or Codex's weekly.
public struct UsageWindow: Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let usedPercent: Double
    public let resetsAt: Date?

    public init(id: String, label: String, usedPercent: Double, resetsAt: Date?) {
        self.id = id
        self.label = label
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }

    /// Builds a window, dropping readings that describe nothing.
    ///
    /// A bucket that is both unused and has no reset time is how both providers
    /// report a window the plan was never granted, so it is dropped rather than
    /// rendered as a row that can never move.
    public static func make(
        id: String,
        label: String,
        usedPercent: Double,
        resetsAt: Date?
    ) -> UsageWindow? {
        let id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !label.isEmpty else { return nil }
        let percent = clampUsedPercent(usedPercent)
        if percent == 0, resetsAt == nil { return nil }
        return UsageWindow(id: id, label: label, usedPercent: percent, resetsAt: resetsAt)
    }
}

/// Both CLIs already report a percentage, so an out-of-range value is a provider
/// bug rather than a fraction to rescale: rescaling would turn 0.9% used into a
/// nearly full gauge.
public func clampUsedPercent(_ value: Double) -> Double {
    guard value.isFinite, value > 0 else { return 0 }
    return min(value, 100)
}

/// Everything known about one provider's plan quota after a probe.
public struct ProviderUsage: Sendable, Equatable {
    public let provider: ProviderKind
    public let status: ProviderStatus
    /// Plan name as the provider words it, e.g. `max`, `pro`.
    public let planLabel: String?
    /// Windows of the plan's own quota. The headline number is the highest of these.
    public let windows: [UsageWindow]
    /// Allowances that are not the plan quota (Codex's per-model buckets).
    public let extraWindows: [UsageWindow]
    public let fetchedAt: Date?
    /// Human-readable reason, for any status other than `ok`.
    public let detail: String?

    public init(
        provider: ProviderKind,
        status: ProviderStatus,
        planLabel: String?,
        windows: [UsageWindow],
        extraWindows: [UsageWindow] = [],
        fetchedAt: Date?,
        detail: String?
    ) {
        self.provider = provider
        self.status = status
        self.planLabel = planLabel
        self.windows = windows
        self.extraWindows = extraWindows
        self.fetchedAt = fetchedAt
        self.detail = detail
    }

    /// The window closest to stopping the next turn.
    public var bindingPercent: Double? {
        windows.map(\.usedPercent).max()
    }

    /// A provider with no figures: the status and detail render in place of a number.
    public static func empty(
        _ provider: ProviderKind,
        _ status: ProviderStatus,
        _ detail: String
    ) -> ProviderUsage {
        ProviderUsage(
            provider: provider,
            status: status,
            planLabel: nil,
            windows: [],
            fetchedAt: nil,
            detail: detail
        )
    }
}

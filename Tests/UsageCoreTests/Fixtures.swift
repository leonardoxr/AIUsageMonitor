/// Payloads captured verbatim from the live CLIs on 2026-08-19, trimmed only of
/// fields no parser reads. Pinning the real shapes is the point: both providers
/// change them without notice.
enum Fixtures {
    /// `GET https://api.anthropic.com/api/oauth/usage`, Claude Max plan.
    static let claudeCurrent = """
    {
     "five_hour": {"utilization": 44.0, "resets_at": "2026-08-19T23:09:59.971307+00:00"},
     "seven_day": {"utilization": 71.0, "resets_at": "2026-08-25T19:59:59.971336+00:00"},
     "seven_day_opus": null,
     "nimbus_quill": {"utilization": 0.0, "resets_at": null},
     "extra_usage": {"is_enabled": false, "monthly_limit": null, "utilization": null},
     "limits": [
      {"kind": "session", "group": "session", "percent": 44, "severity": "normal",
       "resets_at": "2026-08-19T23:09:59.971307+00:00", "scope": null, "is_active": false},
      {"kind": "weekly_all", "group": "weekly", "percent": 71, "severity": "normal",
       "resets_at": "2026-08-25T19:59:59.971336+00:00", "scope": null, "is_active": true},
      {"kind": "weekly_scoped", "group": "weekly", "percent": 57, "severity": "normal",
       "resets_at": "2026-08-25T19:59:59.971656+00:00",
       "scope": {"model": {"id": null, "display_name": "Fable"}, "surface": null},
       "is_active": false}
     ],
     "member_dashboard_available": false
    }
    """

    /// The same account before Anthropic added the `limits` array.
    static let claudeLegacy = """
    {
     "five_hour": {"utilization": 44.0, "resets_at": "2026-08-19T23:09:59.971307+00:00"},
     "seven_day": {"utilization": 71.0, "resets_at": "2026-08-25T19:59:59.971336+00:00"},
     "seven_day_opus": null,
     "nimbus_quill": {"utilization": 0.0, "resets_at": null},
     "extra_usage": {"is_enabled": false, "utilization": null}
    }
    """

    /// `account/rateLimits/read` from `codex app-server`, ChatGPT Pro plan with
    /// the weekly window exhausted and a per-model Spark allowance beside it.
    static let codexRateLimits = """
    {
     "rateLimits": {
      "limitId": "codex", "limitName": null,
      "primary": {"usedPercent": 100, "windowDurationMins": 10080, "resetsAt": 1787196617},
      "secondary": null,
      "credits": {"hasCredits": false, "unlimited": false, "balance": "0"},
      "planType": "pro", "rateLimitReachedType": "rate_limit_reached"
     },
     "rateLimitsByLimitId": {
      "codex_bengalfox": {
       "limitId": "codex_bengalfox", "limitName": "GPT-5.3-Codex-Spark",
       "primary": {"usedPercent": 1, "windowDurationMins": 10080, "resetsAt": 1787764903},
       "secondary": null, "planType": "pro"
      },
      "codex": {
       "limitId": "codex", "limitName": null,
       "primary": {"usedPercent": 100, "windowDurationMins": 10080, "resetsAt": 1787196617},
       "secondary": {"usedPercent": 12, "windowDurationMins": 300, "resetsAt": 1787181000},
       "planType": "pro"
      }
     }
    }
    """
}

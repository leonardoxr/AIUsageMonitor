import XCTest
@testable import UsageCore

/// Bodies captured from a live `GET /api/oauth/usage` on a Max plan.
final class ClaudeUsageParserTests: XCTestCase {
    private let fetchedAt = Date(timeIntervalSince1970: 1_787_171_400)

    private func parse(_ json: String) -> ProviderUsage {
        ClaudeUsageParser.parse(body: Data(json.utf8), planLabel: "max", fetchedAt: fetchedAt)
    }

    func testPrefersTheLimitsArrayAndNamesScopedWindows() {
        let usage = parse(Fixtures.claudeCurrent)

        XCTAssertEqual(usage.status, .ok)
        XCTAssertEqual(usage.planLabel, "Max")
        XCTAssertEqual(usage.windows.map(\.id), ["five_hour", "seven_day", "weekly_scoped:fable"])
        XCTAssertEqual(usage.windows.map(\.label), ["5 hour", "Weekly", "Weekly (Fable)"])
        XCTAssertEqual(usage.windows.map(\.usedPercent), [44, 71, 57])
        // A model-scoped weekly limit exists only in `limits`, and here it is the
        // reason the plan is closer to its ceiling than the flat map admits.
        XCTAssertEqual(usage.bindingPercent, 71)
    }

    func testParsesSixDigitFractionalResetStamps() {
        let usage = parse(Fixtures.claudeCurrent)
        let fiveHour = usage.windows.first { $0.id == "five_hour" }

        XCTAssertEqual(
            fiveHour?.resetsAt?.timeIntervalSince1970 ?? 0,
            1_787_181_000,
            accuracy: 1
        )
    }

    func testFallsBackToTheFlatBucketMapAndDropsUngrantedWindows() {
        let usage = parse(Fixtures.claudeLegacy)

        XCTAssertEqual(usage.status, .ok)
        // `nimbus_quill` is 0% with no reset: a window the plan was never granted.
        // `extra_usage` is a credit balance, not a rolling window.
        XCTAssertEqual(usage.windows.map(\.id), ["five_hour", "seven_day"])
        XCTAssertEqual(usage.windows.map(\.usedPercent), [44, 71])
    }

    func testTitleCasesUnknownBucketKeys() {
        let usage = parse(
            #"{"nimbus_quill": {"utilization": 12, "resets_at": "2026-08-25T19:59:59Z"}}"#
        )

        XCTAssertEqual(usage.windows.map(\.label), ["Nimbus Quill"])
    }

    func testReportsUnavailableForAnUnreadableBody() {
        let usage = ClaudeUsageParser.parse(
            body: Data("not json".utf8),
            planLabel: nil,
            fetchedAt: fetchedAt
        )

        XCTAssertEqual(usage.status, .unavailable)
        XCTAssertTrue(usage.windows.isEmpty)
    }
}

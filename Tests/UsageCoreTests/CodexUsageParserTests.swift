import XCTest
@testable import UsageCore

final class CodexUsageParserTests: XCTestCase {
    private let fetchedAt = Date(timeIntervalSince1970: 1_787_171_400)

    private func parse(_ json: String) -> ProviderUsage {
        guard
            let raw = try? JSONSerialization.jsonObject(with: Data(json.utf8)),
            let object = raw as? [String: Any]
        else {
            XCTFail("fixture is not a JSON object")
            return .empty(.codex, .unavailable, "fixture")
        }
        return CodexUsageParser.parse(result: object, fetchedAt: fetchedAt)
    }

    func testReportsThePlanBucketAsTheHeadlineAndKeepsOtherAllowancesApart() {
        let usage = parse(Fixtures.codexRateLimits)

        XCTAssertEqual(usage.status, .ok)
        XCTAssertEqual(usage.planLabel, "Pro")
        // The richer copy of the binding bucket lives in `rateLimitsByLimitId`,
        // which is where the five-hour secondary window appears at all.
        XCTAssertEqual(usage.windows.map(\.id), ["codex", "codex:secondary"])
        XCTAssertEqual(usage.windows.map(\.label), ["Weekly", "5 hour"])
        XCTAssertEqual(usage.windows.map(\.usedPercent), [100, 12])
        XCTAssertEqual(usage.bindingPercent, 100)
        // A per-model allowance is a different allowance: counting it in the
        // headline would read as though the plan had more left than it does.
        XCTAssertEqual(usage.extraWindows.map(\.label), ["GPT-5.3-Codex-Spark Weekly"])
        XCTAssertEqual(usage.extraWindows.map(\.usedPercent), [1])
    }

    func testConvertsEpochSecondResets() {
        let usage = parse(Fixtures.codexRateLimits)

        XCTAssertEqual(
            usage.windows.first?.resetsAt?.timeIntervalSince1970 ?? 0,
            1_787_196_617,
            accuracy: 0.5
        )
    }

    func testFallsBackToTheSingleBucketViewWhenTheMapIsAbsent() {
        let usage = parse("""
        {"rateLimits": {"limitId": "codex", "planType": "plus",
          "primary": {"usedPercent": 3, "windowDurationMins": 300, "resetsAt": 1787181000}}}
        """)

        XCTAssertEqual(usage.windows.map(\.label), ["5 hour"])
        XCTAssertEqual(usage.planLabel, "Plus")
        XCTAssertTrue(usage.extraWindows.isEmpty)
    }

    func testReportsUnavailableWithoutARateLimitsObject() {
        let usage = parse(#"{"somethingElse": true}"#)

        XCTAssertEqual(usage.status, .unavailable)
        XCTAssertTrue(usage.windows.isEmpty)
    }
}

import XCTest
@testable import UsageCore

final class FormattingTests: XCTestCase {
    func testWindowDurationsReadAsWholeUnits() {
        XCTAssertEqual(Format.windowDuration(minutes: 10080), "Weekly")
        XCTAssertEqual(Format.windowDuration(minutes: 1440), "Daily")
        XCTAssertEqual(Format.windowDuration(minutes: 300), "5 hour")
        XCTAssertEqual(Format.windowDuration(minutes: 4320), "3 day")
        XCTAssertEqual(Format.windowDuration(minutes: 90), "90 minute")
        XCTAssertNil(Format.windowDuration(minutes: 0))
        XCTAssertNil(Format.windowDuration(minutes: nil))
    }

    func testResetLabelsStayRelativeWithinADay() {
        let now = Date(timeIntervalSince1970: 1_787_171_400)

        XCTAssertEqual(Format.reset(now.addingTimeInterval(30), now: now), "resets now")
        XCTAssertEqual(Format.reset(now.addingTimeInterval(2400), now: now), "resets in 40m")
        XCTAssertEqual(Format.reset(now.addingTimeInterval(7800), now: now), "resets in 2h 10m")
        XCTAssertEqual(Format.reset(now.addingTimeInterval(7200), now: now), "resets in 2h")
        // Past a day, a relative figure stops being actionable.
        XCTAssertTrue(Format.reset(now.addingTimeInterval(200_000), now: now).hasPrefix("resets "))
        XCTAssertFalse(Format.reset(now.addingTimeInterval(200_000), now: now).contains("in "))
    }

    func testBarIsFixedWidthSoRowsAlign() {
        XCTAssertEqual(Format.bar(0), "░░░░░░░░░░")
        XCTAssertEqual(Format.bar(44), "████░░░░░░")
        XCTAssertEqual(Format.bar(100), "██████████")
        XCTAssertEqual(Format.bar(44).count, Format.bar(100).count)
    }

    func testOutOfRangePercentagesAreClampedNotRescaled() {
        // A provider bug must not turn 0.9% used into a nearly full gauge.
        XCTAssertEqual(clampUsedPercent(0.9), 0.9)
        XCTAssertEqual(clampUsedPercent(140), 100)
        XCTAssertEqual(clampUsedPercent(-5), 0)
        XCTAssertEqual(clampUsedPercent(.nan), 0)
    }

    func testUnusedWindowsWithoutAResetAreDropped() {
        // How both providers report a window the plan was never granted.
        XCTAssertNil(UsageWindow.make(id: "tangelo", label: "Tangelo", usedPercent: 0, resetsAt: nil))
        XCTAssertNotNil(
            UsageWindow.make(id: "tangelo", label: "Tangelo", usedPercent: 0, resetsAt: Date())
        )
    }
}

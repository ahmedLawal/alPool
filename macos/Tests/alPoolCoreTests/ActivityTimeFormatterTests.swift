import XCTest
@testable import alPoolCore

final class ActivityTimeFormatterTests: XCTestCase {
    func testFormatsZuluTimestampInLocalTimeZone() throws {
        let lagos = try XCTUnwrap(TimeZone(secondsFromGMT: 60 * 60))

        let result = ActivityTimeFormatter.localTime(
            "2026-08-24T06:59:10.123Z",
            timeZone: lagos
        )

        XCTAssertEqual(result, "07:59:10")
    }

    func testConversionCanCrossACalendarDay() throws {
        let pacific = try XCTUnwrap(TimeZone(secondsFromGMT: -8 * 60 * 60))

        let result = ActivityTimeFormatter.localTime(
            "2026-08-24T06:59:10Z",
            timeZone: pacific
        )

        XCTAssertEqual(result, "22:59:10")
    }

    func testInvalidTimestampIsPreserved() {
        XCTAssertEqual(ActivityTimeFormatter.localTime("unknown"), "unknown")
    }
}

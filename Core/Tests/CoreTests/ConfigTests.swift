import XCTest
@testable import Core

final class ConfigTests: XCTestCase {
    func testInvalidTimeZoneThrowsAndPlansNothing() {
        let config = Config(timeZoneIdentifier: "Not/AZone")
        XCTAssertNil(config.timeZone)
        XCTAssertThrowsError(try config.validate()) {
            XCTAssertEqual($0 as? ConfigError, .invalidTimeZone("Not/AZone"))
        }
        let e = event(ny(2026, 6, 1, 10), ny(2026, 6, 1, 11))
        XCTAssertThrowsError(try BlockPlanner.plan(events: [e], config: config, window: wideWindow))
        XCTAssertThrowsError(try config.window(now: ny(2026, 6, 1)))
    }

    func testDecodingOutOfRangeTimeOfDayFails() {
        let json = Data(#"{"hour":25,"minute":0}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(TimeOfDay.self, from: json))
        XCTAssertEqual(try JSONDecoder().decode(TimeOfDay.self, from: Data(#"{"hour":9,"minute":30}"#.utf8)),
                       TimeOfDay(hour: 9, minute: 30))
    }

    func testValidateRejectsBadOverrideAndWorkingHours() {
        var config = nyConfig()
        config.dayOverrides[.friday] = DayHours(start: TimeOfDay(hour: 8), end: TimeOfDay(hour: 17, minute: 60))
        XCTAssertThrowsError(try config.validate())
        XCTAssertThrowsError(try BlockPlanner.plan(events: [], config: config, window: wideWindow))

        var bad = nyConfig()
        bad.workingHours.start = TimeOfDay(hour: -1)
        XCTAssertThrowsError(try bad.validate())
    }

    func testMidnightEndOfDayIsValid() throws {
        var config = nyConfig()
        config.workingHours = DayHours(start: TimeOfDay(hour: 0), end: TimeOfDay(hour: 0))
        XCTAssertTrue(TimeOfDay(hour: 0).isValid)
        XCTAssertNoThrow(try config.validate())
    }
}

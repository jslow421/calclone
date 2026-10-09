import XCTest
@testable import Core

final class BlockPlannerTests: XCTestCase {
    // 2026-06-01 is a Monday.
    private func plan(_ events: [SourceEvent], _ config: Config = nyConfig()) -> [Interval] {
        BlockPlanner.plan(events: events, config: config, window: wideWindow)
    }

    // MARK: Working hours

    func testEventInsideWorkingHoursIsBlockedAsIs() {
        XCTAssertEqual(plan([event(ny(2026, 6, 1, 10), ny(2026, 6, 1, 11))]),
                       [iv(ny(2026, 6, 1, 10), ny(2026, 6, 1, 11))])
    }

    func testEventOutsideWorkingHoursGivesNoBlock() {
        XCTAssertEqual(plan([event(ny(2026, 6, 1, 18), ny(2026, 6, 1, 19)),
                             event(ny(2026, 6, 1, 6), ny(2026, 6, 1, 7))]), [])
    }

    func testEventStraddlingDayStartAndEndIsClipped() {
        XCTAssertEqual(plan([event(ny(2026, 6, 1, 7), ny(2026, 6, 1, 9))]),
                       [iv(ny(2026, 6, 1, 8), ny(2026, 6, 1, 9))])
        XCTAssertEqual(plan([event(ny(2026, 6, 1, 16), ny(2026, 6, 1, 18))]),
                       [iv(ny(2026, 6, 1, 16), ny(2026, 6, 1, 17))])
    }

    func testNonWorkingDaysGiveNoBlock() {
        // 2026-06-06 is a Saturday.
        XCTAssertEqual(plan([event(ny(2026, 6, 6, 10), ny(2026, 6, 6, 11))]), [])
    }

    func testPerDayOverride() {
        let config = nyConfig {
            $0.dayOverrides[.friday] = DayHours(start: TimeOfDay(hour: 9), end: TimeOfDay(hour: 12, minute: 30))
            $0.workingDays.insert(.saturday)
            $0.dayOverrides[.saturday] = DayHours(start: TimeOfDay(hour: 10), end: TimeOfDay(hour: 11))
        }
        // 2026-06-05 is a Friday.
        XCTAssertEqual(plan([event(ny(2026, 6, 5, 8), ny(2026, 6, 5, 14))], config),
                       [iv(ny(2026, 6, 5, 9), ny(2026, 6, 5, 12, 30))])
        XCTAssertEqual(plan([event(ny(2026, 6, 6, 8), ny(2026, 6, 6, 14))], config),
                       [iv(ny(2026, 6, 6, 10), ny(2026, 6, 6, 11))])
        // Other days keep the default hours.
        XCTAssertEqual(plan([event(ny(2026, 6, 4, 8), ny(2026, 6, 4, 14))], config),
                       [iv(ny(2026, 6, 4, 8), ny(2026, 6, 4, 14))])
    }

    // MARK: Midnight and multi-day

    func testEventSpanningMidnightSplitsPerDay() {
        let blocks = plan([event(ny(2026, 6, 1, 16), ny(2026, 6, 2, 9))], nyConfig { $0.mergeEnabled = false })
        XCTAssertEqual(blocks, [iv(ny(2026, 6, 1, 16), ny(2026, 6, 1, 17)),
                                iv(ny(2026, 6, 2, 8), ny(2026, 6, 2, 9))])
    }

    func testMultiDayEventSkipsWeekend() {
        // Friday 2026-06-05 15:00 through Monday 2026-06-08 09:00.
        let blocks = plan([event(ny(2026, 6, 5, 15), ny(2026, 6, 8, 9))], nyConfig { $0.mergeEnabled = false })
        XCTAssertEqual(blocks, [iv(ny(2026, 6, 5, 15), ny(2026, 6, 5, 17)),
                                iv(ny(2026, 6, 8, 8), ny(2026, 6, 8, 9))])
    }

    func testMultiDayEventFullDaysMergeOnlyWhenGapAllows() {
        let event = event(ny(2026, 6, 1, 0), ny(2026, 6, 3, 0))
        XCTAssertEqual(plan([event]).count, 2)
        // 15h overnight gap merges the two days into one block when allowed.
        let merged = plan([event], nyConfig { $0.mergeGapMinutes = 15 * 60 })
        XCTAssertEqual(merged, [iv(ny(2026, 6, 1, 8), ny(2026, 6, 2, 17))])
    }

    func testEndTimeOfMidnightMeansEndOfDay() {
        let config = nyConfig { $0.workingHours = DayHours(start: TimeOfDay(hour: 20), end: TimeOfDay(hour: 0)) }
        XCTAssertEqual(plan([event(ny(2026, 6, 1, 19), ny(2026, 6, 2, 3))], config),
                       [iv(ny(2026, 6, 1, 20), ny(2026, 6, 2, 0))])
    }

    // MARK: Padding order

    func testPadThenClipPullsEventsNearHoursIn() {
        let config = nyConfig { $0.paddingBeforeMinutes = 30; $0.paddingAfterMinutes = 30 }
        // Ends 07:45, padded to 08:15 -> overlaps working hours.
        XCTAssertEqual(plan([event(ny(2026, 6, 1, 7), ny(2026, 6, 1, 7, 45))], config),
                       [iv(ny(2026, 6, 1, 8), ny(2026, 6, 1, 8, 15))])
        // Starts 17:15, padded back to 16:45.
        XCTAssertEqual(plan([event(ny(2026, 6, 1, 17, 15), ny(2026, 6, 1, 18))], config),
                       [iv(ny(2026, 6, 1, 16, 45), ny(2026, 6, 1, 17))])
    }

    func testClipThenPadDropsEventsOutsideHours() {
        let config = nyConfig {
            $0.paddingBeforeMinutes = 30; $0.paddingAfterMinutes = 30; $0.paddingOrder = .clipThenPad
        }
        XCTAssertEqual(plan([event(ny(2026, 6, 1, 7), ny(2026, 6, 1, 7, 45))], config), [])
        XCTAssertEqual(plan([event(ny(2026, 6, 1, 17, 15), ny(2026, 6, 1, 18))], config), [])
    }

    func testClipThenPadReclipsToWorkingHours() {
        let config = nyConfig {
            $0.paddingBeforeMinutes = 30; $0.paddingAfterMinutes = 30; $0.paddingOrder = .clipThenPad
        }
        // Clipped to 08:00-08:30, padded to 07:30-09:00, re-clipped to 08:00-09:00.
        XCTAssertEqual(plan([event(ny(2026, 6, 1, 7), ny(2026, 6, 1, 8, 30))], config),
                       [iv(ny(2026, 6, 1, 8), ny(2026, 6, 1, 9))])
        // Interior events are padded normally.
        XCTAssertEqual(plan([event(ny(2026, 6, 1, 10), ny(2026, 6, 1, 11))], config),
                       [iv(ny(2026, 6, 1, 9, 30), ny(2026, 6, 1, 11, 30))])
    }

    func testPaddingNeverExceedsWorkingHours() {
        for order in [PaddingOrder.padThenClip, .clipThenPad] {
            let config = nyConfig {
                $0.paddingBeforeMinutes = 120; $0.paddingAfterMinutes = 120; $0.paddingOrder = order
            }
            XCTAssertEqual(plan([event(ny(2026, 6, 1, 9), ny(2026, 6, 1, 16))], config),
                           [iv(ny(2026, 6, 1, 8), ny(2026, 6, 1, 17))], "\(order)")
        }
    }

    // MARK: Merge

    func testPaddingDrivenOverlapMerges() {
        let config = nyConfig { $0.paddingBeforeMinutes = 15; $0.paddingAfterMinutes = 15 }
        let events = [event(ny(2026, 6, 1, 10), ny(2026, 6, 1, 11)),
                      event(ny(2026, 6, 1, 11, 20), ny(2026, 6, 1, 12))]
        XCTAssertEqual(plan(events, config), [iv(ny(2026, 6, 1, 9, 45), ny(2026, 6, 1, 12, 15))])
        XCTAssertEqual(plan(events, nyConfig { $0.mergeEnabled = false; $0.paddingBeforeMinutes = 15; $0.paddingAfterMinutes = 15 }),
                       [iv(ny(2026, 6, 1, 9, 45), ny(2026, 6, 1, 11, 15)), iv(ny(2026, 6, 1, 11, 5), ny(2026, 6, 1, 12, 15))].sorted())
    }

    func testMergeGapThreshold() {
        let events = [event(ny(2026, 6, 1, 10), ny(2026, 6, 1, 11)),
                      event(ny(2026, 6, 1, 11, 10), ny(2026, 6, 1, 12))]
        XCTAssertEqual(plan(events).count, 2)
        XCTAssertEqual(plan(events, nyConfig { $0.mergeGapMinutes = 10 }),
                       [iv(ny(2026, 6, 1, 10), ny(2026, 6, 1, 12))])
    }

    func testAdjacentEventsMergeAtGapZero() {
        let events = [event(ny(2026, 6, 1, 10), ny(2026, 6, 1, 11)),
                      event(ny(2026, 6, 1, 11), ny(2026, 6, 1, 12))]
        XCTAssertEqual(plan(events), [iv(ny(2026, 6, 1, 10), ny(2026, 6, 1, 12))])
    }

    func testWithoutMergeIdenticalEventsAreDeduplicated() {
        let e = event(ny(2026, 6, 1, 10), ny(2026, 6, 1, 11))
        XCTAssertEqual(plan([e, e], nyConfig { $0.mergeEnabled = false }), [iv(ny(2026, 6, 1, 10), ny(2026, 6, 1, 11))])
    }

    // MARK: Filters

    func testFilters() {
        let s = ny(2026, 6, 1, 10), e = ny(2026, 6, 1, 11)
        let cases: [(String, SourceEvent, (inout Config) -> Void, Bool)] = [
            ("all-day skipped", event(s, e, allDay: true), { _ in }, false),
            ("all-day kept when off", event(s, e, allDay: true), { $0.skipAllDay = false }, true),
            ("declined skipped", event(s, e, declined: true), { _ in }, false),
            ("declined kept when off", event(s, e, declined: true), { $0.skipDeclined = false }, true),
            ("free skipped", event(s, e, free: true), { _ in }, false),
            ("free kept when off", event(s, e, free: true), { $0.skipFree = false }, true),
            ("tentative kept by default", event(s, e, tentative: true), { _ in }, true),
            ("tentative skipped when on", event(s, e, tentative: true), { $0.skipTentative = true }, false),
            ("zero-length skipped", event(s, s), { _ in }, false),
            ("zero-length skipped even padded", event(s, s), { $0.paddingBeforeMinutes = 30 }, false),
        ]
        for (name, ev, edit, blocked) in cases {
            XCTAssertEqual(plan([ev], nyConfig(edit)).isEmpty, !blocked, name)
        }
    }

    // MARK: Window

    func testWindowBoundsOutput() {
        let window = iv(ny(2026, 6, 2), ny(2026, 6, 3))
        let blocks = BlockPlanner.plan(events: [event(ny(2026, 6, 1, 9), ny(2026, 6, 4, 18))],
                                       config: nyConfig { $0.mergeEnabled = false }, window: window)
        XCTAssertEqual(blocks, [iv(ny(2026, 6, 2, 8), ny(2026, 6, 2, 17))])
    }

    func testConfigWindow() {
        let config = nyConfig { $0.lookaheadDays = 30 }
        let window = config.window(now: ny(2026, 3, 1, 15))
        XCTAssertEqual(window, iv(ny(2026, 3, 1), ny(2026, 3, 31)))
    }

    // MARK: DST (America/New_York)

    private let allDays = Set(Weekday.allCases)

    func testSpringForwardDayWithNormalHours() {
        // 2026-03-08: clocks jump 02:00 -> 03:00; 08:00-17:00 EDT is 12:00Z-21:00Z.
        let config = nyConfig { $0.workingDays = allDays }
        let blocks = plan([event(ny(2026, 3, 8, 0), ny(2026, 3, 9, 0))], config)
        XCTAssertEqual(blocks, [iv(utc(2026, 3, 8, 12), utc(2026, 3, 8, 21))])
    }

    func testSpringForwardDayHoursSpanningTheGap() {
        // 01:00 EST (06:00Z) to 04:00 EDT (08:00Z): only two real hours.
        let config = nyConfig {
            $0.workingDays = allDays
            $0.workingHours = DayHours(start: TimeOfDay(hour: 1), end: TimeOfDay(hour: 4))
        }
        let blocks = plan([event(ny(2026, 3, 8, 0), ny(2026, 3, 9, 0))], config)
        XCTAssertEqual(blocks, [iv(utc(2026, 3, 8, 6), utc(2026, 3, 8, 8))])
        XCTAssertEqual(blocks[0].duration, 2 * 3600)
    }

    func testSpringForwardNonexistentStartMovesForward() {
        // 02:30 doesn't exist; it resolves to 03:00 EDT (07:00Z).
        let config = nyConfig {
            $0.workingDays = allDays
            $0.workingHours = DayHours(start: TimeOfDay(hour: 2, minute: 30), end: TimeOfDay(hour: 5))
        }
        let blocks = plan([event(ny(2026, 3, 8, 0), ny(2026, 3, 9, 0))], config)
        XCTAssertEqual(blocks, [iv(utc(2026, 3, 8, 7), utc(2026, 3, 8, 9))])
    }

    func testFallBackDayWithNormalHours() {
        // 2026-11-01: 08:00-17:00 EST is 13:00Z-22:00Z.
        let config = nyConfig { $0.workingDays = allDays }
        let blocks = plan([event(ny(2026, 11, 1, 0), ny(2026, 11, 2, 0))], config)
        XCTAssertEqual(blocks, [iv(utc(2026, 11, 1, 13), utc(2026, 11, 1, 22))])
    }

    func testFallBackDayHoursSpanningTheRepeatedHour() {
        // 00:30 EDT (04:30Z) to 03:00 EST (08:00Z): 3.5 real hours.
        let config = nyConfig {
            $0.workingDays = allDays
            $0.workingHours = DayHours(start: TimeOfDay(hour: 0, minute: 30), end: TimeOfDay(hour: 3))
        }
        let blocks = plan([event(ny(2026, 11, 1, 0), ny(2026, 11, 2, 0))], config)
        XCTAssertEqual(blocks, [iv(utc(2026, 11, 1, 4, 30), utc(2026, 11, 1, 8))])
        XCTAssertEqual(blocks[0].duration, 3.5 * 3600)
    }

    func testFallBackAmbiguousStartUsesFirstOccurrence() {
        // 01:30 happens twice; use the first (EDT, 05:30Z).
        let config = nyConfig {
            $0.workingDays = allDays
            $0.workingHours = DayHours(start: TimeOfDay(hour: 1, minute: 30), end: TimeOfDay(hour: 3))
        }
        let blocks = plan([event(ny(2026, 11, 1, 0), ny(2026, 11, 2, 0))], config)
        XCTAssertEqual(blocks, [iv(utc(2026, 11, 1, 5, 30), utc(2026, 11, 1, 8))])
    }

    func testEventAcrossDSTChangeSplitsOnLocalDays() {
        // Sat night through Mon morning across spring-forward; Sunday is a working day here.
        let config = nyConfig { $0.workingDays = allDays; $0.mergeEnabled = false }
        let blocks = plan([event(ny(2026, 3, 7, 12), ny(2026, 3, 9, 9))], config)
        XCTAssertEqual(blocks, [iv(ny(2026, 3, 7, 12), ny(2026, 3, 7, 17)),
                                iv(utc(2026, 3, 8, 12), utc(2026, 3, 8, 21)),
                                iv(ny(2026, 3, 9, 8), ny(2026, 3, 9, 9))])
    }

    // MARK: Planner + reconciler

    func testPlanThenReconcileIsIdempotent() {
        let config = nyConfig { $0.paddingBeforeMinutes = 10; $0.paddingAfterMinutes = 10 }
        let events = [event(ny(2026, 6, 1, 9), ny(2026, 6, 1, 10)),
                      event(ny(2026, 6, 1, 10, 5), ny(2026, 6, 1, 11)),
                      event(ny(2026, 6, 2, 14), ny(2026, 6, 2, 15))]
        let desired = plan(events, config)
        var nextID = 0
        let created = apply(Reconciler.reconcile(desired: desired, existing: []), to: [], nextID: &nextID)
        XCTAssertEqual(created.count, 2)
        XCTAssertEqual(Reconciler.reconcile(desired: plan(events, config), existing: created), [])
    }
}

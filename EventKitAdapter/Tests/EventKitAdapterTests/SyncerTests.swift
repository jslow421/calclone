import Core
import XCTest
@testable import EventKitAdapter

final class SyncerTests: XCTestCase {
    private let tz = "America/New_York"
    // 2026-06-01 is a Monday.
    private let now = date(2026, 6, 1, 7)
    private var store: FakeCalendarStore!

    override func setUp() {
        store = FakeCalendarStore(calendars: [
            CalendarInfo(id: "personal", title: "Personal", sourceTitle: "iCloud", allowsModifications: true),
            CalendarInfo(id: "work", title: "Work", sourceTitle: "Work", allowsModifications: true),
            CalendarInfo(id: "readonly", title: "Holidays", sourceTitle: "Sub", allowsModifications: false),
        ])
    }

    private func config(_ edit: (inout Config) -> Void = { _ in }) -> Config {
        var config = Config(timeZoneIdentifier: tz)
        config.sourceCalendarIDs = ["personal"]
        config.targetCalendarID = "work"
        edit(&config)
        return config
    }

    private func meeting(_ h1: Int, _ h2: Int, day: Int = 1) -> SourceEvent {
        SourceEvent(interval: Interval(start: date(2026, 6, day, h1), end: date(2026, 6, day, h2)))
    }

    // MARK: Safety

    func testUnmarkedTargetEventsAreNeverInTheDiff() {
        store.addSource("personal", meeting(10, 11))
        // A real work meeting, no marker, at the same time and elsewhere.
        store.addTarget("work", Interval(start: date(2026, 6, 1, 10), end: date(2026, 6, 1, 11)), notes: nil)
        store.addTarget("work", Interval(start: date(2026, 6, 1, 14), end: date(2026, 6, 1, 15)), notes: "agenda: budget")
        store.addTarget("work", Interval(start: date(2026, 6, 1, 16), end: date(2026, 6, 1, 17)), notes: "cal-blocker:v1 plus more")

        let plan = try! Syncer.plan(store: store, config: config(), now: now)
        XCTAssertTrue(plan.existing.isEmpty)
        XCTAssertEqual(plan.operations, [.create(Interval(start: date(2026, 6, 1, 10), end: date(2026, 6, 1, 11)))])

        try! Syncer.run(store: store, config: config(), now: now)
        XCTAssertEqual(store.events.filter { $0.calendarID == "work" && $0.notes != Marker.notes }.count, 3,
                       "unmarked events must survive a sync")
    }

    func testApplyRefusesToTouchUnmarkedOrForeignEvents() {
        store.addTarget("work", Interval(start: date(2026, 6, 1, 14), end: date(2026, 6, 1, 15)), notes: nil)
        store.addTarget("personal", Interval(start: date(2026, 6, 1, 9), end: date(2026, 6, 1, 10)), notes: Marker.notes)
        let template = BlockTemplate(title: "Blocked", availability: .busy)
        let unmarked = store.events[0].id, foreign = store.events[1].id
        let before = store.events

        for op in [SyncOperation.delete(id: unmarked), .update(id: unmarked, Interval(start: now, end: now.addingTimeInterval(60))),
                   .delete(id: foreign)] {
            XCTAssertThrowsError(try store.apply([.create(Interval(start: now, end: now.addingTimeInterval(60))), op],
                                                 calendarID: "work", template: template)) { error in
                XCTAssertTrue(error is CalendarStoreError)
            }
            XCTAssertEqual(store.events, before, "a rejected batch must write nothing")
        }
    }

    func testMarkerMustMatchExactly() {
        XCTAssertTrue(Marker.isManaged(notes: "cal-blocker:v1"))
        XCTAssertFalse(Marker.isManaged(notes: nil))
        XCTAssertFalse(Marker.isManaged(notes: ""))
        XCTAssertFalse(Marker.isManaged(notes: "cal-blocker:v1\nextra"))
        XCTAssertFalse(Marker.isManaged(notes: "cal-blocker:v2"))
    }

    // MARK: Calendar resolution

    func testTargetAlsoSourceIsRejected() {
        XCTAssertThrowsError(try Syncer.plan(store: store, config: config { $0.sourceCalendarIDs = ["personal", "work"] }, now: now)) {
            XCTAssertEqual($0 as? CalendarStoreError, .targetIsSource(id: "work"))
        }
    }

    func testMissingCalendarsStopTheSync() {
        XCTAssertThrowsError(try Syncer.plan(store: store, config: config { $0.targetCalendarID = "gone" }, now: now)) {
            XCTAssertEqual($0 as? CalendarStoreError, .calendarMissing(id: "gone"))
        }
        XCTAssertThrowsError(try Syncer.plan(store: store, config: config { $0.sourceCalendarIDs = ["gone"] }, now: now)) {
            XCTAssertEqual($0 as? CalendarStoreError, .calendarMissing(id: "gone"))
        }
    }

    func testReadOnlyTargetIsRejected() {
        XCTAssertThrowsError(try Syncer.plan(store: store, config: config { $0.targetCalendarID = "readonly" }, now: now)) {
            XCTAssertEqual($0 as? CalendarStoreError, .calendarNotWritable(id: "readonly"))
        }
    }

    func testMissingConfigIsRejected() {
        XCTAssertThrowsError(try Syncer.plan(store: store, config: config { $0.targetCalendarID = nil }, now: now)) {
            XCTAssertEqual($0 as? CalendarStoreError, .noTarget)
        }
        XCTAssertThrowsError(try Syncer.plan(store: store, config: config { $0.sourceCalendarIDs = [] }, now: now)) {
            XCTAssertEqual($0 as? CalendarStoreError, .noSources)
        }
    }

    func testInvalidTimeZoneStopsTheSyncBeforeAnyWrite() {
        store.addSource("personal", meeting(10, 11))
        XCTAssertThrowsError(try Syncer.run(store: store, config: config { $0.timeZoneIdentifier = "Not/AZone" }, now: now)) {
            XCTAssertEqual($0 as? ConfigError, .invalidTimeZone("Not/AZone"))
        }
        XCTAssertEqual(store.applyCalls, 0)
    }

    // MARK: Behavior

    func testDryRunPlanWritesNothing() {
        store.addSource("personal", meeting(10, 11))
        let before = store.events
        let plan = try! Syncer.plan(store: store, config: config(), now: now)
        XCTAssertEqual(plan.operations.count, 1)
        XCTAssertEqual(store.events, before)
        XCTAssertEqual(store.applyCalls, 0)
    }

    func testSecondRunIsIdempotent() {
        store.addSource("personal", meeting(9, 10))
        store.addSource("personal", meeting(13, 14))
        store.addSource("personal", meeting(9, 10, day: 2))

        let first = try! Syncer.run(store: store, config: config(), now: now)
        XCTAssertEqual(first.operations.count, 3)
        XCTAssertEqual(store.applyCalls, 1, "one batch")

        let second = try! Syncer.run(store: store, config: config(), now: now)
        XCTAssertEqual(second.operations, [])
        XCTAssertEqual(store.applyCalls, 1, "no-op run must not write")
    }

    func testMovedSourceEventUpdatesInPlace() {
        store.addSource("personal", meeting(10, 11))
        try! Syncer.run(store: store, config: config(), now: now)
        let blockID = store.events.first { $0.notes == Marker.notes }!.id

        store.events.removeAll { $0.calendarID == "personal" }
        store.addSource("personal", meeting(10, 12))
        let plan = try! Syncer.run(store: store, config: config(), now: now)
        XCTAssertEqual(plan.operations, [.update(id: blockID, Interval(start: date(2026, 6, 1, 10), end: date(2026, 6, 1, 12)))])
    }

    func testRemovedSourceEventDeletesOnlyTheManagedBlock() {
        store.addSource("personal", meeting(10, 11))
        store.addTarget("work", Interval(start: date(2026, 6, 1, 10), end: date(2026, 6, 1, 11)), notes: nil)
        try! Syncer.run(store: store, config: config(), now: now)

        store.events.removeAll { $0.calendarID == "personal" }
        try! Syncer.run(store: store, config: config(), now: now)
        XCTAssertEqual(store.events.filter { $0.calendarID == "work" }.map(\.notes), [nil])
    }

    func testManagedEventsOutsideWindowAreIgnored() {
        store.addTarget("work", Interval(start: date(2027, 1, 4, 10), end: date(2027, 1, 4, 11)), notes: Marker.notes)
        let plan = try! Syncer.plan(store: store, config: config(), now: now)
        XCTAssertEqual(plan.operations, [])
    }
}

func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    return calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
}

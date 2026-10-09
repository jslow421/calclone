import Foundation
@testable import Core

let nyID = "America/New_York"

func ny(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: nyID)!
    return calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

func utc(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

func iv(_ start: Date, _ end: Date) -> Interval { Interval(start: start, end: end) }

func event(_ start: Date, _ end: Date, allDay: Bool = false, declined: Bool = false,
           free: Bool = false, tentative: Bool = false) -> SourceEvent {
    SourceEvent(interval: iv(start, end), isAllDay: allDay, isDeclined: declined,
                isFree: free, isTentative: tentative)
}

func nyConfig(_ edit: (inout Config) -> Void = { _ in }) -> Config {
    var config = Config(timeZoneIdentifier: nyID)
    edit(&config)
    return config
}

/// Wide window around the dates used in tests.
let wideWindow = iv(ny(2026, 1, 1), ny(2027, 1, 1))

/// Applies reconciler output to a list of events, like the adapter would.
func apply(_ ops: [SyncOperation], to events: [ManagedEvent], nextID: inout Int) -> [ManagedEvent] {
    var result = events
    for op in ops {
        switch op {
        case .create(let interval):
            result.append(ManagedEvent(id: "new-\(nextID)", interval: interval))
            nextID += 1
        case .update(let id, let interval):
            let index = result.firstIndex { $0.id == id }!
            result[index].interval = interval
        case .delete(let id):
            result.removeAll { $0.id == id }
        }
    }
    return result
}

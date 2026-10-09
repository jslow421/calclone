import Core
import Foundation
@testable import EventKitAdapter

struct FakeEvent: Equatable {
    var id: String
    var calendarID: String
    var interval: Interval
    var notes: String?
    var title = "Meeting"
    var source = SourceEvent(interval: Interval(start: .distantPast, end: .distantPast))
}

/// In-memory store with the same safety rules as `EKCalendarStore`.
final class FakeCalendarStore: CalendarStore {
    var infos: [CalendarInfo]
    var events: [FakeEvent] = []
    private var nextID = 0
    private(set) var applyCalls = 0

    init(calendars: [CalendarInfo]) { infos = calendars }

    func addSource(_ calendarID: String, _ event: SourceEvent) {
        events.append(FakeEvent(id: "src-\(nextID)", calendarID: calendarID, interval: event.interval, notes: nil, source: event))
        nextID += 1
    }

    func addTarget(_ calendarID: String, _ interval: Interval, notes: String?) {
        events.append(FakeEvent(id: "tgt-\(nextID)", calendarID: calendarID, interval: interval, notes: notes))
        nextID += 1
    }

    func calendars() throws -> [CalendarInfo] { infos }

    func sourceEvents(in window: Interval, calendarIDs: [String]) throws -> [SourceEvent] {
        events.filter { calendarIDs.contains($0.calendarID) && $0.interval.overlaps(window) }.map(\.source)
    }

    func managedEvents(in window: Interval, calendarID: String) throws -> [ManagedEvent] {
        events.filter { $0.calendarID == calendarID && Marker.isManaged(notes: $0.notes) && $0.interval.overlaps(window) }
            .map { ManagedEvent(id: $0.id, interval: $0.interval) }
    }

    func apply(_ operations: [SyncOperation], calendarID: String, template: BlockTemplate) throws {
        applyCalls += 1
        for op in operations {
            switch op {
            case .create: break
            case .update(let id, _), .delete(let id):
                guard let event = events.first(where: { $0.id == id }) else { throw CalendarStoreError.eventMissing(eventID: id) }
                guard Marker.isManaged(notes: event.notes), event.calendarID == calendarID else {
                    throw CalendarStoreError.notManaged(eventID: id)
                }
            }
        }
        for op in operations {
            switch op {
            case .create(let interval):
                events.append(FakeEvent(id: "tgt-\(nextID)", calendarID: calendarID, interval: interval,
                                        notes: Marker.notes, title: template.title))
                nextID += 1
            case .update(let id, let interval):
                events[events.firstIndex { $0.id == id }!].interval = interval
            case .delete(let id):
                events.removeAll { $0.id == id }
            }
        }
    }
}

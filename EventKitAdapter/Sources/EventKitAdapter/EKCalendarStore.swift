import Core
import EventKit
import Foundation

/// The only code that touches EventKit.
public final class EKCalendarStore: CalendarStore {
    private let store: EKEventStore

    public init(store: EKEventStore = EKEventStore()) {
        self.store = store
    }

    public func requestAccess() async throws {
        guard try await store.requestFullAccessToEvents() else { throw CalendarStoreError.accessDenied }
    }

    public func calendars() throws -> [CalendarInfo] {
        store.calendars(for: .event).map {
            CalendarInfo(id: $0.calendarIdentifier, title: $0.title, sourceTitle: $0.source.title,
                         allowsModifications: $0.allowsContentModifications)
        }
    }

    public func sourceEvents(in window: Interval, calendarIDs: [String]) throws -> [SourceEvent] {
        let calendars = try resolve(calendarIDs)
        let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: calendars)
        return store.events(matching: predicate).map(Self.sourceEvent)
    }

    public func managedEvents(in window: Interval, calendarID: String) throws -> [ManagedEvent] {
        let calendar = try resolve([calendarID])[0]
        let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: [calendar])
        return store.events(matching: predicate).compactMap { event in
            guard Marker.isManaged(notes: event.notes), let id = event.eventIdentifier else { return nil }
            return ManagedEvent(id: id, interval: Interval(start: event.startDate, end: event.endDate))
        }
    }

    public func apply(_ operations: [SyncOperation], calendarID: String, template: BlockTemplate) throws {
        let calendar = try resolve([calendarID])[0]
        guard calendar.allowsContentModifications else { throw CalendarStoreError.calendarNotWritable(id: calendarID) }

        // Validate every update/delete before writing anything.
        var targets: [String: EKEvent] = [:]
        for op in operations {
            switch op {
            case .create: break
            case .update(let id, _), .delete(let id):
                guard let event = store.event(withIdentifier: id) else { throw CalendarStoreError.eventMissing(eventID: id) }
                guard Marker.isManaged(notes: event.notes), event.calendar.calendarIdentifier == calendarID else {
                    throw CalendarStoreError.notManaged(eventID: id)
                }
                targets[id] = event
            }
        }

        do {
            for op in operations {
                switch op {
                case .create(let interval):
                    let event = EKEvent(eventStore: store)
                    event.calendar = calendar
                    event.title = template.title
                    event.notes = Marker.notes
                    event.startDate = interval.start
                    event.endDate = interval.end
                    event.availability = Self.availability(template.availability)
                    event.alarms = []
                    try store.save(event, span: .thisEvent, commit: false)
                case .update(let id, let interval):
                    let event = targets[id]!
                    event.startDate = interval.start
                    event.endDate = interval.end
                    try store.save(event, span: .thisEvent, commit: false)
                case .delete(let id):
                    try store.remove(targets[id]!, span: .thisEvent, commit: false)
                }
            }
            try store.commit()
        } catch {
            store.reset()
            throw error
        }
    }

    private func resolve(_ ids: [String]) throws -> [EKCalendar] {
        try ids.map { id in
            guard let calendar = store.calendar(withIdentifier: id) else { throw CalendarStoreError.calendarMissing(id: id) }
            return calendar
        }
    }

    static func sourceEvent(_ event: EKEvent) -> SourceEvent {
        let me = event.attendees?.first { $0.isCurrentUser }
        return SourceEvent(
            interval: Interval(start: event.startDate, end: event.endDate),
            isAllDay: event.isAllDay,
            // A cancelled event shouldn't block time either.
            isDeclined: me?.participantStatus == .declined || event.status == .canceled,
            isFree: event.availability == .free,
            isTentative: event.status == .tentative || me?.participantStatus == .tentative
        )
    }

    static func availability(_ availability: Availability) -> EKEventAvailability {
        switch availability {
        case .busy: .busy
        case .tentative: .tentative
        case .outOfOffice: .unavailable
        }
    }
}

import Core
import Foundation

/// Every managed event carries this line in its notes. Only events carrying it
/// on the target calendar may ever be updated or deleted (SPEC §6).
public enum Marker {
    public static let notes = "cal-blocker:v1"

    public static func isManaged(notes: String?) -> Bool {
        notes == Marker.notes
    }
}

public struct CalendarInfo: Hashable {
    public var id: String
    public var title: String
    public var sourceTitle: String
    public var allowsModifications: Bool

    public init(id: String, title: String, sourceTitle: String, allowsModifications: Bool) {
        self.id = id
        self.title = title
        self.sourceTitle = sourceTitle
        self.allowsModifications = allowsModifications
    }
}

/// What a created block looks like beyond its interval.
public struct BlockTemplate: Hashable {
    public var title: String
    public var availability: Availability

    public init(title: String, availability: Availability) {
        self.title = title
        self.availability = availability
    }
}

public enum CalendarStoreError: Error, Equatable, CustomStringConvertible {
    case accessDenied
    case calendarMissing(id: String)
    case calendarNotWritable(id: String)
    case targetIsSource(id: String)
    case notManaged(eventID: String)
    case eventMissing(eventID: String)
    case noTarget
    case noSources

    public var description: String {
        switch self {
        case .accessDenied: "calendar access denied"
        case .calendarMissing(let id): "calendar \(id) not found; pausing rather than guessing"
        case .calendarNotWritable(let id): "target calendar \(id) is read-only"
        case .targetIsSource(let id): "target calendar \(id) is also a source; this would loop"
        case .notManaged(let id): "refusing to modify event \(id): it does not carry the marker or is not on the target calendar"
        case .eventMissing(let id): "event \(id) no longer exists"
        case .noTarget: "no target calendar configured"
        case .noSources: "no source calendars configured"
        }
    }
}

/// The only seam between sync logic and the system calendar. `EKCalendarStore`
/// is the real implementation; tests use an in-memory fake.
public protocol CalendarStore {
    func calendars() throws -> [CalendarInfo]

    /// Event occurrences (recurrences expanded) on the given calendars.
    func sourceEvents(in window: Interval, calendarIDs: [String]) throws -> [SourceEvent]

    /// Only marker-carrying events on the target calendar.
    func managedEvents(in window: Interval, calendarID: String) throws -> [ManagedEvent]

    /// Applies all operations to the target calendar and commits once. Update and
    /// delete must throw `notManaged` for any event that isn't marked and on the target.
    func apply(_ operations: [SyncOperation], calendarID: String, template: BlockTemplate) throws
}

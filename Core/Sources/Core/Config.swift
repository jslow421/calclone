import Foundation

/// Matches `Calendar`'s weekday numbering (Sunday = 1).
public enum Weekday: Int, Codable, CaseIterable, Hashable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday
}

/// A wall-clock time. `hour` may be 24 (with minute 0) to mean end of day.
public struct TimeOfDay: Codable, Hashable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int = 0) {
        self.hour = hour
        self.minute = minute
    }
}

public struct DayHours: Codable, Hashable {
    public var start: TimeOfDay
    public var end: TimeOfDay

    public init(start: TimeOfDay, end: TimeOfDay) {
        self.start = start
        self.end = end
    }
}

public enum PaddingOrder: String, Codable, Hashable {
    case padThenClip
    case clipThenPad
}

public enum Availability: String, Codable, Hashable {
    case busy
    case tentative
    case outOfOffice
}

/// Sync settings with the SPEC §5 defaults. Calendar identifiers are plain
/// strings so this type stays free of EventKit.
public struct Config: Codable, Equatable {
    public var sourceCalendarIDs: [String] = []
    public var targetCalendarID: String?

    public var workingDays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
    public var workingHours = DayHours(start: TimeOfDay(hour: 8), end: TimeOfDay(hour: 17))
    public var dayOverrides: [Weekday: DayHours] = [:]
    public var timeZoneIdentifier: String

    public var paddingBeforeMinutes = 0
    public var paddingAfterMinutes = 0
    public var paddingOrder = PaddingOrder.padThenClip

    public var mergeEnabled = true
    public var mergeGapMinutes = 0

    public var skipAllDay = true
    public var skipDeclined = true
    public var skipFree = true
    public var skipTentative = false

    public var lookaheadDays = 30
    public var blockTitle = "Blocked"
    public var availability = Availability.busy
    public var pollIntervalMinutes = 15
    public var launchAtLogin = true

    /// The time zone is injected; callers pass `TimeZone.current.identifier`
    /// for the "system" default.
    public init(timeZoneIdentifier: String) {
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    public var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .gmt
    }

    /// Gregorian calendar in the configured time zone. All day math goes through this.
    public var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    public func hours(for weekday: Weekday) -> DayHours {
        dayOverrides[weekday] ?? workingHours
    }

    /// SPEC §6 step 1: start of today through today + lookahead days.
    public func window(now: Date) -> Interval {
        let calendar = calendar
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: lookaheadDays, to: start) ?? start
        return Interval(start: start, end: end)
    }
}

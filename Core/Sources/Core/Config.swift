import Foundation

/// Matches `Calendar`'s weekday numbering (Sunday = 1).
public enum Weekday: Int, Codable, CaseIterable, Hashable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday
}

/// A wall-clock time, 00:00 to 23:59.
public struct TimeOfDay: Codable, Hashable {
    public var hour: Int
    public var minute: Int

    /// Not validating, so tests and callers can use literals; see `isValid` and `Config.validate()`.
    public init(hour: Int, minute: Int = 0) {
        self.hour = hour
        self.minute = minute
    }

    public var isValid: Bool {
        (0...23).contains(hour) && (0...59).contains(minute)
    }

    private enum CodingKeys: String, CodingKey { case hour, minute }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let hour = try container.decode(Int.self, forKey: .hour)
        let minute = try container.decode(Int.self, forKey: .minute)
        self.init(hour: hour, minute: minute)
        guard isValid else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Invalid time of day \(hour):\(minute)"))
        }
    }
}

public enum ConfigError: Error, Equatable {
    case invalidTimeZone(String)
    case invalidTimeOfDay(TimeOfDay)
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

    /// Nil when the identifier doesn't resolve; never guesses a fallback.
    public var timeZone: TimeZone? {
        TimeZone(identifier: timeZoneIdentifier)
    }

    /// Gregorian calendar in the configured time zone, nil if the zone is invalid.
    /// All day math goes through this.
    public var calendar: Calendar? {
        guard let timeZone else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// Rejects settings that would silently shift or corrupt blocks, so callers
    /// can pause and notify instead of guessing.
    public func validate() throws {
        guard timeZone != nil else { throw ConfigError.invalidTimeZone(timeZoneIdentifier) }
        let allHours = [workingHours] + Array(dayOverrides.values)
        for time in allHours.flatMap({ [$0.start, $0.end] }) where !time.isValid {
            throw ConfigError.invalidTimeOfDay(time)
        }
    }

    public func hours(for weekday: Weekday) -> DayHours {
        dayOverrides[weekday] ?? workingHours
    }

    /// SPEC §6 step 1: start of today through today + lookahead days.
    public func window(now: Date) throws -> Interval {
        try validate()
        guard let calendar else { throw ConfigError.invalidTimeZone(timeZoneIdentifier) }
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: lookaheadDays, to: start) ?? start
        return Interval(start: start, end: end)
    }
}

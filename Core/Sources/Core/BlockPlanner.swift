import Foundation

/// Turns source events into the intervals that should be blocked on the target calendar.
public enum BlockPlanner {
    /// Pure function: the same inputs always give the same sorted, non-overlapping
    /// (when merging) intervals, all inside `window` and inside working hours.
    public static func plan(events: [SourceEvent], config: Config, window: Interval) -> [Interval] {
        let calendar = config.calendar
        let before = TimeInterval(config.paddingBeforeMinutes * 60)
        let after = TimeInterval(config.paddingAfterMinutes * 60)

        var blocks: [Interval] = []
        for event in events where !isSkipped(event, config: config) {
            switch config.paddingOrder {
            case .padThenClip:
                let padded = event.interval.padded(before: before, after: after)
                guard let span = padded.intersection(window) else { continue }
                for hours in workingIntervals(touching: span, config: config, calendar: calendar) {
                    if let block = span.intersection(hours) { blocks.append(block) }
                }
            case .clipThenPad:
                guard let span = event.interval.intersection(window) else { continue }
                for hours in workingIntervals(touching: span, config: config, calendar: calendar) {
                    guard let clipped = span.intersection(hours) else { continue }
                    let padded = clipped.padded(before: before, after: after)
                    if let block = padded.intersection(hours)?.intersection(window) {
                        blocks.append(block)
                    }
                }
            }
        }

        if config.mergeEnabled {
            return Interval.merge(blocks, gap: TimeInterval(config.mergeGapMinutes * 60))
        }
        // Without merging, overlapping duplicates would never reconcile cleanly.
        return Array(Set(blocks.filter { !$0.isEmpty })).sorted()
    }

    static func isSkipped(_ event: SourceEvent, config: Config) -> Bool {
        event.interval.isEmpty
            || (config.skipAllDay && event.isAllDay)
            || (config.skipDeclined && event.isDeclined)
            || (config.skipFree && event.isFree)
            || (config.skipTentative && event.isTentative)
    }

    /// Working-hours intervals for every calendar day that `span` touches.
    static func workingIntervals(touching span: Interval, config: Config, calendar: Calendar) -> [Interval] {
        var result: [Interval] = []
        var day = calendar.startOfDay(for: span.start)
        while day < span.end {
            if let weekday = Weekday(rawValue: calendar.component(.weekday, from: day)),
               config.workingDays.contains(weekday),
               let hours = workingInterval(on: day, hours: config.hours(for: weekday), calendar: calendar) {
                result.append(hours)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    /// Resolves wall-clock hours on the day starting at `dayStart`. A start time that
    /// doesn't exist (spring forward) moves to the next valid time; an ambiguous one
    /// (fall back) uses its first occurrence.
    static func workingInterval(on dayStart: Date, hours: DayHours, calendar: Calendar) -> Interval? {
        guard let start = resolve(hours.start, on: dayStart, calendar: calendar),
              let end = resolve(hours.end, on: dayStart, calendar: calendar) else { return nil }
        let interval = Interval(start: start, end: end)
        return interval.isEmpty ? nil : interval
    }

    private static func resolve(_ time: TimeOfDay, on dayStart: Date, calendar: Calendar) -> Date? {
        if time.hour >= 24 {
            return calendar.date(byAdding: .day, value: 1, to: dayStart)
        }
        return calendar.date(
            bySettingHour: time.hour,
            minute: time.minute,
            second: 0,
            of: dayStart,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )
    }
}

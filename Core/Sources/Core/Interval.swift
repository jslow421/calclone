import Foundation

/// A half-open span of time `[start, end)`.
public struct Interval: Hashable, Codable, Comparable {
    public var start: Date
    public var end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    /// True when the interval has no duration (zero-length or inverted).
    public var isEmpty: Bool { end <= start }

    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }

    /// The overlap of two intervals, or nil if they share no time.
    public func intersection(_ other: Interval) -> Interval? {
        let result = Interval(start: max(start, other.start), end: min(end, other.end))
        return result.isEmpty ? nil : result
    }

    /// Expands the interval by the given number of seconds on each side.
    /// Padding is an elapsed duration, so plain seconds are correct here.
    public func padded(before: TimeInterval, after: TimeInterval) -> Interval {
        Interval(start: start.addingTimeInterval(-before), end: end.addingTimeInterval(after))
    }

    /// True when the two intervals share time.
    public func overlaps(_ other: Interval) -> Bool {
        intersection(other) != nil
    }

    /// True when one interval ends exactly where the other begins.
    public func isAdjacent(to other: Interval) -> Bool {
        end == other.start || other.end == start
    }

    public static func < (lhs: Interval, rhs: Interval) -> Bool {
        (lhs.start, lhs.end) < (rhs.start, rhs.end)
    }

    /// Sorts the intervals and merges those that overlap or are separated by
    /// at most `gap` seconds. Empty intervals are dropped.
    public static func merge(_ intervals: [Interval], gap: TimeInterval = 0) -> [Interval] {
        var result: [Interval] = []
        for interval in intervals.filter({ !$0.isEmpty }).sorted() {
            if let last = result.last, interval.start.timeIntervalSince(last.end) <= gap {
                result[result.count - 1].end = max(last.end, interval.end)
            } else {
                result.append(interval)
            }
        }
        return result
    }
}

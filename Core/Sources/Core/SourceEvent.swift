import Foundation

/// A source-calendar event reduced to what planning needs. The EventKit
/// adapter maps `EKEvent` occurrences to this type.
public struct SourceEvent: Hashable {
    public var interval: Interval
    public var isAllDay: Bool
    public var isDeclined: Bool
    public var isFree: Bool
    public var isTentative: Bool

    public init(
        interval: Interval,
        isAllDay: Bool = false,
        isDeclined: Bool = false,
        isFree: Bool = false,
        isTentative: Bool = false
    ) {
        self.interval = interval
        self.isAllDay = isAllDay
        self.isDeclined = isDeclined
        self.isFree = isFree
        self.isTentative = isTentative
    }
}

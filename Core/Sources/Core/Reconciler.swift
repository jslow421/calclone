import Foundation

/// A marker-carrying event already on the target calendar. The adapter must pass
/// only marked events; the reconciler can't tell the difference, so it can never
/// touch an event it wasn't given.
public struct ManagedEvent: Hashable {
    public var id: String
    public var interval: Interval

    public init(id: String, interval: Interval) {
        self.id = id
        self.interval = interval
    }
}

public enum SyncOperation: Hashable {
    case create(Interval)
    case update(id: String, Interval)
    case delete(id: String)
}

public enum Reconciler {
    /// Diffs desired intervals against existing managed events (SPEC §6 step 7).
    /// Applying the result and reconciling again yields no operations.
    public static func reconcile(desired: [Interval], existing: [ManagedEvent]) -> [SyncOperation] {
        var unmatchedDesired = Array(Set(desired.filter { !$0.isEmpty })).sorted()
        let sortedExisting = existing.sorted { ($0.interval, $0.id) < ($1.interval, $1.id) }

        // Exact matches are no-ops. Extra events with the same interval are leftovers.
        var leftoverExisting: [ManagedEvent] = []
        var matched = Set<Interval>()
        for event in sortedExisting {
            if unmatchedDesired.contains(event.interval), !matched.contains(event.interval) {
                matched.insert(event.interval)
            } else {
                leftoverExisting.append(event)
            }
        }
        unmatchedDesired.removeAll { matched.contains($0) }

        // Pair leftovers for update, best match first: most overlap, then nearest start.
        struct Pair {
            let desired: Interval
            let event: ManagedEvent
            let overlap: TimeInterval
            let distance: TimeInterval
        }
        var pairs: [Pair] = []
        for interval in unmatchedDesired {
            for event in leftoverExisting {
                pairs.append(Pair(
                    desired: interval,
                    event: event,
                    overlap: interval.intersection(event.interval)?.duration ?? 0,
                    distance: abs(interval.start.timeIntervalSince(event.interval.start))
                ))
            }
        }
        pairs.sort {
            if $0.overlap != $1.overlap { return $0.overlap > $1.overlap }
            if $0.distance != $1.distance { return $0.distance < $1.distance }
            return ($0.desired, $0.event.id) < ($1.desired, $1.event.id)
        }

        var updates: [SyncOperation] = []
        var usedDesired = Set<Interval>()
        var usedEvents = Set<String>()
        for pair in pairs where !usedDesired.contains(pair.desired) && !usedEvents.contains(pair.event.id) {
            usedDesired.insert(pair.desired)
            usedEvents.insert(pair.event.id)
            updates.append(.update(id: pair.event.id, pair.desired))
        }

        let creates = unmatchedDesired.filter { !usedDesired.contains($0) }.map(SyncOperation.create)
        let deletes = leftoverExisting.filter { !usedEvents.contains($0.id) }.map { SyncOperation.delete(id: $0.id) }
        return updates + creates + deletes
    }
}

import Core
import Foundation

/// The result of one sync computation, before anything is written.
public struct SyncPlan {
    public var window: Interval
    public var sourceEventCount: Int
    public var desired: [Interval]
    public var existing: [ManagedEvent]
    public var operations: [SyncOperation]
}

public enum Syncer {
    /// Resolves calendars, computes desired blocks and diffs them against the
    /// managed events. Writes nothing.
    public static func plan(store: CalendarStore, config: Config, now: Date) throws -> SyncPlan {
        guard let targetID = config.targetCalendarID else { throw CalendarStoreError.noTarget }
        guard !config.sourceCalendarIDs.isEmpty else { throw CalendarStoreError.noSources }
        if config.sourceCalendarIDs.contains(targetID) { throw CalendarStoreError.targetIsSource(id: targetID) }

        // Re-resolve by identifier every run; a missing calendar stops the sync.
        let calendars = Dictionary(uniqueKeysWithValues: try store.calendars().map { ($0.id, $0) })
        for id in config.sourceCalendarIDs where calendars[id] == nil {
            throw CalendarStoreError.calendarMissing(id: id)
        }
        guard let target = calendars[targetID] else { throw CalendarStoreError.calendarMissing(id: targetID) }
        guard target.allowsModifications else { throw CalendarStoreError.calendarNotWritable(id: targetID) }

        let window = try config.window(now: now)
        let events = try store.sourceEvents(in: window, calendarIDs: config.sourceCalendarIDs)
        let desired = try BlockPlanner.plan(events: events, config: config, window: window)
        let existing = try store.managedEvents(in: window, calendarID: targetID)
        return SyncPlan(
            window: window,
            sourceEventCount: events.count,
            desired: desired,
            existing: existing,
            operations: Reconciler.reconcile(desired: desired, existing: existing)
        )
    }

    /// Plans, then writes the operations in one batch.
    @discardableResult
    public static func run(store: CalendarStore, config: Config, now: Date) throws -> SyncPlan {
        let plan = try plan(store: store, config: config, now: now)
        if !plan.operations.isEmpty, let targetID = config.targetCalendarID {
            try store.apply(plan.operations, calendarID: targetID,
                            template: BlockTemplate(title: config.blockTitle, availability: config.availability))
        }
        return plan
    }
}

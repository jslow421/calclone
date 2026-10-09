import EventKit
import Foundation

// Milestone 1 go/no-go check. Read-only unless --target <calendarIdentifier> is given.
// --keep leaves the test event in place so it can be checked on the work side;
// --cleanup (with --target) deletes leftover test events.
// Only ever writes to the target calendar, and only deletes events carrying the marker.

let marker = "cal-blocker:v1"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

var targetID: String?
var keep = false
var cleanup = false
let usage = "usage: gonogo [--target <calendarIdentifier> [--keep | --cleanup]]"
var args = CommandLine.arguments.dropFirst()
while let arg = args.popFirst() {
    switch arg {
    case "--target":
        guard let v = args.popFirst() else { fail("--target needs a calendar identifier") }
        targetID = v
    case "--keep": keep = true
    case "--cleanup": cleanup = true
    default:
        fail("unknown argument \(arg)\n\(usage)")
    }
}
if keep && cleanup { fail("--keep and --cleanup are mutually exclusive") }
if (keep || cleanup) && targetID == nil { fail("--keep/--cleanup need --target\n\(usage)") }

let store = EKEventStore()

let granted: Bool
do {
    granted = try await store.requestFullAccessToEvents()
} catch {
    fail("access request failed: \(error)")
}
guard granted else {
    fail("calendar access denied (status \(EKEventStore.authorizationStatus(for: .event).rawValue)). Enable in System Settings > Privacy & Security > Calendars.")
}

let typeNames: [EKCalendarType: String] = [
    .local: "local", .calDAV: "calDAV", .exchange: "exchange",
    .subscription: "subscription", .birthday: "birthday",
]

print("Calendars:")
for cal in store.calendars(for: .event).sorted(by: { ($0.source.title, $0.title) < ($1.source.title, $1.title) }) {
    print("  \(cal.title)  [source: \(cal.source.title), type: \(typeNames[cal.type] ?? "?"), writable: \(cal.allowsContentModifications)]")
    print("    id: \(cal.calendarIdentifier)")
}

guard let targetID else {
    print("\nRead-only run. Re-run with --target <id> to test create/delete.")
    exit(0)
}

guard let calendar = store.calendar(withIdentifier: targetID) else { fail("no calendar with id \(targetID)") }
guard calendar.allowsContentModifications else { fail("calendar '\(calendar.title)' is not writable") }

print("\nTarget: \(calendar.title) (source: \(calendar.source.title))")

let testTitle = "Blocked (gonogo test)"

/// Removes marked test events from the target calendar only; returns how many.
func removeMarked(_ events: [EKEvent]) -> Int {
    var deleted = 0
    for e in events where e.notes == marker && e.title == testTitle && e.calendar.calendarIdentifier == calendar.calendarIdentifier {
        do {
            try store.remove(e, span: .thisEvent, commit: false)
            deleted += 1
        } catch {
            fail("remove failed: \(error) — delete '\(testTitle)' manually")
        }
    }
    do {
        try store.commit()
    } catch {
        fail("commit failed: \(error)")
    }
    return deleted
}

if cleanup {
    let now = Date()
    // Look back too: the kept 03:00 event may already have ended.
    let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-30 * 86400), end: now.addingTimeInterval(7 * 86400), calendars: [calendar])
    print("Cleanup (last 30 days to next 7): deleted \(removeMarked(store.events(matching: predicate))) test event(s).")
    exit(0)
}

// Create: attendee-less event tomorrow at 03:00 for 15 minutes, carrying the marker.
let cal = Calendar.current
let start = cal.date(bySettingHour: 3, minute: 0, second: 0, of: cal.date(byAdding: .day, value: 1, to: Date())!)!
let event = EKEvent(eventStore: store)
event.calendar = calendar
event.title = testTitle
event.notes = marker
event.startDate = start
event.endDate = start.addingTimeInterval(15 * 60)
event.availability = .busy
event.alarms = []

do {
    try store.save(event, span: .thisEvent, commit: true)
} catch {
    fail("save failed: \(error)")
}
let eventID = event.eventIdentifier ?? "?"
print("Created event \(eventID) at \(start)")

// Re-fetch to confirm it round-trips through the store.
let predicate = store.predicateForEvents(withStart: start.addingTimeInterval(-60), end: start.addingTimeInterval(16 * 60), calendars: [calendar])
let found = store.events(matching: predicate).filter { $0.notes == marker && $0.title == event.title }
print("Re-fetch: found \(found.count) marked event(s); attendees: \(found.first?.attendees?.count ?? 0)")

if keep {
    print("Kept event. Check it on the work side (web/Outlook), then run with --target \(targetID) --cleanup.")
    exit(0)
}

// Delete only marked events from the target calendar.
print("Deleted \(removeMarked(found)) event(s). GO: create/save/fetch/delete all succeeded.")

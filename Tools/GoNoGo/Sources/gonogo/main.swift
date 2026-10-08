import EventKit
import Foundation

// Milestone 1 go/no-go check. Read-only unless --target <calendarIdentifier> is given.
// Only ever writes to the target calendar, and only deletes events carrying the marker.

let marker = "cal-blocker:v1"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

var targetID: String?
var args = CommandLine.arguments.dropFirst()
while let arg = args.popFirst() {
    switch arg {
    case "--target":
        guard let v = args.popFirst() else { fail("--target needs a calendar identifier") }
        targetID = v
    default:
        fail("unknown argument \(arg)\nusage: gonogo [--target <calendarIdentifier>]")
    }
}

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

// Create: attendee-less event tomorrow at 03:00 for 15 minutes, carrying the marker.
let cal = Calendar.current
let start = cal.date(bySettingHour: 3, minute: 0, second: 0, of: cal.date(byAdding: .day, value: 1, to: Date())!)!
let event = EKEvent(eventStore: store)
event.calendar = calendar
event.title = "Blocked (gonogo test)"
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

// Delete only marked events from the target calendar.
var deleted = 0
for e in found where e.notes == marker && e.calendar.calendarIdentifier == calendar.calendarIdentifier {
    do {
        try store.remove(e, span: .thisEvent, commit: false)
        deleted += 1
    } catch {
        fail("remove failed: \(error) — test event may remain; delete 'Blocked (gonogo test)' manually")
    }
}
do {
    try store.commit()
} catch {
    fail("commit failed: \(error)")
}
print("Deleted \(deleted) event(s). GO: create/save/fetch/delete all succeeded.")

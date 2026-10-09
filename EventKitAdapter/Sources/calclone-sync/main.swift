import Core
import EventKitAdapter
import Foundation

// Milestone 3 dry-run CLI. Prints the operations one sync would perform.
// Writes nothing unless --apply is given.

let usage = """
usage: calclone-sync --source <calendarId> [--source <id> ...] --target <calendarId> [--lookahead <days>] [--apply]
       calclone-sync --list
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n\(usage)\n".utf8))
    exit(1)
}

var config = Config(timeZoneIdentifier: TimeZone.current.identifier)
var apply = false
var list = false
var args = CommandLine.arguments.dropFirst()
while let arg = args.popFirst() {
    switch arg {
    case "--source":
        guard let v = args.popFirst() else { fail("--source needs a calendar identifier") }
        config.sourceCalendarIDs.append(v)
    case "--target":
        guard let v = args.popFirst() else { fail("--target needs a calendar identifier") }
        config.targetCalendarID = v
    case "--lookahead":
        guard let v = args.popFirst(), let days = Int(v), days > 0 else { fail("--lookahead needs a positive number of days") }
        config.lookaheadDays = days
    case "--apply": apply = true
    case "--list": list = true
    default: fail("unknown argument \(arg)")
    }
}

let store = EKCalendarStore()
do {
    try await store.requestAccess()
} catch {
    fail("\(error). Enable in System Settings > Privacy & Security > Calendars.")
}

if list {
    for cal in try store.calendars().sorted(by: { ($0.sourceTitle, $0.title) < ($1.sourceTitle, $1.title) }) {
        print("\(cal.title)  [source: \(cal.sourceTitle), writable: \(cal.allowsModifications)]\n  id: \(cal.id)")
    }
    exit(0)
}

let formatter = DateFormatter()
formatter.timeZone = config.timeZone ?? .current
formatter.dateFormat = "EEE yyyy-MM-dd HH:mm"

func show(_ interval: Interval) -> String {
    "\(formatter.string(from: interval.start)) - \(formatter.string(from: interval.end))"
}

do {
    let now = Date()
    let plan = apply
        ? try Syncer.run(store: store, config: config, now: now)
        : try Syncer.plan(store: store, config: config, now: now)

    print("Window: \(show(plan.window)) (\(config.timeZoneIdentifier))")
    print("Source events: \(plan.sourceEventCount), desired blocks: \(plan.desired.count), existing managed: \(plan.existing.count)")
    let existingByID = Dictionary(uniqueKeysWithValues: plan.existing.map { ($0.id, $0.interval) })
    for op in plan.operations {
        switch op {
        case .create(let i): print("  create  \(show(i))")
        case .update(let id, let i): print("  update  \(show(existingByID[id]!)) -> \(show(i))")
        case .delete(let id): print("  delete  \(show(existingByID[id]!))")
        }
    }
    if plan.operations.isEmpty { print("  no changes") }
    print(apply ? "Applied \(plan.operations.count) operation(s)." : "Dry run: nothing written. Re-run with --apply to write.")
} catch {
    fail("\(error)")
}

# Calendar Blocker — Spec

A macOS menu bar app that mirrors personal calendar events onto a work calendar as opaque "Blocked" events during configurable working hours, so colleagues see accurate availability without seeing personal details.

## 1. Goals

- Read events from one or more **source** (personal) calendars.
- For each event overlapping configured working hours, create a **"Blocked"** event on a **target** (work) calendar.
- Support configurable padding before and after each event.
- Keep the target calendar in sync: edits, moves, and deletions on the personal side are reflected automatically.
- Run unattended in the background with minimal resource use.
- Leak no personal information to the work calendar.

## 2. Non-goals (v1)

- No direct Google or Microsoft Graph API integration. Everything goes through EventKit.
- No two-way sync. The work calendar is never read to create personal events.
- No iOS or Windows support.
- No Mac App Store distribution. Local or notarized direct distribution only.
- No mirroring of attendees, locations, descriptions, or meeting links.

## 3. Platform and stack

- **macOS 14+** (uses `requestFullAccessToEvents`).
- **Swift 5.9+**, SwiftUI for UI, `MenuBarExtra` for the menu bar presence.
- **EventKit** for all calendar access. Calendar.app must already have both calendars configured and writable.
- **SMAppService** (`.mainApp`) for launch-at-login.
- Persistence: `UserDefaults` or a JSON file in Application Support for config. No database is needed for v1 (see reconciliation below).
- App bundle with `LSUIElement = YES` (no Dock icon).
- Info.plist: `NSCalendarsFullAccessUsageDescription`.
- Entitlements: `com.apple.security.personal-information.calendars`. Sandboxing is optional for a locally run app, but if enabled, the entitlement is required.

## 4. Architecture

Separate pure logic from system I/O so the core is unit-testable without a real calendar.

```
CalendarBlocker/
├── Core/                       # Swift package, no EventKit imports
│   ├── Config.swift            # Codable settings model
│   ├── Interval.swift          # Date interval type + ops (clip, pad, merge)
│   ├── BlockPlanner.swift      # source events + config -> desired intervals
│   └── Reconciler.swift        # desired vs existing -> create/update/delete ops
├── EventKitAdapter/
│   ├── CalendarStore.swift     # protocol: fetch events, list calendars, apply ops
│   └── EKCalendarStore.swift   # real implementation over EKEventStore
├── Sync/
│   └── SyncEngine.swift        # triggers, debounce, orchestration
└── App/
    ├── CalendarBlockerApp.swift  # MenuBarExtra + Settings scene
    ├── SettingsView.swift
    └── LoginItem.swift
```

`BlockPlanner` and `Reconciler` must be pure functions over plain value types. `EKCalendarStore` is the only code that touches EventKit, and it sits behind a protocol so tests can use an in-memory fake.

## 5. Configuration

| Setting | Type | Default |
|---|---|---|
| Source calendars | multi-select of EKCalendars | none (must choose) |
| Target calendar | single EKCalendar, must allow modifications | none (must choose) |
| Working days | set of weekdays | Mon-Fri |
| Working hours | start/end time, optionally per-day overrides | 08:00-17:00 |
| Time zone | system time zone | system |
| Padding before | minutes | 0 |
| Padding after | minutes | 0 |
| Padding order | `padThenClip` or `clipThenPad` | `padThenClip` |
| Merge overlapping/adjacent blocks | bool | true |
| Merge gap threshold | minutes (blocks closer than this merge) | 0 |
| Skip all-day events | bool | true |
| Skip declined events | bool | true |
| Skip events marked Free | bool | true |
| Skip tentative events | bool | false |
| Lookahead window | days | 30 |
| Block title | string | "Blocked" |
| Block availability | busy / tentative / OOF where supported | busy |
| Safety-net poll interval | minutes | 15 |
| Launch at login | bool | true |

## 6. Sync algorithm

Each sync run:

1. **Compute window**: from start of today to today + lookahead days.
2. **Fetch source events** via `predicateForEvents(withStart:end:calendars:)`. This returns expanded occurrences of recurring events, so treat each occurrence as an independent event.
3. **Filter** according to the skip rules above.
4. **Pad and clip** each event per day:
   - `padThenClip`: expand by padding, then intersect with each working-hours interval for each working day it touches.
   - `clipThenPad`: intersect with working hours first, then expand by padding, then re-clip so blocks never exceed working hours.
   - Events spanning midnight must be split per day.
   - Discard empty intervals.
5. **Merge** (if enabled): sort and merge intervals that overlap or are within the gap threshold.
6. **Fetch existing managed events** on the target calendar in the same window. A managed event is one carrying the marker (see below).
7. **Reconcile by interval**:
   - Desired interval exactly matching an existing managed event: no-op.
   - Leftover desired intervals paired with leftover existing events: update start/end of the existing event where possible, to avoid churn and spurious notifications.
   - Remaining desired intervals: create.
   - Remaining existing managed events: delete.
8. **Apply** operations, committing in one batch (`commit: false` per op, then `store.commit()` once).

Reconciling by interval rather than by a source-event-ID mapping is deliberate. Once blocks are padded, clipped, and merged, there is no clean one-to-one mapping from source events to target events, and interval diffing is self-healing: no database to corrupt or drift.

### Managed event marker

Every created event gets an opaque marker so the app can find its own events even if config changes or local state is lost, and never touches the user's real work events:

- Title: the configured block title.
- Notes: a single line such as `cal-blocker:v1` (no personal data).
- Only events on the target calendar carrying this marker are ever updated or deleted. This is a hard safety rule.

### Created event properties

- Title: configured block title ("Blocked")
- Start/end: computed interval
- No attendees, no location, no URL, no personal notes
- No alarms (remove any default alarms)
- Availability: as configured
- Time zone: floating or system, consistent with the target calendar's behavior

## 7. Triggers

- **`EKEventStoreChangedNotification`**: primary trigger. Debounce (~5s, trailing) so bursts of changes from a sync coalesce into one run. It does not say what changed, so every trigger runs the full window sync.
- **Safety-net timer**: every N minutes (default 15), because the notification only fires while the process is alive and some changes can be missed.
- **On launch** and **on wake from sleep** (`NSWorkspace.didWakeNotification`).
- **On config change** and via a manual **Sync Now** menu item.
- **Feedback-loop guard**: the app's own writes trigger the change notification. The sync is idempotent, so the resulting run should compute zero operations. Serialize runs (no concurrent syncs) and coalesce triggers that arrive mid-run into one follow-up run.

## 8. UI

**Menu bar item** (SF Symbol, e.g. `calendar.badge.clock`):
- Status line: "Last synced 2 min ago · 14 blocks"
- Sync Now
- Pause / Resume
- Settings...
- Quit

**Settings window** (SwiftUI `Settings` scene):
- Calendars: source multi-select, target picker (only writable calendars; warn if the target is also in the source list, as this would cause a loop)
- Schedule: working days, hours, per-day overrides
- Padding: before/after minutes, padding order
- Filters: the skip toggles
- Advanced: lookahead, poll interval, merge options, block title, availability
- General: launch at login
- A read-only **Preview** of the next 7 days of computed blocks is a nice-to-have and very useful for debugging config.

**Error states** surfaced in the menu: permission denied, target calendar missing or read-only, last sync failed (with a short reason).

## 9. Permissions and first run

- On first launch, call `requestFullAccessToEvents`. If denied, show a state explaining how to enable it in System Settings > Privacy & Security > Calendars.
- Handle `EKAuthorizationStatus` changes at runtime.
- Re-resolve calendars by `calendarIdentifier` on each run. If a configured calendar disappears, pause and notify rather than guessing.

## 10. Edge cases to handle explicitly

- Recurring events with exceptions or deletions (handled via expanded occurrences).
- Events that span midnight or multiple days.
- Events entirely outside working hours: no block.
- Zero-length events: skip.
- Padding that causes adjacent blocks to overlap: merge handles this.
- DST transitions: do all date math with `Calendar` in the configured time zone, never raw seconds.
- Source and target on the same account.
- Target calendar read-only or deleted.
- Large number of events: the window is bounded, so this is fine, but avoid per-event `commit`.
- User manually deletes or edits a managed block on the work calendar: the next sync recreates or corrects it. Document this as expected behavior.
- Sync interrupted mid-run: the next run converges because reconciliation is idempotent.

## 11. Testing

- **Unit tests** (the bulk): `BlockPlanner` and `Reconciler` with table-driven cases covering padding order, midnight spans, DST days, merge gaps, all filters, and idempotency (running twice yields zero operations).
- **Adapter tests**: a fake `CalendarStore` implementing the protocol, used to test `SyncEngine` including debounce and serialization.
- **Manual test checklist** against two real test calendars: create/move/delete a personal event, recurring event with an exception, all-day event, declined event, and a sync after an app restart.

## 12. Milestones

1. **Go/no-go check**: confirm the work calendar appears in Calendar.app and is writable. Write a tiny CLI or script that creates and deletes one event on it via EventKit. Stop here if this fails.
2. **Core logic**: `Interval`, `BlockPlanner`, `Reconciler`, with full unit tests. No UI, no EventKit.
3. **EventKit adapter**: `EKCalendarStore`, permission flow, a debug CLI that runs one sync and prints the planned operations in dry-run mode.
4. **Sync engine**: triggers, debounce, serialization, timer, wake handling.
5. **Menu bar app + settings UI**, launch at login.
6. **Polish**: error states, preview, notarization/signing for local distribution.

## 13. Acceptance criteria (v1)

- Creating a personal event inside working hours produces a "Blocked" event on the work calendar within ~1 minute (or sooner when the change notification fires).
- Moving or deleting the personal event updates or removes the block.
- Padding and clipping match config for events straddling the start or end of the working day.
- No work calendar event lacking the marker is ever modified or deleted.
- No attendees, so no invitations are sent; no personal details appear on any created event.
- Running a sync twice in a row performs zero writes the second time.
- The app survives sleep/wake and relaunch without duplicating blocks.

## 14. Open questions

- Which account type is the work calendar (Exchange/M365 or Google), and does it allow event creation from Calendar.app under MDM? (Resolved by milestone 1.)
- Should the title be fixed, or should it support per-rule titles (e.g. "Busy" vs "Blocked")?
- Should blocks be created as "busy" or "out of office"? Out of office has different semantics in some Exchange setups, such as auto-declining meeting requests.
- Does the work calendar send any notification to others when an attendee-less event is created or changed? Expected no, but verify.
- Language choice: Swift is the default here for the least friction with EventKit and SwiftUI. If a different language is preferred, the `Core` package is the only portable part; the EventKit adapter and UI would be rewritten.

## 15. Notes for Claude Code

- Start with milestone 1 and report results before building further.
- Keep `Core` free of EventKit and AppKit imports so it can be tested with `swift test` alone.
- Prefer small, reviewable commits per milestone.
- Ask before adding third-party dependencies; none should be needed.
- When any requirement here is ambiguous, pick the safer behavior (never delete unmarked events, never write to the source calendars) and flag it.

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project status

Milestones 1 (go/no-go EventKit CLI in `Tools/GoNoGo`) and 2 (`Core/` package) are done. `SPEC.md` is the source of truth for requirements, architecture, config defaults, the sync algorithm, edge cases, and milestones. Read it before implementing anything. Next is milestone 3 (EventKit adapter and dry-run CLI).

## Commands

- Core tests: `cd Core && swift test` (XCTest, no dependencies).

## What it is

A macOS 14+ menu bar app (Swift 5.9+, SwiftUI `MenuBarExtra`, EventKit, `LSUIElement`) that mirrors personal calendar events onto a work calendar as opaque "Blocked" events during working hours. All calendar access goes through EventKit (no Google/Graph APIs). It's one-way: the work calendar is never read to create personal events.

## Architecture (planned)

- `Core/` is a Swift package with **no EventKit or AppKit imports**. It holds `Config`, `Interval`, `BlockPlanner` and `Reconciler`. Planner and reconciler are pure functions over plain value types, testable with `swift test` alone.
- `EventKitAdapter/` holds the `CalendarStore` protocol and `EKCalendarStore`. It is the **only** code that touches EventKit, so tests can use an in-memory fake.
- `Sync/SyncEngine` handles triggers (`EKEventStoreChangedNotification` debounced ~5s trailing, safety-net timer, launch, wake, config change, Sync Now). Runs are serialized, and triggers arriving mid-run coalesce into one follow-up.
- `App/` holds the SwiftUI app, settings and login item (`SMAppService.mainApp`).

## Key design decisions

- **Reconcile by interval, not by source-event ID.** After pad/clip/merge there is no 1:1 mapping from source to target events, so each sync diffs desired intervals against existing managed events (no-op / update / create / delete). There is no database. Sync must be idempotent: a second run yields zero writes.
- **Managed-event marker.** Created events carry the notes line `cal-blocker:v1`. Only target-calendar events with this marker may ever be updated or deleted. This is a hard safety rule.
- Created events have no attendees, location, URL, alarms or personal notes.
- Batch writes with `commit: false` per op and a single `store.commit()`.
- Do date math with `Calendar` in the configured time zone, never raw seconds (DST). Split events spanning midnight per day.
- Re-resolve calendars by `calendarIdentifier` each run. If one disappears, pause and notify rather than guess.

## Working rules from the spec

- Start with milestone 1 (go/no-go: a tiny CLI that creates and deletes one event on the work calendar via EventKit) and report results before building further.
- Ambiguity: choose the safer behavior (never delete unmarked events, never write to source calendars) and flag it.
- Ask before adding third-party dependencies; none should be needed.
- Prefer small, reviewable commits per milestone.

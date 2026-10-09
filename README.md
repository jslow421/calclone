# calclone

## Status

- Milestone 1 (go/no-go): passed. On a work calendar on an Exchange source, EventKit create, re-fetch (0 attendees, marker round-trips) and delete all worked. Still to check by hand: the event showed up in the work-side web/Outlook view, and no notification reached others.
- Milestone 2 (core logic): `Core/` Swift package with `Interval`, `Config`, `BlockPlanner`, `Reconciler`. Run `cd Core && swift test`.

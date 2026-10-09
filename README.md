# calclone

## Status

- Milestone 1 (go/no-go): passed. On the "Work" calendar (source: Caylent, id `B3C79A36-E583-4721-BB0E-FE9B289780D5`), EventKit create, re-fetch (0 attendees, marker round-trips) and delete all worked. Still to check by hand: the event showed up in the work-side web/Outlook view, and no notification reached others.
- Milestone 2 (core logic): `Core/` Swift package with `Interval`, `Config`, `BlockPlanner`, `Reconciler`. Run `cd Core && swift test`.

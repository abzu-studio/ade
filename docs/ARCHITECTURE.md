# Architecture

This document describes `Sources/Ade` and `Sources/AdeCore` (Swift Package 1.0.1). The preserved Xcode 0.3.2 implementation is documented separately in [ARCHITECTURE-XCODE.md](ARCHITECTURE-XCODE.md). Its storage format and rules are not interchangeable with this package.


Adê is a native macOS app. SwiftUI draws the window. `AdeCore` holds every business rule. The screens dispatch actions and render the result. The core does not import SwiftUI or AppKit.

```
Sources/AdeCore     rules, reduce, merge, document planner
Sources/Ade         Mac shell, menus, file panels, PDF drawing
Tests/AdeCoreTests  the rule suite
```

The Mac target is built only on macOS. `swift test` on Linux runs `AdeCore` and does not compile the app.

## Actions

`dispatch(database, action, context)` in `Sources/AdeCore/Reduce.swift` is the only writer. `context` supplies the clock, the actor id, and new ids. The function returns a `CoreResult`. Error codes are translated in the UI with `error.${code}`.

A successful space change calls `commit`, which clones the space into a revision. Snapshots include asset bytes. `replaceSpace` swaps one space's records. Spaces are matched on `id`. Every other collection is matched on `spaceId`.

## Attendance and volunteering

`computeAttendance` and `suggestVolunteers` are pure reads. The event screen and the participation screen both call `computeAttendance`. Document bindings call `attendanceByPerson`, so a generated PDF uses the same counts.

The percentage is `present / (present + absent)`. A zero denominator is an em dash, not 0%. Excused and pending do not count. Volunteer scores are a list of factors (`code`, `count`, `points`). The screen prints those factors. `suggestVolunteers` never writes a selection.

## Documents

`planDocument` returns pages in top-left coordinates. The Mac renderer converts them to PDF bottom-left coordinates, draws Helvetica, and substitutes `?` for characters Helvetica cannot draw. Images are PNG or JPEG. A background is a PDF page.

## Persistence

The database is one JSON file, `ade-db-v1`, in Application Support under `Adê/database.json`. If that file fails validation, the app reports a storage error and starts empty without overwriting the bad file until a later successful action, or until you choose Start empty.

Export writes pretty JSON through a save panel. Import reads a file and dispatches `importBackup` or `importSync`. A backup asks before it replaces this Mac.

## Collaboration

`toSyncBundle` copies one space. `mergeSyncBundle` compares canonical JSON with every `updatedAt` removed. Conflicts stay on the database until a person chooses keep local, use the other version, or keep both.

## Interface

The shell is a sidebar and a detail column. Routes are Overview, People, Groups, Periods, Components, Events, Participation, Documents, History, Conflicts, Data, and Rules. Attendance and volunteers are sections of an event, not separate routes.

English strings in `Sources/Ade/Resources/en.json` are the catalog. Spanish is the same set of keys. The default locale is English. The actor name defaults to "Local user".

Undo and redo are in the Edit menu and in the space header. When a text field can undo, the menu uses that field's undo manager. Otherwise it walks the space history. The palette stays on the Día clay colors in both appearances: clay ink `#B8441A`, umber `#4A2A18`, tint `#E5C9B0`, cream `#FAF6EE`, paper `#EDE6D6`.

## Tests

`Tests/AdeCoreTests/RulesTests.swift` covers the attendance formula, group dates, event duplication, history, volunteer scores, capacity, sync conflicts, tombstones, and the document planner.

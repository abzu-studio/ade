# Architecture

Adê is a Next.js 15 App Router application. The shared TypeScript core holds every business rule. React screens dispatch actions and render the result. Nothing in the core imports React, the DOM, or pdf-lib.

```
src/core        rules, reduce, merge, document planner
src/persistence IndexedDB repository and file helpers
src/lib/pdf     draw a PlannedPage[] with pdf-lib
src/state       load, dispatch, save
src/i18n        en (source of MessageKey) and es
src/app         screens
src/components/ui   default shadcn/ui
```

## Actions

`dispatch(database, action, context)` in `src/core/reduce.ts` is the only writer. `context` supplies the clock, the actor id, and new ids. The function returns a `Result`. Error codes are translated in the UI with `error.${code}`.

A successful space change calls `commit`, which clones the space into a revision. Snapshots include asset bytes. `replaceSpace` swaps one space's records. Spaces are matched on `id`. Every other collection is matched on `spaceId`.

## Attendance and volunteering

`computeAttendance` and `suggestVolunteers` are pure reads. The attendance screen and the participation screen both call `computeAttendance`. Document bindings call `attendanceByPerson`, so a generated PDF uses the same counts.

Volunteer scores are a list of factors (`code`, `count`, `points`). The screen prints those factors. `suggestVolunteers` never writes a selection.

## Documents

`planDocument` returns pages in top-left coordinates. The renderer converts them to PDF bottom-left coordinates, embeds Helvetica, and substitutes `?` for characters Helvetica cannot draw. Images are PNG or JPEG. A background is an embedded PDF page.

## Persistence

IndexedDB database `ade`, object store `kv`, key `database`. The value is the whole `Database` (`ade-db-v1`). Saves are queued. If the stored value fails validation, the app reports a storage error and starts empty without overwriting the bad value until the user resets it.

Export writes JSON in the browser. Import reads a file and dispatches `importBackup` or `importSync`.

## Collaboration

`toSyncBundle` copies one space. `mergeSyncBundle` compares canonical JSON with every `updatedAt` removed. Conflicts stay on the database until a person chooses keep local, use the other version, or keep both.

## Interface

Screens are client components. They use the default shadcn/ui theme (`base-nova`, neutral). There is no separate brand color or type system.

English strings in `src/i18n/en.ts` define `MessageKey`. Spanish is a complete `Record<MessageKey, string>`. The default locale is English. The actor name defaults to "Local user".

The shell shows undo, redo, and the language switch on every space screen. A Mac check runs after mount so the notice does not cause a hydration mismatch. The notice is not a gate.

## Tests

`src/core/rules.test.ts` covers the attendance formula, group dates, event duplication, history, volunteer scores, capacity, sync conflicts, tombstones, and the document planner. `src/lib/pdf/render.test.ts` builds a multi-page PDF with text, an image, columns, and a background page.

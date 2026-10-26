# Adê rules

This document describes `Sources/Ade` and `Sources/AdeCore` (Swift Package 1.0.1). The preserved Xcode 0.3.2 implementation is documented separately in [RULES-XCODE.md](RULES-XCODE.md). Its storage format and rules are not interchangeable with this package.


The code in `Sources/AdeCore` is the source of these rules. Screens display the same constants.

Dates are civil dates `YYYY-MM-DD`. Comparisons are lexicographic and inclusive. An open membership end is `null` and means the membership is still running. Two ranges overlap when they share a day.

## Spaces

A space owns every other record. People, groups, periods, components, categories, events, attendance, volunteering, templates, assets, conflicts, and revisions all carry that space id.

## People and groups

A person is `active` or `inactive`. Inactive people stay on past events and still count in attendance for those events. Volunteer suggestions skip inactive people.

A group membership has a start date and an optional end date. End date is inclusive. Memberships for the same person in the same group cannot overlap. `isMemberOnDate` is how Adê answers who belonged on a given day.

## Periods

A period is an inclusive date window. It filters which events are read for participation. It does not add another exclusion reason inside the percentage.

## Components and categories

An event has one component. A category is optional and must belong to that component.

## Events

Statuses are `draft`, `scheduled`, `completed`, and `cancelled`.

Allowed changes:

- draft → scheduled, cancelled
- scheduled → draft, completed, cancelled
- completed → scheduled, cancelled
- cancelled → scheduled

Duplicate copies the title (plus the suffix from the screen), date, description, component, category, capacities, the counts-for-attendance flag, and the participant list. The copy is a draft with a new id and `duplicatedFromId`. Attendance and volunteering are not copied.

A cancelled event keeps its participant list (`EVENT_LOCKED`).

Participant capacity and volunteer capacity are a whole number of 0 or more, or empty for no limit. The list cannot grow past participant capacity. Lowering a capacity below the current count fails.

Delete an event only while it is a draft and has no attendance or volunteering. Delete a person, group, component, or category only when nothing still references it (`IN_USE`).

Attendance marks are allowed on scheduled and completed events. Volunteer changes are blocked on cancelled events.

## Attendance

```
percentage = present / (present + absent)
```

If the denominator is 0, the percentage is empty, not 0.

Counted:

- `present`
- `absent`

Excluded:

- `pending`
- `excused`
- no mark yet (this is not an absence)
- cancelled events
- events with `countsForAttendance` set to false
- people who are not on that event's participant list

Adê does not create an automatic absence for someone who is not on the list. A stray attendance row for a non-participant is ignored.

With a group filter, a person counts on an event only when their membership covers that event's date. Otherwise the line is `not-member-on-date` and is excluded.

Who appears in a result:

- no group: every person in the space
- a group and a period: people whose membership overlaps that period
- a group and an event, without a period: people whose membership covers that event date
- a group with neither a period nor an event: people with any membership in that group

The combined percentage is `sum(present) / sum(present + absent)`. It is not the average of each person's percentage.

Each attendance change appends history: previous state, next state, previous note, next note, time, and actor.

## Volunteering

States move only along these edges. The same state can be saved again to update a note.

- no record → interested, selected
- interested → selected, declined
- selected → completed, declined, absent, interested
- completed → selected
- declined → interested
- absent → selected

`selected` and `completed` consume capacity. `interested`, `declined`, and `absent` do not. A transition that newly consumes a place fails when it would pass `volunteerCapacity`.

Suggestions do not change data. Final selection is always a manual action. Only active people are ranked. Earlier events are other events in the space whose date is strictly before the target event.

Weights in `VOLUNTEER_WEIGHTS`:

| Signal | Points each |
| --- | --- |
| completed | 10 |
| completed within 180 days (`recentDays`) | 5 |
| completed in the same component | 2 |
| earlier selected | 3 |
| earlier interested | 1 |
| interested in this event | 8 |
| earlier declined | -2 |
| earlier volunteer absent | -4 |
| earlier attendance present | 1, capped at 10 presents |

Recent days are measured with `daysBetween` and must be greater than 0 and at most 180. Presents on cancelled events, events that do not count, or events where the person was not a participant are ignored.

A person with no signals scores 0 and is labeled no earlier participation. Sort is score descending, then completed count descending, then name, then id. A person is eligible to select when they have no volunteer record or they are currently interested.

## Documents

A template has a page size (`letter` 612×792 or `a4` 595.28×841.89), an optional background PDF, and elements:

- text, with a literal string or a binding
- an image asset (PNG or JPEG)
- columns bound to a list

Column text flows by line height `fontSize * 1.35` and wraps by truncating at about `fontSize * 0.5` points per character. Static text and images repeat on every page. The background page index is clamped to the PDF. The planner in `Sources/AdeCore/Documents.swift` resolves live Adê data, including the same participation figures as the participation screen. `Sources/Ade/PDF.swift` draws the plan with Core Graphics and Helvetica.

## History

Each space keeps `revisionIds` and a `cursor`. A change stores a snapshot of the space after the change and drops any redo tail. Undo moves the cursor back and restores that snapshot. Redo moves it forward. Restoring an older revision moves the cursor and keeps later revisions until a new change truncates them. Undo of the first revision removes the space's records but keeps the history so redo can return.

Locale and the local actor name are not space revisions.

## Collaboration

A backup (`ade-backup-v1`) replaces the whole local database after it is checked.

A space export (`ade-sync-v1`) is a snapshot plus tombstones, not the undo stack.

- missing space: adopt it
- same records, ignoring `updatedAt`: keep the local space
- record only on the other side: insert it
- both sides changed the same record: store a conflict with both payloads and keep the local record active
- attendance and volunteering use the key `eventId:personId`, so a second active mark is not inserted
- an overlapping membership is a conflict and is not inserted
- a tombstone for an unchanged record deletes it and keeps the payload on the tombstone
- a tombstone for a record that changed locally is a conflict; the local record stays

Resolving a conflict:

- keep local: archive the conflict
- use the other version: replace or delete the local record
- keep both: add a separate copy with a `(conflict)` suffix when that cannot create two active marks; attendance, volunteering, the space itself, and an overlapping membership are not copied into the active set

Importing the same pending conflict again does not add a second conflict. Importing an identical snapshot does not add a revision.

# Adê

Adê is a native Mac app for one operator. A space holds people, groups, periods, components, events, attendance, volunteering, and documents. The attendance percentage is `present / (present + absent)`. Pending, excused, and unmarked people are not absences.

The app is local-first. There are no accounts. Collaboration is a JSON file: export a backup or one space, and import it on another Mac. When both sides changed the same record, Adê keeps both versions until you choose.

## Requirements

macOS 14 or later.

## Build

```bash
swift test
bash scripts/package-macos-app.sh
open "dist/Adê.app"
```

`swift test` runs the rule suite in `Tests/AdeCoreTests`. The package script builds a release `.app`, generates the dock icon, and writes `dist/Ade-1.0.1-macOS.zip`.

## Using it

Open Adê from the Dock. Create a space, or load the demo space. Everything else belongs to the open space: Overview, People, Groups, Periods, Components, Events, Participation, Documents, History, Conflicts, Data, and Rules.

Attendance and volunteers stay on the event. Participation reads the same counts across a period. Undo is ⌘Z. On an event that is scheduled or completed, P, A, E, and W mark present, absent, excused, and pending when a text field is not focused.

The interface is English and Spanish. Switch language from the space header or the Language menu. Dates in history are shown in Puerto Rico time.

Export and import live in the Data section and in the File menu. A backup replaces the database on this Mac after you confirm. A space file merges. Identical records stay put. Conflicts remain until you keep the local version, use the other version, or keep both.

## Rules

`docs/RULES.md` is the behavior contract. `Sources/AdeCore` is the code those rules run. The screens do not calculate a second percentage.

## Fonts

The interface uses Barlow Condensed (Jeremy Tribby), IBM Plex Mono (IBM), and Inter (Rasmus Andersson), under the SIL Open Font License 1.1. See `Sources/Ade/Resources/Fonts/OFL.txt`.

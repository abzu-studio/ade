# Adê

Adê is a native Mac app for one operator. A space holds people, groups, periods, components, events, attendance, volunteering, and documents. The attendance percentage is `present / (present + absent)`. Pending, excused, and unmarked people are not absences.

The app is local-first. There are no accounts. Collaboration is a JSON file: export a backup or one space, and import it on another Mac. When both sides changed the same record, Adê keeps both versions until you choose.

## Download — SwiftUI/Xcode edition

[Adê 0.4.5 for macOS](https://github.com/abzu-studio/ade/releases/tag/v0.4.5) is the DMG edition from `macos/`, with universal Apple Silicon and Intel binaries. The release includes the corresponding source archive and SHA-256 checksums. It starts empty, without demonstration records.

This preview is ad-hoc signed and **not notarized by Apple**. macOS may block its first launch; see the release installation notes. Existing Xcode 0.4.0 data stays in the same local container.

## Requirements

macOS 14 or later.

## Build

This branch contains two native targets. The Swift Package commands below build 1.0.1 from `Sources/`. The Xcode 0.4.5 app lives in `macos/Ade.xcodeproj`; its checks use `scripts/test-native.sh` and its packaging is documented in [Distribution](docs/DISTRIBUTION.md). They have separate bundle identifiers and storage formats; there is no automatic data migration between them.

```bash
swift test
bash scripts/package-macos-app.sh
open "dist/Adê.app"
```

`swift test` runs the rule suite in `Tests/AdeCoreTests`. The package script builds a release `.app`, generates the dock icon, and writes `dist/Ade-1.0.1-macOS.zip`.

## Using the Swift Package edition

Open Adê from the Dock. Create a space. Everything else belongs to the open space: Overview, People, Groups, Periods, Components, Events, Participation, Documents, History, Conflicts, Data, and Rules.

Attendance and volunteers stay on the event. Participation reads the same counts across a period. Undo is ⌘Z. On an event that is scheduled or completed, P, A, E, and W mark present, absent, excused, and pending when a text field is not focused.

The interface is English and Spanish. Switch language from the space header or the Language menu. Dates in history are shown in Puerto Rico time.

Export and import live in the Data section and in the File menu. A backup replaces the database on this Mac after you confirm. A space file merges. Identical records stay put. Conflicts remain until you keep the local version, use the other version, or keep both.

## Rules

`docs/RULES.md` is the behavior contract. `Sources/AdeCore` is the code those rules run. The screens do not calculate a second percentage.

## Fonts

The interface uses Barlow Condensed (Jeremy Tribby), IBM Plex Mono (IBM), and Inter (Rasmus Andersson), under the SIL Open Font License 1.1. See `Sources/Ade/Resources/Fonts/OFL.txt`.

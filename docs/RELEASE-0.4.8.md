# Adê 0.4.8 · macOS

Native SwiftUI/Xcode build 22. Requires macOS 14 or later, on Apple Silicon and Intel. Attendance is still `present / (present + absent)`. Volunteer weights in this app are still prior completed volunteering × 3 plus prior attendance × 1. Conflict rules, Día clay, the app icon, the menu glyph, and the English and Spanish copy are unchanged. No new roles.

## What changed on screen

0.4.7 kept the workspace inside an 18-point night mat, with an inset hairline, a card shadow, and the title-bar strip. 0.4.8 removes that frame. The sidebar and the page sit flush with the window edge. The title bar is hidden. The window background is the paper color of the current day or night theme, including the indigo night paper.

Attendance marks stay 92×34 points, with P, A, E, and X in the help tag. Search, the calendar, the opening ident, the formula, and the volunteer sentence are the same as 0.4.7.

## Download

- `Ade-0.4.8-22-macos.zip`: universal app (Apple Silicon and Intel).

## Install and data

Unzip the archive and move Adê to Applications. The download has no personal records, credentials, demonstration spaces, or test tools. New installs start empty. The bundle identifier remains `com.ade.mac` and the Xcode 0.4.x data format is unchanged: replacing the app keeps existing spaces. Export a copy from Data before updating if you want a backup.

**Ad hoc signature. No Developer ID and no Apple notarization.** macOS may block the first launch. If you trust the download, follow [Apple’s instructions for opening an app that was blocked](https://support.apple.com/en-us/102445). You do not need to turn off Gatekeeper.

The Swift Package 1.0.1 edition in this repository is a different build, with a different container and format. It does not migrate its data into this app, and its volunteer weights are the ones in `docs/RULES.md`, not the × 3 / × 1 score in this app.

## Verification

GitHub Actions on the Mac runner builds the universal app, runs the core, persistence, and PDF checks, and checks the bundle. The Mac app was not launched in this environment, so there is no new window screenshot. Notarization and a physical Intel Mac are still outstanding.

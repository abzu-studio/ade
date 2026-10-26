# Adê 0.4.7 · macOS

Native SwiftUI/Xcode build 21. Requires macOS 14 or later, on Apple Silicon and Intel. Attendance is still `present / (present + absent)`. Volunteer weights in this app are still prior completed volunteering × 3 plus prior attendance × 1. Conflict rules, Día clay, the app icon, the menu glyph, and the English and Spanish copy are unchanged. No new roles.

## What got faster

0.4.6 moved the crest blur into a short buffer and dropped the live material. It still rebuilt the ink as a SwiftUI path: about 10,142 squares on a 1244×684 point workspace, plus about 3,076 squares on the attendance block, every frame.

0.4.7 stamps that same Bayer formula into one image. A C build of the kernel on the 1244×684 workspace:

- Grain, full point size: 0.72 ms at -O3, 1.56 ms at -O0. A 960-pixel long edge is 0.65 ms. Over two seconds, 29,125 of 506,880 pixels in the 960×528 buffer change, so the field still moves.
- Accent lattice at 2×: navigation tab 0.028 ms, primary button 0.028 ms, attendance block 0.14 ms (-O3).
- Crest blur in the 420×231 buffer, radius 13, three box passes: 3.57 ms for one blur and 14.3 ms for the four crest blurs (-O3). The 0.4.5 full-window blur this replaced was about 9.8 ms each at 1× (about 39 ms for four) and about 98 ms each on a retina 2× store (about 393 ms for four).

The attendance rail for one event sums that roster instead of walking every person in the space. Volunteer suggestions use one pass over past events, completed volunteering, and attendance, then the same score. Overview, the attendance list, and group names reuse the open revision instead of scanning the space again on each redraw. Date formatting is cached.

Reduce Motion, Reduce Transparency, Increase Contrast, Low Power Mode, Adê’s motion switch, and an inactive window still pause the animation.

## What changed on screen

Attendance marks are 92×34 points, with the keyboard letter in the help tag (P, A, E, X). The selected row is marked with the accent color and a heavier bar. Search is on the roster whenever it is not empty, and a count plus Clear appear while a query is typed. Calendar days are 34 points tall. The opening ident, the formula, and the volunteer sentence on the event are the same.

## Download

- `Ade-0.4.7-21-macos.zip`: universal app (Apple Silicon and Intel).

## Install and data

Unzip the archive and move Adê to Applications. The download has no personal records, credentials, demonstration spaces, or test tools. New installs start empty. The bundle identifier remains `com.ade.mac` and the Xcode 0.4.x data format is unchanged: replacing the app keeps existing spaces. Export a copy from Data before updating if you want a backup.

**Ad hoc signature. No Developer ID and no Apple notarization.** macOS may block the first launch. If you trust the download, follow [Apple’s instructions for opening an app that was blocked](https://support.apple.com/en-us/102445). You do not need to turn off Gatekeeper.

The Swift Package 1.0.1 edition in this repository is a different build, with a different container and format. It does not migrate its data into this app, and its volunteer weights are the ones in `docs/RULES.md`, not the × 3 / × 1 score in this app.

## Verification

Kernel times above are from `gcc -O3` and `gcc -O0` of `macos/Ade/PaperFieldKernels.c` via `scripts/bench-paper-kernels.c` on the Linux build machine. GitHub Actions on the Mac runner builds the universal app, runs the core, persistence, and PDF checks, and checks the bundle. The Mac app was not launched in this environment, so there is no new window screenshot. Notarization and a physical Intel Mac are still outstanding.

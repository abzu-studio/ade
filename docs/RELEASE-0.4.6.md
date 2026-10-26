# Adê 0.4.6 · macOS

Native SwiftUI/Xcode build 20. Requires macOS 14 or later, on Apple Silicon and Intel. Same screens, attendance formula `present / (present + absent)`, volunteer weights, conflict rules, Día clay colors, app icon, menu glyph, and English/Spanish copy as 0.4.5.

## Performance

0.4.5 draws the paper field at 30 frames per second. A profile of those kernels on a 1244×684 point workspace:

- Ordered dither: about 10,000–13,000 squares. Computing them took 0.16 ms. That was not the frame.
- Four full-window blurs (two crest fills and two crest strokes): about 9 ms each at 1×, about 96 ms each on a retina 2× backing store (2488×1368, radius 75). Four blurs are about 36 ms at 1× and about 380 ms at 2×. A frame at 30 fps has 33 ms. A repeat of the same bench stayed in that range (about 8–10 ms and about 100 ms).
- Sidebar, header, and sheets used a live material over that animation, so the backdrop was blurred again whenever the field changed.

0.4.6 keeps the crest paths, the dither lattice, and the moving sheen.

- Crests are drawn into a buffer whose long edge is at most 420 pixels and blurred there, then scaled up. The same geometry at 320×175 took 0.48 ms in the profile, against those full-window blurs.
- Chrome keeps its tint, highlight, border, and moving reflection, and no longer samples the animating field through a live material.
- Reduce Motion, Reduce Transparency, Increase Contrast, Low Power Mode, Adê’s own motion switch, and an inactive window still pause the animation.

## Download

- `Ade-0.4.6-20-macos.zip`: universal app (Apple Silicon and Intel).

## Install and data

Unzip the archive and move Adê to Applications. The download has no personal records, credentials, demonstration spaces, or test tools. New installs start empty. The bundle identifier remains `com.ade.mac` and the Xcode 0.4.x data format is unchanged: replacing the app keeps existing spaces. Export a copy from Data before updating if you want a backup.

**Ad hoc signature. No Developer ID and no Apple notarization.** macOS may block the first launch. If you trust the download, follow [Apple’s instructions for opening an app that was blocked](https://support.apple.com/en-us/102445). You do not need to turn off Gatekeeper.

The Swift Package 1.0.1 edition in this repository is a different build, with a different container and format. It does not migrate its data into this app.

## Verification

The field profile compared the 0.4.5 blur and dither kernels with the short crest buffer. GitHub Actions runs the core, persistence, and PDF checks and verifies the universal bundle, entitlements, signature, and absence of private files. Notarization and a physical Intel Mac are still outstanding.

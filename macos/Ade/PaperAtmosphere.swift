import SwiftUI

/// The clock belongs exclusively to the artwork, never to a form, list, or the data model.
struct PaperArtworkClock<Artwork: View>: View {
  @ViewBuilder var artwork: (Double) -> Artwork
  @Environment(\.isEnabled) private var enabled
  @Environment(\.paperReduceMotion) private var reducedMotion
  @Environment(\.paperAtmosphereVisible) private var atmosphereVisible
  @Environment(\.accessibilityReduceTransparency) private var reducedTransparency
  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.controlActiveState) private var activeState
  @AppStorage("ade-ambient-motion") private var animated = true
  @State private var visible = false
  @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

  private var paused: Bool {
    reducedMotion || !animated || !enabled || !visible || !atmosphereVisible || lowPower
      || scenePhase != .active
      || activeState == .inactive
  }

  var body: some View {
    ZStack {
      if !reducedTransparency && contrast != .increased {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused)) { timeline in
          // All periods divide 120, so reducing the clock magnitude has no visible seam.
          let time =
            reducedMotion || !animated
            ? 0 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 120)
          artwork(time)
        }
      }
    }
    .clipped().allowsHitTesting(false).accessibilityHidden(true)
    .onAppear { visible = true }
    .onDisappear { visible = false }
    .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
      lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    }
  }
}

struct PaperAtmosphere: View {
  var scene: PaperScene = .spaces
  @Environment(\.paperReduceMotion) private var reducedMotion
  var body: some View {
    PaperArtworkClock { time in
      SceneInk(scene: scene, time: time).id(scene).transition(.opacity)
    }.animation(reducedMotion ? nil : .easeInOut(duration: 0.65), value: scene)
  }
}

/// Decoration shares the workspace bounds without reserving a footer or moving content.
/// Foreground text, controls and glass surfaces always draw above the animated field.
struct PaperAmbientLayout: ViewModifier {
  let scene: PaperScene
  func body(content: Content) -> some View {
    content
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background { PaperAtmosphere(scene: scene) }
      .clipped()
  }
}

/// Tinted glass sheets retain the straight editorial edges and do not blur foreground text.
struct PaperGlassSurface: View {
  @Environment(\.paperScene) private var scene
  @Environment(\.paperReduceMotion) private var reducedMotion
  var tint: Color = Enki.paper
  @Environment(\.accessibilityReduceTransparency) private var reducedTransparency
  @Environment(\.colorSchemeContrast) private var contrast
  var body: some View {
    let night = Enki.isNight
    return ZStack {
      if reducedTransparency || contrast == .increased {
        tint
      } else {
        // Opaque tint. A live material resampled the animating field under every
        // sidebar, header and sheet on each frame. The sheen above still moves.
        tint
        LinearGradient(
          colors: [.white.opacity(night ? 0.025 : 0.32), .clear, scene.ink.opacity(0.04)],
          startPoint: .topLeading, endPoint: .bottomTrailing)
        PaperArtworkClock { time in
          PaperSurfaceReflection(time: time, accented: false, night: night)
        }
        Rectangle().strokeBorder(
          LinearGradient(colors: [.white.opacity(night ? 0.22 : 0.8), Enki.rule.opacity(0.4)],
                         startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.7)
      }
    }.animation(reducedMotion ? nil : .easeInOut(duration: 0.65), value: scene)
      .allowsHitTesting(false).accessibilityHidden(true)
  }
}

/// The label is outside this view: animated ink and reflections can never tint its glyphs.
struct PaperAccentSurface: View {
  var tint: Color
  var cornerRadius: CGFloat = 3
  var body: some View {
    let night = Enki.isNight
    return ZStack {
      tint
      PaperArtworkClock { time in
        PaperSurfaceReflection(time: time, accented: true, night: night)
      }
    }.clipShape(RoundedRectangle(cornerRadius: cornerRadius))
      .allowsHitTesting(false).accessibilityHidden(true)
  }
}

/// Native material reflection, plus a fixed print lattice on solid accent surfaces.
/// The clock invalidates only this drawing, not the button, its label, or its action.
private struct PaperSurfaceReflection: View {
  let time: Double
  let accented: Bool
  let night: Bool
  private static let bayer = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

  var body: some View {
    Canvas(opaque: false, rendersAsynchronously: true) { context, size in
      guard size.width > 0, size.height > 0 else { return }
      let phase = time * .pi * 2 / 12
      let travel = 0.5 + 0.36 * sin(phase)
      let bounds = Path(CGRect(origin: .zero, size: size))
      let strength = accented ? 0.19 : (night ? 0.14 : 0.55)
      // Day accents carry white labels: deepen their ink instead of washing it out.
      let reflectionColor: Color = accented && !night ? .black : .white
      let center = CGPoint(x: size.width * travel, y: size.height * (0.35 + 0.15 * cos(phase)))
      // A broad reflected window moves slowly across the material, without hard bands.
      context.fill(bounds, with: .radialGradient(
        Gradient(colors: [reflectionColor.opacity(strength), reflectionColor.opacity(strength * 0.30), .clear]),
        center: center, startRadius: 0, endRadius: max(size.width, size.height) * 0.75))
      context.fill(bounds, with: .linearGradient(
        Gradient(stops: [
          .init(color: reflectionColor.opacity(strength * 0.65), location: 0),
          .init(color: .clear, location: 0.30),
          .init(color: .black.opacity(night ? 0.06 : 0.035), location: 1),
        ]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))

      if accented {
        let spacing = max(2.5, sqrt(size.width * size.height / 5_000))
        var ink = Path()
        for column in 0...Int(size.width / spacing) {
          let x = (Double(column) + 0.5) * spacing
          let wave = 0.5 + 0.28 * sin(x / size.width * .pi * 2 - phase)
          for row in 0...Int(size.height / spacing) {
            let y = (Double(row) + 0.5) * spacing
            let density = min(0.9, max(0.05, wave + 0.22 * (y / size.height - 0.5)))
            let threshold = (Double(Self.bayer[(row & 3) * 4 + (column & 3)]) + 0.5) / 16
            let coverage = min(1.0, max(0.0, (density - threshold) * 5 + 0.5))
            guard coverage > 0.005 else { continue }
            let side = spacing * 0.58 * sqrt(coverage)
            ink.addRect(CGRect(x: x - side / 2, y: y - side / 2, width: side, height: side))
          }
        }
        context.fill(ink, with: .color(reflectionColor.opacity(night ? 0.26 : 0.16)))
        context.stroke(bounds, with: .linearGradient(
          Gradient(colors: [.white.opacity(0.28), .clear, .black.opacity(0.12)]),
          startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)), lineWidth: 1)
      }
    }
  }
}

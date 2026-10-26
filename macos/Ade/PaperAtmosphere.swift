import SwiftUI

/// The clock belongs exclusively to the artwork, never to a form, list, or the data model.
struct PaperAtmosphere: View {
  var scene: PaperScene = .spaces
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
    reducedMotion || !animated || !visible || !atmosphereVisible || lowPower
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
          ZStack {
            SceneInk(scene: scene, time: time)
              .id(scene).transition(.opacity)
          }.animation(reducedMotion ? nil : .easeInOut(duration: 0.65), value: scene)
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

/// Layout owns a separate decorative strip, so no row or control can overlap the water.
/// Height depends on the window, never on animation phase or application data.
struct PaperAmbientLayout: ViewModifier {
  let scene: PaperScene
  func body(content: Content) -> some View {
    GeometryReader { geometry in
      VStack(spacing: 0) {
        content.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
        PaperAtmosphere(scene: scene)
          .frame(height: min(84, max(48, geometry.size.height * 0.10)))
      }
    }
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
    ZStack {
      if reducedTransparency || contrast == .increased {
        tint
      } else {
        Rectangle().fill(.ultraThinMaterial)
        tint.opacity(0.78)
        LinearGradient(
          colors: [.white.opacity(Enki.isNight ? 0.025 : 0.32), .clear, scene.ink.opacity(0.04)],
          startPoint: .topLeading, endPoint: .bottomTrailing)
        Rectangle().strokeBorder(.white.opacity(Enki.isNight ? 0.07 : 0.5), lineWidth: 0.5)
      }
    }.animation(reducedMotion ? nil : .easeInOut(duration: 0.65), value: scene)
      .allowsHitTesting(false).accessibilityHidden(true)
  }
}

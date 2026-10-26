import SwiftUI

/// Product-specific art direction, independent of records and participation calculations.
@MainActor enum PaperScene: String, CaseIterable {
  case threshold, spaces, summary, people, groups, periods, classification, events
  case attendance, volunteers, context, results, documents, history, data, conflicts, rules,
    settings

  var ink: Color {
    Enki.atmosphere
  }
  static var abzu: Color { Enki.accent }
  static var deep: Color { Enki.deep }
  static var sage: Color { Enki.present }
  static var slate: Color { Enki.atmosphere }
  static var ochre: Color { Enki.atmosphere }
  static var gold: Color { Enki.onDark.opacity(0.85) }
  var hasRail: Bool { self == .attendance }
}

private struct PaperSceneKey: EnvironmentKey {
  static let defaultValue: PaperScene = .spaces
}
private struct PaperAtmosphereVisibleKey: EnvironmentKey {
  static let defaultValue = true
}
extension EnvironmentValues {
  var paperAtmosphereVisible: Bool {
    get { self[PaperAtmosphereVisibleKey.self] }
    set { self[PaperAtmosphereVisibleKey.self] = newValue }
  }
  var paperScene: PaperScene {
    get { self[PaperSceneKey.self] }
    set { self[PaperSceneKey.self] = newValue }
  }
}

/// One continuous halftone field. No pictograms or synthetic data marks behind the workspace.
struct SceneInk: View {
  let scene: PaperScene
  let time: Double

  var body: some View {
    Canvas(opaque: false, rendersAsynchronously: true) { context, size in
      guard size.width > 0, size.height > 0 else { return }
      // Coherent waves advect density across a fixed print grid. No per-frame randomness.
      // Periods of 30, 40 and 60 seconds meet exactly at the 120-second clock boundary.
      let phase = time * .pi * 2
      let calm = scene == .documents || scene == .rules || scene == .settings
      let amplitude = calm ? 0.055 : 0.085
      let color = Enki.atmosphere
      let bottom = CGPoint(x: 0, y: size.height)
      context.fill(
        Path(CGRect(origin: .zero, size: size)),
        with: .linearGradient(
          Gradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: color.opacity(Enki.isNight ? 0.035 : 0.025), location: 0.45),
            .init(color: color.opacity(Enki.isNight ? 0.23 : 0.15), location: 1),
          ]), startPoint: .zero, endPoint: bottom))
      var dots = Path()
      let step = 4.0
      for row in 0...Int(size.height / step) {
        let y = Double(row) * step
        let v = y / size.height
        // Smooth fade gives the top of the reserved band no visible edge.
        let fade = v * v * (3 - 2 * v)
        for column in 0...Int(size.width / step) {
          let x = Double(column) * step + (row.isMultiple(of: 2) ? 0 : step / 2)
          let tide = 0.28
            + amplitude * sin(x / 145 - phase / 40)
            + amplitude * 0.6 * sin(x / 310 + phase / 60)
          let depth = max(0, min(1, (v - tide) / 0.72))
          let current = 0.82 + 0.18 * sin(x / 95 + v * 5 - phase / 30)
          let density = depth * depth * (3 - 2 * depth) * fade * current
          let radius = 1.65 * sqrt(density)
          guard radius > 0.12 else { continue }
          dots.addEllipse(in: CGRect(x: x - radius, y: y - radius,
                                     width: radius * 2, height: radius * 2))
        }
      }
      context.fill(dots, with: .linearGradient(
        Gradient(colors: [color.opacity(0.12), color.opacity(Enki.isNight ? 0.72 : 0.62)]),
        startPoint: .zero, endPoint: bottom))
    }
  }
}

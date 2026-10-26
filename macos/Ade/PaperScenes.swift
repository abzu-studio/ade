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

/// A single translucent light field beneath the workspace, with no row masks or inset bands.
/// Coherent currents carry soft reflections and ordered ink grain beneath the controls.
struct SceneInk: View {
  let scene: PaperScene
  let time: Double

  var body: some View {
    let color = Enki.atmosphere
    let night = Enki.isNight
    let resolved = color.resolve(in: EnvironmentValues())
    let red = CGFloat(resolved.red)
    let green = CGFloat(resolved.green)
    let blue = CGFloat(resolved.blue)
    return Canvas(opaque: false, rendersAsynchronously: true) { context, size in
      guard size.width > 0, size.height > 0 else { return }
      let calm = scene == .documents || scene == .rules || scene == .settings
      let energy = calm ? 0.75 : 1.0
      let bounds = Path(CGRect(origin: .zero, size: size))
      let top = CGPoint.zero
      let bottom = CGPoint(x: 0, y: size.height)

      // The tint spans the entire surface. No hard upper boundary or reserved footer.
      context.fill(bounds, with: .linearGradient(
        Gradient(stops: [
          .init(color: .clear, location: 0),
          .init(color: color.opacity(night ? 0.035 : 0.025), location: 0.38),
          .init(color: color.opacity(night ? 0.16 : 0.10), location: 1),
        ]), startPoint: top, endPoint: bottom))

      // Same crest periods as 0.4.5. The soft light is rasterized into a short buffer and
      // blurred there: a profile of the previous four full-window blurs was the frame cost.
      if let field = PaperWaveField.image(
        size: size, time: time, energy: energy, night: night,
        red: red, green: green, blue: blue)
      {
        context.draw(
          Image(decorative: field, scale: 1), in: CGRect(origin: .zero, size: size))
      }
      // Same Bayer lattice as 0.4.5, drawn as one image. A path of ~10,000 rects
      // was rebuilt on every frame; the coverage formula is unchanged.
      if let grain = PaperInkGrain.image(
        size: size, time: time, energy: energy, night: night, red: red, green: green, blue: blue)
      {
        context.draw(Image(decorative: grain, scale: 1), in: CGRect(origin: .zero, size: size))
      }

      // A restrained surface sheen, shared across all content instead of glass boxes per row.
      context.fill(bounds, with: .linearGradient(
        Gradient(stops: [
          .init(color: .white.opacity(night ? 0.015 : 0.14), location: 0),
          .init(color: .clear, location: 0.45),
          .init(color: .clear, location: 1),
        ]), startPoint: top, endPoint: CGPoint(x: size.width, y: size.height)))
    }
  }
}

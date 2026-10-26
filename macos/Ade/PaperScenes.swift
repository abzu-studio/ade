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

  private static let bayer = [
    0, 48, 12, 60, 3, 51, 15, 63,
    32, 16, 44, 28, 35, 19, 47, 31,
    8, 56, 4, 52, 11, 59, 7, 55,
    40, 24, 36, 20, 43, 27, 39, 23,
    2, 50, 14, 62, 1, 49, 13, 61,
    34, 18, 46, 30, 33, 17, 45, 29,
    10, 58, 6, 54, 9, 57, 5, 53,
    42, 26, 38, 22, 41, 25, 37, 21,
  ]

  var body: some View {
    let color = Enki.atmosphere
    let night = Enki.isNight
    return Canvas(opaque: false, rendersAsynchronously: true) { context, size in
      guard size.width > 0, size.height > 0 else { return }
      let phase = time * .pi * 2
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

      // Periods divide 120 seconds, keeping the clock wrap seamless. A shared flow
      // drives both depth and reflected light, instead of independently wandering shapes.
      let blur = min(54.0, max(24.0, size.height * 0.055))
      for current in 0..<2 {
        let offset = Double(current) * .pi
        var crest = Path()
        for column in 0...64 {
          let u = Double(column) / 64
          let x = (u * 1.16 - 0.08) * size.width
          let swell = 0.065 * sin(u * .pi * 2 - phase / 12 + offset)
            + 0.035 * sin(u * .pi * 3 + phase / 20 + offset)
          let drift = 0.09 * sin(phase / 10 + offset)
          let y = size.height * (0.62 + Double(current) * 0.20 + energy * (swell + drift))
          let point = CGPoint(x: x, y: y)
          if column == 0 { crest.move(to: point) } else { crest.addLine(to: point) }
        }
        var depth = crest
        depth.addLine(to: CGPoint(x: size.width * 1.08, y: size.height * 1.2))
        depth.addLine(to: CGPoint(x: -size.width * 0.08, y: size.height * 1.2))
        depth.closeSubpath()
        context.drawLayer { fluid in
          fluid.addFilter(.blur(radius: blur))
          fluid.fill(depth, with: .color(color.opacity((night ? 0.18 : 0.14) * energy)))
        }
        context.drawLayer { reflection in
          reflection.addFilter(.blur(radius: blur * 0.8))
          reflection.stroke(crest, with: .linearGradient(
            Gradient(stops: [
              .init(color: .clear, location: 0),
              .init(color: .white.opacity((night ? 0.075 : 0.48) * energy), location: 0.35),
              .init(color: color.opacity(night ? 0.22 : 0.08), location: 0.70),
              .init(color: .clear, location: 1),
            ]), startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: size.width, y: size.height)),
            style: StrokeStyle(lineWidth: size.height * 0.10, lineCap: .round, lineJoin: .round))
        }
      }
      // A fixed Bayer lattice makes the water read as printed ink. Only its coverage
      // changes with the same currents as the glass; cells never jump or randomize.
      // Batch the marks into one draw and bound their count on large displays.
      let spacing = max(4.0, sqrt(size.width * size.height / 42_000))
      var grain = Path()
      let drift = 0.09 * sin(phase / 10)
      for column in 0...Int(size.width / spacing) {
        let x = (Double(column) + 0.5) * spacing
        let u = (x / size.width + 0.08) / 1.16
        let swell = 0.065 * sin(u * .pi * 2 - phase / 12)
          + 0.035 * sin(u * .pi * 3 + phase / 20)
        let crest = 0.62 + energy * (swell + drift)
        let firstRow = max(0, Int((crest - 0.18) * size.height / spacing) - 1)
        for row in firstRow...Int(size.height / spacing) {
          let y = (Double(row) + 0.5) * spacing
          let depth = y / size.height - crest
          let rise = min(1.0, max(0.0, (depth + 0.18) / 0.46))
          let density = rise * rise * (3 - 2 * rise) * 0.82 * energy
          let threshold = (Double(Self.bayer[(row & 7) * 8 + (column & 7)]) + 0.5) / 64
          // Smooth coverage across each threshold avoids binary popping or flicker.
          let coverage = min(1.0, max(0.0, (density - threshold) * 7 + 0.5))
            * min(1.0, density * 12)
          guard coverage > 0.005 else { continue }
          let side = spacing * 0.56 * sqrt(coverage)
          grain.addRect(CGRect(x: x - side / 2, y: y - side / 2, width: side, height: side))
        }
      }
      context.fill(grain, with: .color(color.opacity(night ? 0.46 : 0.60)))

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

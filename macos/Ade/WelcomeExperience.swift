import SwiftUI

enum WelcomePreferences {
  static let store: UserDefaults = {
    #if DEBUG
      if let run = ProcessInfo.processInfo.environment["ADE_UI_TEST_RUN"] {
        return UserDefaults(suiteName: "AdeWelcomeTests-" + run)!
      }
    #endif
    return .standard
  }()
  static var bypassForExistingTests: Bool {
    #if DEBUG
      return ProcessInfo.processInfo.environment["ADE_UI_TEST_RUN"] != nil
        && ProcessInfo.processInfo.environment["ADE_TEST_WELCOME"] != "1"
    #else
      return false
    #endif
  }
}

/// The workspace stays alive under the introduction, preserving drafts when it is replayed.
struct LaunchExperience: View {
  @Environment(AppModel.self) private var model
  @Environment(\.paperReduceMotion) private var reducedMotion
  @AppStorage("ade-opening-completed-v2", store: WelcomePreferences.store) private var completed =
    false
  private var presenting: Bool {
    model.welcomeRequested || (!completed && !WelcomePreferences.bypassForExistingTests)
  }
  var body: some View {
    WorkspaceView().opacity(presenting ? 0 : 1).disabled(presenting)
      .environment(\.paperAtmosphereVisible, !presenting)
      .overlay {
        if presenting {
          WelcomeExperience {
            completed = true
            model.welcomeRequested = false
          }.transition(.opacity)
        }
      }
      .animation(reducedMotion ? nil : .easeInOut(duration: 0.55), value: presenting)
      .task { await model.load() }
  }
}

/// An audiovisual ident, not an onboarding form. It never creates or edits records.
struct WelcomeExperience: View {
  @Environment(AppModel.self) private var model
  @Environment(\.paperReduceMotion) private var reducedMotion
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.controlActiveState) private var activeState
  @AppStorage("ade-opening-sound", store: WelcomePreferences.store) private var soundEnabled = true
  @State private var sound = OpeningSound()
  @State private var elapsed = 0.0
  @State private var started: Date?
  @State private var ended = false
  var finish: () -> Void
  private let duration = 8.4
  private var active: Bool { scenePhase == .active && activeState != .inactive }

  var body: some View {
    ZStack {
      PaperScene.deep
      TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active)) { timeline in
        let time = min(
          duration, elapsed + (started.map { timeline.date.timeIntervalSince($0) } ?? 0))
        OpeningFrame(time: time, reduced: reducedMotion, spanish: model.locale == "es")
      }.accessibilityHidden(true)
      VStack {
        HStack {
          Text(model.t("PERSONAS · ENCUENTROS · MEMORIA", "PEOPLE · ENCOUNTERS · MEMORY"))
            .font(.custom(Enki.mono, size: 10)).tracking(2)
          Spacer()
          Text("ADÊ").font(.custom(Enki.condensed, size: 22)).tracking(3)
        }.foregroundStyle(Enki.onDark.opacity(0.8))
        Spacer()
        HStack {
          Button {
            soundEnabled.toggle()
          } label: {
            Label(
              model.t(
                soundEnabled ? "Sonido activado" : "Sonido desactivado",
                soundEnabled ? "Sound on" : "Sound off"),
              systemImage: soundEnabled ? "speaker.wave.2" : "speaker.slash")
          }.accessibilityIdentifier("opening-sound")
          Spacer()
          Button(model.t("Omitir →", "Skip →"), action: complete)
            .accessibilityIdentifier("welcome-skip").keyboardShortcut(.cancelAction)
        }.font(.custom(Enki.mono, size: 11)).foregroundStyle(Enki.onDark)
          .buttonStyle(.plain)
      }.padding(36)
    }.accessibilityElement(children: .contain)
      .onAppear { updatePlayback() }
      .onChange(of: active) { updatePlayback() }
      .onChange(of: soundEnabled) { sound.setEnabled(soundEnabled) }
      .onDisappear { sound.stop() }
      .task(id: active) {
        guard active else { return }
        do {
          // Suspension cancels this task; resume waits only the remaining sequence time.
          try await Task.sleep(for: .seconds(max(0, duration - elapsed)))
          guard !Task.isCancelled else { return }
          complete()
        } catch {}
      }
  }
  private func updatePlayback() {
    guard !ended else { return }
    if active {
      if started == nil { started = Date() }
      sound.play(at: elapsed, enabled: soundEnabled)
    } else {
      if let start = started { elapsed = min(duration, elapsed + Date().timeIntervalSince(start)) }
      started = nil
      sound.pause()
    }
  }
  private func complete() {
    guard !ended else { return }
    ended = true
    sound.stop()
    finish()
  }
}

private struct OpeningFrame: View {
  let time: Double
  let reduced: Bool
  let spanish: Bool
  private func ramp(_ start: Double, _ length: Double) -> Double {
    let t = max(0, min(1, (time - start) / length))
    return t * t * (3 - 2 * t)
  }
  var body: some View {
    GeometryReader { geometry in
      let reveal = reduced ? 1 : ramp(0.2, 1.1)
      let connections = reduced ? 1 : ramp(2.0, 1.5)
      let memory = reduced ? 1 : ramp(4.5, 1.5)
      let wordmark = reduced ? 1 : ramp(6.0, 1.0)
      ZStack {
        Canvas { context, size in
          let center = CGPoint(x: size.width / 2, y: size.height * 0.45)
          let radius = min(size.width * 0.28, size.height * 0.31)
          let breath = reduced ? 0 : sin(time * 0.65) * 8
          for ring in 0..<7 {
            let r = radius * (0.4 + Double(ring) * 0.13) + breath
            let ellipse = CGRect(
              x: center.x - r, y: center.y - r * 0.58, width: r * 2, height: r * 1.16)
            context.stroke(
              Path(ellipseIn: ellipse), with: .color(PaperScene.abzu.opacity(0.12 * reveal)),
              lineWidth: 1)
          }
          var points: [CGPoint] = []
          for i in 0..<12 {
            let angle = Double(i) * .pi / 6 - .pi / 2 + (reduced ? 0 : time * 0.025)
            let orbital = CGPoint(
              x: center.x + cos(angle) * radius,
              y: center.y + sin(angle) * radius * 0.68)
            let filed = CGPoint(
              x: center.x - 120 + Double(i % 4) * 80,
              y: center.y - 64 + Double(i / 4) * 64)
            let point = CGPoint(
              x: orbital.x + (filed.x - orbital.x) * memory,
              y: orbital.y + (filed.y - orbital.y) * memory)
            points.append(point)
            let alpha = max(0, min(1, reveal * 2 - Double(i) / 12)) * (1 - wordmark * 0.8)
            context.fill(
              Path(ellipseIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)),
              with: .color(PaperScene.gold.opacity(alpha)))
            context.stroke(
              Path(ellipseIn: CGRect(x: point.x - 12, y: point.y - 12, width: 24, height: 24)),
              with: .color(PaperScene.gold.opacity(alpha * 0.3)), lineWidth: 0.8)
          }
          for i in 0..<points.count {
            let start = points[i]
            let end = points[(i + 4) % points.count]
            var line = Path()
            line.move(to: start)
            line.addLine(
              to: CGPoint(
                x: start.x + (end.x - start.x) * connections,
                y: start.y + (end.y - start.y) * connections))
            context.stroke(
              line, with: .color(PaperScene.gold.opacity(0.32 * connections * (1 - memory))),
              lineWidth: 1)
          }
          for page in (0..<3).reversed() {
            let rect = CGRect(
              x: center.x - 165 + Double(page) * 12, y: center.y - 117 + Double(page) * 10,
              width: 306, height: 214)
            context.fill(
              Path(rect), with: .color(Enki.onDark.opacity(0.035 * memory * (1 - wordmark))))
            context.stroke(
              Path(rect), with: .color(PaperScene.gold.opacity(0.5 * memory * (1 - wordmark))),
              lineWidth: 1)
          }
        }
        VStack(spacing: 18) {
          Text("ADÊ").font(.custom(Enki.display, size: min(150, geometry.size.width * 0.16)))
            .tracking(6).foregroundStyle(Enki.onDark).opacity(wordmark)
            .offset(y: reduced ? 0 : (1 - wordmark) * 12)
          Text(spanish ? "CADA ENCUENTRO CUENTA." : "EVERY ENCOUNTER COUNTS.")
            .font(.custom(Enki.mono, size: 12)).tracking(3).foregroundStyle(PaperScene.gold)
            .opacity(wordmark)
        }.position(x: geometry.size.width / 2, y: geometry.size.height * 0.44)
        VStack(spacing: 10) {
          Text(
            reduced
              ? (spanish ? "PERSONAS. ENCUENTROS. MEMORIA." : "PEOPLE. ENCOUNTERS. MEMORY.")
              : time < 2.7
                ? (spanish ? "REUNIR" : "GATHER")
                : time < 5.0
                  ? (spanish ? "PARTICIPAR" : "PARTICIPATE")
                  : (spanish ? "CONSERVAR" : "PRESERVE")
          )
          .font(.custom(Enki.condensed, size: 30)).tracking(4)
          Text(
            spanish ? "Lo que hacemos juntos deja huella." : "What we do together leaves a mark."
          )
          .font(.custom("Inter-Regular", size: 13)).foregroundStyle(Enki.onDark.opacity(0.65))
        }.foregroundStyle(PaperScene.gold).opacity(reveal * (1 - wordmark))
          .position(x: geometry.size.width / 2, y: geometry.size.height * 0.79)
      }
    }.clipped()
  }
}

import SwiftUI

/// Short, interruptible motion. No animation drives a model change or waits for a save.
enum PaperMotion {
  static let response = Animation.spring(response: 0.28, dampingFraction: 0.86)
  static let navigation = Animation.spring(response: 0.38, dampingFraction: 0.92)
  static let arrival = Animation.easeOut(duration: 0.28)
}

private struct PaperReduceMotionKey: EnvironmentKey {
  static let defaultValue = false
}
extension EnvironmentValues {
  var paperReduceMotion: Bool {
    get { self[PaperReduceMotionKey.self] }
    set { self[PaperReduceMotionKey.self] = newValue }
  }
}

struct MotionAccessibility: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var systemReduced
  private var forced: Bool {
    #if DEBUG
      ProcessInfo.processInfo.environment["ADE_REDUCE_MOTION"] == "1"
    #else
      false
    #endif
  }
  func body(content: Content) -> some View {
    content.environment(\.paperReduceMotion, systemReduced || forced)
  }
}

/// Keeps a single live view, including its focus, draft and selection, during navigation.
struct PaperArrival: ViewModifier {
  var trigger: String
  @Environment(\.paperReduceMotion) private var reduced
  @State private var settled = false
  func body(content: Content) -> some View {
    content.opacity(reduced || settled ? 1 : 0)
      .offset(y: reduced || settled ? 0 : 9)
      .task(id: trigger) {
        guard !reduced else {
          settled = true
          return
        }
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { settled = false }
        // One presentation frame, cancelled automatically by the next navigation.
        do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
        guard !Task.isCancelled else { return }
        withAnimation(PaperMotion.arrival) { settled = true }
      }
      .onChange(of: reduced) { if reduced { settled = true } }
  }
}

struct PaperHover: ViewModifier {
  @Environment(\.isEnabled) private var enabled
  @Environment(\.paperReduceMotion) private var reduced
  @State private var hovering = false
  func body(content: Content) -> some View {
    content.background(Enki.accent.opacity(hovering && enabled ? 0.045 : 0))
      .onHover { hovering = $0 }
      .animation(reduced ? nil : .easeOut(duration: 0.16), value: hovering)
  }
}

struct PaperButtonStyle: ButtonStyle {
  var lift: CGFloat = 0
  func makeBody(configuration: Configuration) -> some View {
    PaperButtonFace(pressed: configuration.isPressed, lift: lift) { configuration.label }
  }
}
private struct PaperButtonFace<Label: View>: View {
  @Environment(\.isEnabled) private var enabled
  @Environment(\.paperReduceMotion) private var reduced
  @State private var hovering = false
  var pressed: Bool
  var lift: CGFloat
  @ViewBuilder var label: Label
  var body: some View {
    label.contentShape(Rectangle())
      .background(Enki.accent.opacity(hovering && enabled ? 0.045 : 0))
      .opacity(enabled ? (pressed ? 0.7 : 1) : 0.42)
      .scaleEffect(!reduced && pressed && enabled ? 0.985 : 1)
      .offset(y: !reduced && hovering && enabled && !pressed ? -lift : 0)
      .onHover { hovering = $0 }
      .animation(reduced ? nil : PaperMotion.response, value: pressed)
      .animation(reduced ? nil : PaperMotion.response, value: hovering)
  }
}

struct PaperLinkFace<Label: View>: View {
  @Environment(\.isEnabled) private var enabled
  @Environment(\.paperReduceMotion) private var reduced
  @State private var hovering = false
  var pressed: Bool
  var large: Bool
  @ViewBuilder var label: Label
  var body: some View {
    label.font(.custom(large ? Enki.display : Enki.mono, size: large ? 22 : 10))
      .textCase(.uppercase).tracking(large ? 0.4 : 1.2)
      .padding(.bottom, 3)
      .overlay(alignment: .bottom) {
        Rectangle().fill(Enki.accent.opacity(0.6)).frame(height: large ? 2 : 0.6)
          .overlay(alignment: .leading) {
            Rectangle().fill(Enki.accent).frame(height: large ? 2 : 1)
              .scaleEffect(x: hovering && enabled ? 1 : 0, anchor: .leading)
          }.allowsHitTesting(false)
      }
      .foregroundStyle(large || (hovering && enabled) ? Enki.accent : Enki.ink)
      .opacity(!enabled ? 0.32 : pressed ? 0.65 : 1)
      .offset(y: !reduced && hovering && enabled && !pressed ? -1 : 0)
      .scaleEffect(!reduced && pressed && enabled ? 0.98 : 1)
      .padding(.vertical, 4).contentShape(Rectangle())
      .onHover { hovering = $0 }
      .animation(reduced ? nil : PaperMotion.response, value: hovering)
      .animation(reduced ? nil : PaperMotion.response, value: pressed)
  }
}

struct PaperNumber: ViewModifier {
  var value: String
  @Environment(\.paperReduceMotion) private var reduced
  func body(content: Content) -> some View {
    content.contentTransition(reduced ? .identity : .numericText())
      .animation(reduced ? nil : PaperMotion.response, value: value)
  }
}

/// Decorative layers never intercept events or become accessibility elements.
struct PaperElevation: ViewModifier {
  @Environment(\.accessibilityReduceTransparency) private var reducedTransparency
  func body(content: Content) -> some View {
    content.background {
      Rectangle().fill(Enki.paper)
        .shadow(color: Color.black.opacity(reducedTransparency ? 0 : 0.075), radius: 16, x: 0, y: 7)
        .shadow(color: Color.black.opacity(reducedTransparency ? 0 : 0.035), radius: 2, x: 0, y: 1)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
    .overlay(alignment: .top) {
      Rectangle().fill(.white.opacity(reducedTransparency ? 0 : (Enki.isNight ? 0.06 : 0.42))).frame(height: 1)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
  }
}

struct PaperFieldFace<Content: View>: View {
  @Environment(\.paperReduceMotion) private var reduced
  @FocusState private var focused: Bool
  @ViewBuilder var content: Content
  var body: some View {
    content.focused($focused).padding(.vertical, 9).padding(.horizontal, 2)
      .background(Enki.paper)
      .overlay(alignment: .bottom) {
        PaperRule().overlay(alignment: .leading) {
          Rectangle().fill(Enki.accent).frame(height: 1.4)
            .scaleEffect(x: focused ? 1 : 0, anchor: .leading)
            .animation(reduced ? nil : PaperMotion.response, value: focused)
        }.allowsHitTesting(false)
      }
  }
}

struct PaperTextChange: ViewModifier {
  var value: String
  @Environment(\.paperReduceMotion) private var reduced
  func body(content: Content) -> some View {
    content.contentTransition(reduced ? .identity : .opacity)
      .animation(reduced ? nil : .easeOut(duration: 0.18), value: value)
  }
}

/// Saving occupies its own overlay, so a write never shifts the workspace beneath the pointer.
struct PaperBusyIndicator: View {
  var busy: Bool
  @Environment(\.paperReduceMotion) private var reduced
  var body: some View {
    ZStack(alignment: .top) {
      if busy {
        ProgressView().progressViewStyle(.linear).tint(Enki.accent)
          .transition(.opacity)
      }
    }.frame(height: 3).allowsHitTesting(false)
      .animation(reduced ? nil : .easeOut(duration: 0.16), value: busy)
  }
}

import CoreText
import SwiftUI

enum DayTheme: String, CaseIterable, Identifiable {
  case indigo, graphite
  case nightIndigo = "night-indigo", nightGraphite = "night-graphite"
  var id: String { rawValue }
  var isNight: Bool { self == .nightIndigo || self == .nightGraphite }
  var isIndigo: Bool { self == .indigo || self == .nightIndigo }
  var iconName: String { isIndigo ? "indigo" : "graphite" }
  var title: String { (isNight ? "Noche" : "Día") + (isIndigo ? " · Índigo" : " · Grafito") }
  var englishTitle: String { (isNight ? "Night" : "Day") + (isIndigo ? " · Indigo" : " · Graphite") }
}

/// UI preference only. Switching never replaces view identity or touches workspace data.
@MainActor @Observable final class DayAppearance {
  static let shared = DayAppearance()
  private let defaults: UserDefaults
  var preferenceStore: UserDefaults { defaults }
  var theme: DayTheme {
    didSet { defaults.set(theme.rawValue, forKey: "ade-day-theme") }
  }
  private init() {
    #if DEBUG
      if let run = ProcessInfo.processInfo.environment["ADE_UI_TEST_RUN"] {
        defaults = UserDefaults(suiteName: "AdeDayTests-" + run)!
      } else {
        defaults = .standard
      }
    #else
      defaults = .standard
    #endif
    theme = DayTheme(rawValue: defaults.string(forKey: "ade-day-theme") ?? "") ?? .indigo
  }
  func applyDockIcon() {
    guard
      let url = Bundle.main.url(
        forResource: "AdeIcon-" + theme.iconName,
        withExtension: "icns", subdirectory: "Resources/Icons"), let icon = NSImage(contentsOf: url)
    else { return }
    NSApplication.shared.applicationIconImage = icon
  }
}

@MainActor enum Enki {
  static func hex(_ value: UInt32) -> Color {
    Color(
      red: Double((value >> 16) & 255) / 255,
      green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
  }
  static var isNight: Bool { DayAppearance.shared.theme.isNight }
  private static var indigo: Bool { DayAppearance.shared.theme.isIndigo }
  static var paper: Color { hex(isNight ? (indigo ? 0x0C1020 : 0x0F1113) : 0xFAFAF8) }
  static var ink: Color { hex(isNight ? 0xEAECF3 : 0x242629) }
  static var heading: Color { ink }
  static var accent: Color { hex(isNight ? (indigo ? 0xA5ADF7 : 0xF18B68) : (indigo ? 0x454B9D : 0xB64B32)) }
  static var selection: Color { hex(isNight ? (indigo ? 0x29315D : 0x2B3037) : (indigo ? 0x454B9D : 0x242629)) }
  static var brand: Color { isNight ? (indigo ? accent : ink) : selection }
  static var deep: Color { hex(indigo ? 0x292D53 : 0x242629) }
  static var onDark: Color { hex(0xF4F5FA) }
  static var onAccent: Color { isNight ? paper : onDark }
  static var stamp: Color { isNight ? (indigo ? accent : ink) : deep }
  static var atmosphere: Color { hex(isNight ? (indigo ? 0x6573D7 : 0x697582) : (indigo ? 0x777FA2 : 0x858B91)) }
  static var outer: Color { hex(isNight ? (indigo ? 0x080B15 : 0x090B0D) : 0xE8E7E2) }
  static var side: Color { hex(isNight ? (indigo ? 0x101627 : 0x171B20) : 0xF1F1EE) }
  static var clay: Color { accent }
  static var rule: Color { hex(isNight ? (indigo ? 0x303953 : 0x343B43) : 0xD6D8D9) }
  static var present: Color { hex(isNight ? 0x57C6CF : 0x227880) }
  static var absent: Color { hex(isNight ? 0xF18F9C : 0xB9474A) }
  static var pending: Color { hex(isNight ? 0xDDC37C : 0x927529) }
  static let display = "BarlowCondensed-ExtraBold"
  static let condensed = "BarlowCondensed-Bold"
  static let mono = "IBMPlexMono-Medium"
  static func registerFonts() {
    guard let folder = Bundle.main.resourceURL?.appendingPathComponent("Resources/Fonts"),
      let urls = try? FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: nil)
    else { return }
    for url in urls where url.pathExtension == "ttf" {
      CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
  }
}
struct PageHeading<Actions: View>: View {
  var title: String
  var subtitle: String
  @ViewBuilder var actions: Actions
  var body: some View {
    HStack(alignment: .center) {
      VStack(alignment: .leading, spacing: 6) {
        Text(subtitle.uppercased()).font(.custom(Enki.mono, size: 10)).tracking(1)
          .foregroundStyle(.secondary)
        Text(title.uppercased()).font(.custom(Enki.display, size: 44)).foregroundStyle(Enki.heading)
          .accessibilityAddTraits(.isHeader)
      }
      Spacer()
      actions
    }.padding(.horizontal, 32).padding(.top, 24).padding(.bottom, 18)
  }
}
struct EmptyState: View {
  var title: String
  var detail: String
  var symbol = "tray"
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      PaperRule(strong: true).frame(width: 48)
      Text(title.uppercased()).font(.custom(Enki.condensed, size: 28))
        .foregroundStyle(Enki.accent).fixedSize(horizontal: false, vertical: true)
      Text(detail).font(.custom("Inter-Regular", size: 13)).lineSpacing(5)
        .foregroundStyle(Enki.ink.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
    }.frame(maxWidth: 440, alignment: .leading).padding(32)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
      .accessibilityElement(children: .contain).accessibilityIdentifier("empty-state")
  }
}
struct ActionLink: ButtonStyle {
  var large = false
  func makeBody(configuration: Configuration) -> some View {
    PaperLinkFace(pressed: configuration.isPressed, large: large) { configuration.label }
  }
}
struct PaperRule: View {
  var strong = false
  var body: some View {
    Rectangle().fill(strong ? Enki.ink : Enki.rule).frame(height: strong ? 1.5 : 0.5)
  }
}
struct MicroLabel: View {
  var text: String
  var body: some View {
    Text(text.uppercased()).font(.custom(Enki.mono, size: 9)).tracking(1.6).foregroundStyle(
      Enki.ink)
  }
}
struct StatusStamp: View {
  var text: String
  var filled = false
  var muted = false
  var dashed = false
  var angle: Double = -2
  private var stampColor: Color {
    switch text.lowercased() {
    case "presente", "present", "programado", "scheduled": Enki.present
    case "ausente", "absent", "cancelado", "cancelled": Enki.absent
    case "pendiente", "pending": Enki.pending
    default: Enki.stamp
    }
  }
  var body: some View {
    Text(text.uppercased()).font(.custom(Enki.condensed, size: 13)).tracking(1.2).fixedSize(
      horizontal: true, vertical: false
    )
    .padding(.horizontal, 8).padding(.vertical, 4)
    .foregroundStyle(filled ? Enki.paper : stampColor)
    .background(filled ? stampColor : .clear)
    .overlay {
      Rectangle().strokeBorder(
        stampColor, style: StrokeStyle(lineWidth: 1.0, dash: dashed ? [4, 3] : []))
    }
    .rotationEffect(.degrees(angle)).opacity(muted ? 0.42 : 1)
  }
}
struct SheetFrame<Content: View>: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var title: String
  var save: () async -> Bool
  @ViewBuilder var content: Content
  var body: some View {
    VStack(spacing: 0) {
      PageHeading(title: title, subtitle: model.t("Edición", "Edit")) { EmptyView() }
      ScrollView { content.padding(24).modifier(PaperArrival(trigger: "sheet")) }.frame(
        maxHeight: .infinity)
      Divider()
      HStack {
        Button(model.t("Cancelar", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
        Spacer()
        Button(model.t("Guardar", "Save")) { Task { if await save() { dismiss() } } }
          .keyboardShortcut(.defaultAction).accessibilityIdentifier("sheet-save").disabled(
            model.busy || model.pending != nil)
      }.padding(20)
      if let error = model.error {
        Text(error).font(.callout).foregroundStyle(.red).padding([.horizontal, .bottom])
      }
    }.frame(width: 620, height: 640).background { PaperGlassSurface() }
      .buttonStyle(ActionLink()).textFieldStyle(PaperFieldStyle()).toggleStyle(PaperToggleStyle())
      .scrollContentBackground(.hidden)
  }
}
struct DayField: View {
  @Environment(AppModel.self) private var model
  var title: String
  @Binding var value: String
  @State private var calendarOpen = false
  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      MicroLabel(text: title + model.t(" · AAAA-MM-DD", " · YYYY-MM-DD"))
      HStack {
        TextField(title, text: $value).textFieldStyle(PaperFieldStyle())
          .accessibilityLabel(title).help("2026-10-25 · ISO 8601")
        Button {
          calendarOpen = true
        } label: {
          Image(systemName: "calendar")
        }
        .buttonStyle(ActionLink()).accessibilityLabel(
          title + " · " + model.t("Calendario", "Calendar")
        ).accessibilityIdentifier("calendar-" + title)
        .popover(isPresented: $calendarOpen, arrowEdge: .bottom) {
          PaperCalendar(value: $value, close: { calendarOpen = false })
            .onExitCommand { calendarOpen = false }
        }
      }
    }
  }
}

struct VerticalDottedLine: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.midX, y: 0))
    path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
    return path
  }
}

struct DayThemeChooser: View {
  @Environment(AppModel.self) private var model
  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 8) { choices }
      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) { choices }
    }
  }
  private var choices: some View {
      ForEach(DayTheme.allCases) { theme in
        Button {
          DayAppearance.shared.theme = theme
        } label: {
          HStack(spacing: 7) {
            Image(systemName: theme.isNight ? "moon.fill" : "sun.max.fill")
              .foregroundStyle(theme.isIndigo ? Enki.hex(0x858DE0) : Enki.ink).frame(
              width: 9, height: 9)
            Text(model.t(theme.title, theme.englishTitle))
              .font(.custom(Enki.mono, size: 10))
            if DayAppearance.shared.theme == theme {
              Image(systemName: "checkmark").font(.system(size: 9))
            }
          }.fixedSize().padding(.horizontal, 12).padding(.vertical, 9)
            .background(Enki.paper)
            .overlay {
              RoundedRectangle(cornerRadius: 2).stroke(
                DayAppearance.shared.theme == theme ? Enki.accent : Enki.rule)
            }
        }.buttonStyle(.plain).accessibilityIdentifier("theme-" + theme.rawValue)
          .accessibilityValue(
            DayAppearance.shared.theme == theme ? model.t("Seleccionado", "Selected") : "")
      }
  }
}
struct DayPrimaryButton: ButtonStyle {
  @Environment(\.isEnabled) private var enabled
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.custom(Enki.mono, size: 10)).textCase(.uppercase).tracking(0.8)
      .padding(.horizontal, 14).padding(.vertical, 10).foregroundStyle(Enki.onAccent)
      .background { PaperAccentSurface(tint: Enki.accent) }
      .opacity(!enabled ? 0.4 : configuration.isPressed ? 0.7 : 1)
  }
}

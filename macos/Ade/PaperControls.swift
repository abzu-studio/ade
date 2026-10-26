import SwiftUI

/// App-owned controls share the paper typography and rules; their contents remain native SwiftUI.
struct PaperOption: Identifiable {
  var id: String
  var title: String
  init(_ id: String, _ title: String) {
    self.id = id
    self.title = title
  }
}
struct PaperPicker: View {
  @Environment(\.paperReduceMotion) private var reducedMotion
  @Environment(AppModel.self) private var model
  var title: String
  @Binding var selection: String
  var options: [PaperOption]
  @State private var expanded = false
  @State private var search = ""
  @Environment(\.isEnabled) private var enabled
  init(_ title: String, selection: Binding<String>, options: [PaperOption]) {
    self.title = title
    _selection = selection
    self.options = options
  }
  var body: some View {
    Button {
      search = ""
      expanded.toggle()
    } label: {
      VStack(alignment: .leading, spacing: 7) {
        MicroLabel(text: title)
        HStack(spacing: 12) {
          Text(options.first { $0.id == selection }?.title ?? "—")
            .font(.custom(Enki.condensed, size: 19)).lineLimit(2)
            .modifier(PaperTextChange(value: selection))
          Spacer(minLength: 4)
          Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            .rotationEffect(.degrees(expanded && !reducedMotion ? 180 : 0))
            .animation(reducedMotion ? nil : PaperMotion.response, value: expanded)
        }.foregroundStyle(Enki.accent)
        PaperRule()
      }.padding(.vertical, 5).contentShape(Rectangle())
    }.buttonStyle(PaperButtonStyle()).opacity(enabled ? 1 : 0.4)
      .accessibilityLabel(title).accessibilityValue(
        options.first { $0.id == selection }?.title ?? "—"
      )
      .popover(isPresented: $expanded, arrowEdge: .bottom) { popup }
  }
  private var filtered: [PaperOption] {
    options.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }
  }
  private var popup: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        MicroLabel(text: title)
        Spacer()
        Button {
          expanded = false
        } label: {
          Image(systemName: "xmark")
        }.help(model.t("Cerrar", "Close"))
      }
      .padding(16)
      PaperRule(strong: true)
      if options.count > 8 {
        TextField(model.t("Buscar", "Search"), text: $search).textFieldStyle(PaperFieldStyle())
          .padding(14)
      }
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(filtered) { option in
            optionRow(option)
            PaperRule()
          }
        }
      }.frame(height: min(320, CGFloat(max(1, filtered.count)) * 53))
    }.frame(width: 310).fixedSize(horizontal: false, vertical: true)
      .background { PaperGlassSurface() }.foregroundStyle(Enki.ink).buttonStyle(ActionLink())
      .onExitCommand { expanded = false }

  }
  private func optionRow(_ option: PaperOption) -> some View {
    Button {
      selection = option.id
      expanded = false
    } label: {
      HStack(spacing: 12) {
        Text(selection == option.id ? "✓" : " ").font(.custom(Enki.mono, size: 11)).frame(width: 14)
        Text(option.title).font(.custom(Enki.condensed, size: 20)).multilineTextAlignment(.leading)
        Spacer(minLength: 0)
      }.padding(.horizontal, 16).padding(.vertical, 12)
        .foregroundStyle(selection == option.id ? Enki.accent : Enki.ink)
        .background(selection == option.id ? Enki.side.opacity(0.8) : .clear).contentShape(
          Rectangle())
    }.buttonStyle(PaperButtonStyle()).accessibilityLabel(option.title)
      .accessibilityIdentifier("option-" + option.id)
      .accessibilityAddTraits(selection == option.id ? .isSelected : [])
  }
}
struct PaperFieldStyle: TextFieldStyle {
  func _body(configuration: TextField<Self._Label>) -> some View {
    PaperFieldFace {
      configuration.textFieldStyle(.plain).font(.custom("Inter-Regular", size: 13))
    }
  }
}
struct PaperToggleStyle: ToggleStyle {
  @Environment(\.paperReduceMotion) private var reducedMotion
  func makeBody(configuration: Configuration) -> some View {
    Button {
      configuration.isOn.toggle()
    } label: {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text(configuration.isOn ? "✓" : " ").font(.custom(Enki.mono, size: 12))
          .frame(width: 17, height: 17).background(configuration.isOn ? Enki.accent : .clear)
          .foregroundStyle(Enki.paper).overlay {
            Rectangle().strokeBorder(Enki.accent, lineWidth: 1)
          }
        configuration.label.font(.custom("Inter-Regular", size: 13)).multilineTextAlignment(
          .leading)
      }.padding(.vertical, 6).contentShape(Rectangle())
        .animation(reducedMotion ? nil : PaperMotion.response, value: configuration.isOn)
    }.buttonStyle(PaperButtonStyle()).accessibilityRepresentation {
      Toggle(isOn: configuration.$isOn) { configuration.label }
    }
  }
}
struct PaperForm<Content: View>: View {
  @ViewBuilder var content: Content
  var body: some View {
    VStack(alignment: .leading, spacing: 18) { content }
      .frame(maxWidth: .infinity, alignment: .leading)
      .textFieldStyle(PaperFieldStyle()).toggleStyle(PaperToggleStyle()).buttonStyle(ActionLink())
  }
}
struct PaperSection<Content: View>: View {
  var title: String
  @ViewBuilder var content: Content
  init(_ title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      MicroLabel(text: title).padding(.top, 12)
      PaperRule(strong: true)
      content
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}
struct PaperMenu<Content: View, Label: View>: View {
  @ViewBuilder var content: Content
  @ViewBuilder var label: Label
  @State private var expanded = false
  init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
    self.content = content()
    self.label = label()
  }
  var body: some View {
    Button {
      expanded.toggle()
    } label: {
      label
    }.buttonStyle(ActionLink())
      .popover(isPresented: $expanded) {
        VStack(alignment: .leading, spacing: 18) { content }
          .buttonStyle(PaperMenuAction(close: { expanded = false }))
          .padding(20).frame(minWidth: 200, alignment: .leading)
          .background { PaperGlassSurface() }.foregroundStyle(Enki.ink)
          .onExitCommand { expanded = false }
      }
  }
}
extension PaperMenu where Label == Text {
  init(_ title: String, @ViewBuilder content: () -> Content) {
    self.content = content()
    label = Text(title)
  }
}
private struct PaperMenuAction: PrimitiveButtonStyle {
  var close: () -> Void
  func makeBody(configuration: Configuration) -> some View {
    Button {
      close()
      configuration.trigger()
    } label: {
      configuration.label
    }
    .buttonStyle(ActionLink())
  }
}
struct PaperDisclosure<Content: View>: View {
  @Environment(\.paperReduceMotion) private var reducedMotion
  @Environment(AppModel.self) private var model
  var title: String
  @ViewBuilder var content: Content
  @State private var expanded = false
  init(_ title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button {
        expanded.toggle()
      } label: {
        HStack {
          Text(title)
          Spacer()
          Text(expanded ? "−" : "+")
        }
      }.buttonStyle(ActionLink()).accessibilityValue(
        expanded ? model.t("Abierto", "Open") : model.t("Cerrado", "Closed"))
      if expanded { content.transition(.opacity) }
    }.animation(reducedMotion ? nil : PaperMotion.response, value: expanded)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}
struct PaperSelectionRow<Content: View>: View {
  @Environment(\.paperReduceMotion) private var reducedMotion
  var selected: Bool
  var action: () -> Void
  @ViewBuilder var content: Content
  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 0) {
        content.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        PaperRule()
      }.background(selected ? Enki.side : Enki.paper)
        .overlay(alignment: .leading) {
          if selected { Rectangle().fill(Enki.accent).frame(width: 3) }
        }
        .contentShape(Rectangle())
    }.buttonStyle(PaperButtonStyle())
      .animation(reducedMotion ? nil : PaperMotion.response, value: selected)
      .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

struct PaperInput<Content: View>: View {
  var title: String
  @ViewBuilder var content: Content
  init(_ title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      MicroLabel(text: title)
      content.textFieldStyle(PaperFieldStyle())
    }
  }
}

private enum MonthTitle {
  private static let lock = NSLock()
  private static var localeID = ""
  private static let formatter: DateFormatter = {
    let format = DateFormatter()
    format.dateFormat = "LLLL yyyy"
    return format
  }()
  static func format(_ date: Date, locale: Locale, timeZone: TimeZone) -> String {
    lock.lock()
    defer { lock.unlock() }
    if localeID != locale.identifier {
      formatter.locale = locale
      formatter.timeZone = timeZone
      localeID = locale.identifier
    }
    return formatter.string(from: date)
  }
}

struct PaperCalendar: View {
  @Binding var value: String
  var close: () -> Void
  @State private var month: Date
  @Environment(AppModel.self) private var model
  private var locale: Locale { Locale(identifier: model.locale) }
  private var calendar: Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 0)!
    cal.locale = locale
    return cal
  }
  init(value: Binding<String>, close: @escaping () -> Void) {
    _value = value
    self.close = close
    _month = State(initialValue: Day.date(value.wrappedValue) ?? Date())
  }
  private var monthTitle: String {
    MonthTitle.format(month, locale: locale, timeZone: calendar.timeZone)
  }
  private var first: Date {
    calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
  }
  private var offset: Int { (calendar.component(.weekday, from: first) + 5) % 7 }
  private var count: Int { calendar.range(of: .day, in: .month, for: first)!.count }
  var body: some View {
    VStack(spacing: 16) {
      HStack {
        Button("←") { move(-1) }.accessibilityIdentifier("calendar-previous-month")
          .accessibilityLabel(
            locale.language.languageCode?.identifier == "es" ? "Mes anterior" : "Previous month")
        Spacer()
        Text(monthTitle).font(
          .custom(Enki.condensed, size: 23)
        ).textCase(.uppercase).modifier(PaperTextChange(value: monthTitle))
        Spacer()
        Button("→") { move(1) }.accessibilityIdentifier("calendar-next-month").accessibilityLabel(
          locale.language.languageCode?.identifier == "es" ? "Mes siguiente" : "Next month")
      }
      PaperRule(strong: true)
      LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
        ForEach(0..<7, id: \.self) { index in
          Text(calendar.shortStandaloneWeekdaySymbols[(index + 1) % 7]).font(
            .custom(Enki.mono, size: 9))
        }
        ForEach(0..<(offset + count), id: \.self) { cell in
          if cell < offset {
            Color.clear.frame(height: 34).accessibilityHidden(true)
          } else {
            let day = cell - offset + 1
            let date = calendar.date(byAdding: .day, value: day - 1, to: first)!
            let key = Day.string(date)
            Button {
              value = key
              close()
            } label: {
              Text(String(day)).font(.custom(Enki.mono, size: 12)).frame(maxWidth: .infinity).frame(
                height: 34
              )
              .background(value == key ? Enki.accent : Enki.paper)
              .foregroundStyle(value == key ? Enki.paper : Enki.ink)
              .overlay { Rectangle().strokeBorder(Enki.rule, lineWidth: 0.5) }
            }.buttonStyle(PaperButtonStyle()).accessibilityLabel(key).accessibilityIdentifier(
              "calendar-day-" + key
            )
            .accessibilityAddTraits(value == key ? .isSelected : [])
          }
        }
      }
    }.padding(20).frame(width: 320).background { PaperGlassSurface() }.foregroundStyle(Enki.ink)
      .buttonStyle(
        ActionLink())
  }
  private func move(_ amount: Int) {
    month = calendar.date(byAdding: .month, value: amount, to: first)!
  }
}

struct PaperTextEditor: View {
  @Binding var text: String
  var body: some View {
    TextEditor(text: $text).font(.custom("Inter-Regular", size: 13))
      .scrollContentBackground(.hidden).padding(6).background(Enki.paper)
  }
}

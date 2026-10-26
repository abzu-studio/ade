import SwiftUI

/// A focused native command surface. No data mutation occurs while searching or navigating.
struct QuickOpen: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @FocusState private var searching: Bool
  @State private var query = ""
  @State private var selected = ""
  @State private var person: Person?
  private enum Destination {
    case section(AppSection), space(String), event(String), person(Person)
  }
  private struct Item: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let destination: Destination
  }
  private var items: [Item] {
    var items: [Item] = []
    if model.space != nil {
      items += AppSection.allCases.map {
        Item(id: "section-" + $0.id, title: $0.title(model), detail: model.t("Sección", "Section"),
             symbol: "rectangle.split.2x1", destination: .section($0))
      }
    }
    items += model.database.spaces.compactMap { branch in
      guard let space = branch.visible?.data else { return nil }
      return Item(id: "space-" + space.id, title: space.name, detail: model.t("Espacio", "Space"),
                  symbol: "square.stack", destination: .space(space.id))
    }
    if let space = model.space, !query.isEmpty {
      items += space.events.map {
        Item(id: "event-" + $0.id, title: $0.name,
             detail: model.t("Evento", "Event") + " · " + $0.date + " · " + model.status($0.status.rawValue),
             symbol: "calendar", destination: .event($0.id))
      }
      items += space.people.map {
        Item(id: "person-" + $0.id, title: $0.name,
             detail: model.t("Asistencia individual", "Individual attendance"),
             symbol: "person", destination: .person($0))
      }
    }
    let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
    return Array(items.filter { item in
      words.allSatisfy { (item.title + " " + item.detail).localizedStandardContains($0) }
    }.prefix(60))
  }
  var body: some View {
    let matches = items
    let active = matches.contains { $0.id == selected } ? selected : matches.first?.id ?? ""
    return VStack(spacing: 0) {
      HStack(spacing: 14) {
        Image(systemName: "magnifyingglass").foregroundStyle(Enki.accent)
        TextField(model.t("Ir a una sección, evento o persona…", "Go to a section, event or person…"), text: $query)
          .textFieldStyle(.plain).font(.custom("Inter-Regular", size: 17))
          .focused($searching).accessibilityIdentifier("quick-open-search")
          .onSubmit { activateSelected() }
        Button(model.t("Cerrar", "Close")) { dismiss() }.buttonStyle(ActionLink()).keyboardShortcut(.cancelAction)
      }.padding(22)
      PaperRule(strong: true)
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 0) {
            if matches.isEmpty {
              Text(model.t("Sin coincidencias", "No matches"))
                .foregroundStyle(.secondary).padding(36)
            }
            ForEach(matches) { item in
              Button { activate(item) } label: {
                HStack(spacing: 14) {
                  Image(systemName: item.symbol).frame(width: 22).foregroundStyle(Enki.accent)
                  VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.custom(Enki.condensed, size: 22))
                    Text(item.detail).font(.custom(Enki.mono, size: 9)).foregroundStyle(.secondary)
                  }
                  Spacer()
                  if item.id == active { Image(systemName: "return").foregroundStyle(Enki.accent) }
                }.padding(.horizontal, 22).padding(.vertical, 11)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .background(item.id == active ? Enki.accent.opacity(0.09) : .clear)
                  .contentShape(Rectangle())
              }.buttonStyle(.plain).id(item.id)
                .accessibilityIdentifier("quick-open-" + item.id)
              PaperRule()
            }
          }
        }.onChange(of: active) { proxy.scrollTo(active, anchor: .center) }
      }
      PaperRule()
      HStack {
        MicroLabel(text: model.t("↑ ↓ ELEGIR · ↵ ABRIR · ESC CERRAR", "↑ ↓ SELECT · ↵ OPEN · ESC CLOSE"))
        Spacer()
        Text("⌘K").font(.custom(Enki.mono, size: 10))
      }.foregroundStyle(.secondary).padding(16)
    }.frame(width: 660, height: 510).background { PaperGlassSurface() }
      .foregroundStyle(Enki.ink)
      .defaultFocus($searching, true)
      .onAppear { searching = true }
      .onChange(of: query) { selected = "" }
      .onKeyPress(.downArrow) { move(1); return .handled }
      .onKeyPress(.upArrow) { move(-1); return .handled }
      .sheet(item: $person) { PersonParticipationView(personID: $0.id) }
  }
  private var activeID: String { items.contains { $0.id == selected } ? selected : items.first?.id ?? "" }
  private func move(_ offset: Int) {
    let matches = items
    guard !matches.isEmpty else { return }
    let index = matches.firstIndex { $0.id == activeID } ?? 0
    selected = matches[min(matches.count - 1, max(0, index + offset))].id
  }
  private func activateSelected() {
    if let item = items.first(where: { $0.id == activeID }) { activate(item) }
  }
  private func activate(_ item: Item) {
    switch item.destination {
    case .section(let section): model.navigate(section)
    case .space(let id): model.openSpace(id)
    case .event(let id): model.openEvent(id)
    case .person(let value): person = value; return
    }
    dismiss()
  }
}

import SwiftUI

struct SpacesHomeView: View {
  @Environment(AppModel.self) private var m
  @State private var name = ""
  var advanced: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        MicroLabel(text: m.t("ADÊ · LOCAL EN ESTA MAC", "ADÊ · LOCAL ON THIS MAC"))
        Spacer()
        DayThemeChooser()
        Button(m.t("Importar…", "Import…")) { Task { await m.importWorkspace() } }
          .buttonStyle(ActionLink()).disabled(m.unreadable || m.busy || m.pending != nil)
      }.padding(.bottom, 42)
      HStack(alignment: .top, spacing: 58) {
        VStack(alignment: .leading, spacing: 18) {
          Text("ADÊ").font(.custom(Enki.display, size: 112)).foregroundStyle(Enki.brand)
            .accessibilityAddTraits(.isHeader)
          Text(
            m.t(
              "Espacios, eventos, asistencia, voluntariado y documentos.",
              "Spaces, events, attendance, volunteering and documents.")
          )
          .font(.custom("Inter-Regular", size: 14)).foregroundStyle(.secondary).lineSpacing(4)
          MicroLabel(text: m.t("Nuevo espacio", "New space")).padding(.top, 36)
          TextField(m.t("NOMBRE DEL ESPACIO…", "SPACE NAME…"), text: $name)
            .textFieldStyle(PaperFieldStyle()).font(.custom(Enki.condensed, size: 23))
            .accessibilityIdentifier("space-name").onSubmit { create() }
          HStack {
            Button(m.t("Crear espacio", "Create space"), action: create)
              .buttonStyle(DayPrimaryButton()).accessibilityIdentifier("space-create")
              .disabled(
                name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || m.busy
                  || m.unreadable || m.pending != nil)
            #if DEBUG
            Button(m.t("Cargar demo", "Load demo")) { Task { await m.loadDemo() } }
              .buttonStyle(ActionLink()).accessibilityIdentifier("load-demo")
              .disabled(m.busy || m.unreadable || m.pending != nil)
            #endif
          }
          Button(m.t("Opciones de creación…", "Creation options…"), action: advanced)
            .buttonStyle(ActionLink()).accessibilityIdentifier("new-space").disabled(
              m.busy || m.unreadable)
          Text(
            m.t(
              "Los espacios se guardan en este Mac. Puedes exportarlos desde Datos.",
              "Spaces are saved on this Mac. Export them from Data.")
          )
          .font(.caption).foregroundStyle(.secondary).lineSpacing(3)
        }.frame(width: 300)
        VStack(alignment: .leading, spacing: 12) {
          MicroLabel(text: "[ \(m.database.spaces.count) " + m.t("ESPACIOS", "SPACES") + " ]")
          Text(m.t("TUS ESPACIOS", "YOUR SPACES")).font(.custom(Enki.display, size: 34))
          PaperRule(strong: true)
          ScrollView {
            LazyVStack(spacing: 0) {
              ForEach(m.database.spaces) { branch in
                HStack(spacing: 16) {
                  VStack(alignment: .leading, spacing: 5) {
                    Text((branch.visible?.data.name ?? branch.id).uppercased())
                      .font(.custom(Enki.condensed, size: 24)).lineLimit(2)
                    MicroLabel(
                      text: "\(branch.visible?.data.people.count ?? 0) " + m.t("personas", "people")
                        + " · \(branch.visible?.data.events.count ?? 0) " + m.t("eventos", "events")
                    )
                  }
                  Spacer()
                  Button(m.t("Abrir →", "Open →")) { m.openSpace(branch.id) }
                    .buttonStyle(ActionLink()).accessibilityIdentifier("open-space-" + branch.id)
                }.padding(.vertical, 16)
                PaperRule()
              }
            }
          }
        }.frame(maxWidth: .infinity)
      }
      Spacer(minLength: 20)
    }.padding(.horizontal, 50).padding(.top, 22).padding(.bottom, 36)
      .foregroundStyle(Enki.ink).modifier(PaperArrival(trigger: "spaces"))
  }
  private func create() {
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    Task { if await m.createSpace(name: name, zone: "America/Puerto_Rico") { name = "" } }
  }
}
enum DateLabel {
  private static let lock = NSLock()
  private static var formats: [String: DateFormatter] = [:]
  static func short(_ value: String, locale: String, weekday: Bool = false) -> String {
    guard let date = Day.date(value) else { return value }
    let key = locale + (weekday ? "|w" : "|d")
    lock.lock()
    let format: DateFormatter
    if let cached = formats[key] {
      format = cached
    } else {
      let created = DateFormatter()
      created.locale = Locale(identifier: locale)
      created.timeZone = TimeZone(secondsFromGMT: 0)
      created.dateFormat = weekday ? "EEE dd MMM" : "dd MMM yyyy"
      formats[key] = created
      format = created
    }
    let text = format.string(from: date)
    lock.unlock()
    return text.replacingOccurrences(of: ".", with: "").uppercased()
  }
}
struct OverviewView: View {
  @Environment(AppModel.self) private var m
  var body: some View {
    if let s = m.space {
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
              MicroLabel(text: m.t("ESPACIO · RESUMEN", "SPACE · OVERVIEW"))
              Text(s.name.uppercased()).font(.custom(Enki.display, size: 44)).foregroundStyle(
                Enki.heading)
            }
            Spacer()
            Button(m.t("Exportar espacio", "Export space")) { m.exportWorkspace() }.buttonStyle(
              ActionLink())
            Button(m.t("+ Añadir evento", "+ Add event")) { m.navigate(.events) }.buttonStyle(
              DayPrimaryButton())
          }
          PaperRule(strong: true)
          Text(m.t("CICLO DE ACTIVIDAD", "ACTIVITY CYCLE")).font(.custom(Enki.condensed, size: 23))
          workflow(s)
          Text(m.t("CONTEOS", "COUNTS")).font(.custom(Enki.condensed, size: 23))
          HStack(spacing: 0) {
            metric(m.t("Personas", "People"), String(s.people.count))
            metric(m.t("Grupos", "Groups"), String(s.groups.count))
            metric(m.t("Períodos", "Periods"), String(s.periods.count))
            metric(m.t("Componentes", "Components"), String(s.components.count))
            metric(m.t("Eventos", "Events"), String(s.events.count))
            metric(m.t("Documentos", "Documents"), String(s.templates.count), last: true)
          }.padding(16).overlay { Rectangle().stroke(Enki.rule, lineWidth: 0.7) }
          let upcoming = next(s)
          HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 7) {
              MicroLabel(text: m.t("Siguiente paso", "Next step"))
              Text(upcoming.title.uppercased()).font(.custom(Enki.condensed, size: 24))
              MicroLabel(text: upcoming.detail)
            }
            Spacer()
            Button(upcoming.action + " →") {
              if let event = upcoming.event { m.openEvent(event) } else { m.navigate(upcoming.section) }
            }.buttonStyle(ActionLink())
          }.padding(.top, 8)
        }.padding(30)
      }
    }
  }
  private func metric(_ label: String, _ value: String, last: Bool = false) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        MicroLabel(text: label)
        Text(value).font(.custom(Enki.display, size: 38)).foregroundStyle(Enki.ink)
          .modifier(PaperNumber(value: value))
      }
      Spacer(minLength: 0)
    }.padding(.leading, last ? 16 : 0).frame(maxWidth: .infinity, alignment: .leading).overlay(
      alignment: .trailing
    ) { if !last { Rectangle().fill(Enki.rule).frame(width: 0.5).padding(.trailing, 16) } }
  }
  private struct Stage: Identifiable {
    var id: String
    var title: String
    var detail: String
    var level: Double
    var destination: AppSection
    var explanation: String
  }
  private func workflow(_ s: Space) -> some View {
    let result = m.participation()
    let eligible = s.events.filter { $0.canRecord && $0.countsForAttendance }
    let listed = eligible.reduce(0) { $0 + $1.participantIds.count }
    let stages = [
      Stage(
        id: "people", title: m.t("Personas", "People"),
        detail: "\(s.people.filter(\.active).count) " + m.t("activas", "active"),
        level: s.people.isEmpty
          ? 0 : Double(s.people.filter(\.active).count) / Double(s.people.count),
        destination: .people,
        explanation: m.t("Personas activas / personas registradas", "Active / registered people")),
      Stage(
        id: "classification", title: m.t("Componentes", "Components"),
        detail: "\(s.components.count) · \(s.categories.count) " + m.t("categorías", "categories"),
        level: s.components.isEmpty ? 0 : 1, destination: .classification,
        explanation: m.t("Hay clasificación disponible", "Classification is available")),
      Stage(
        id: "events", title: m.t("Eventos", "Events"),
        detail: "\(s.events.count) " + m.t("creados", "created"),
        level: s.events.isEmpty
          ? 0 : Double(s.events.filter(\.canRecord).count) / Double(s.events.count),
        destination: .events,
        explanation: m.t("Programados o completados / eventos", "Scheduled or completed / events")),
      Stage(
        id: "volunteers", title: m.t("Voluntarios", "Volunteers"),
        detail: "\(s.volunteers.filter { $0.status.occupiesSeat }.count) "
          + m.t("selecciones", "selections"),
        level: s.events.reduce(0, { $0 + $1.volunteerCapacity }) == 0
          ? 0
          : Double(s.volunteers.filter { $0.status.occupiesSeat }.count)
            / Double(s.events.reduce(0, { $0 + $1.volunteerCapacity })), destination: .events,
        explanation: m.t(
          "Plazas ocupadas / cupo de voluntariado", "Occupied / available volunteer places")),
      Stage(
        id: "attendance", title: m.t("Asistencia", "Attendance"),
        detail: "\(result.denominator) " + m.t("evaluables", "eligible"),
        level: listed == 0 ? 0 : Double(result.denominator) / Double(listed), destination: .events,
        explanation: m.t(
          "Marcas presente o ausente / plazas de eventos evaluables",
          "Present or absent records / eligible event roster places")),
      Stage(
        id: "results", title: m.t("Participación", "Participation"), detail: result.formatted,
        level: (result.percentage ?? 0) / 100, destination: .results,
        explanation: m.t("Presentes / (presentes + ausentes)", "Present / (present + absent)")),
      Stage(
        id: "documents", title: m.t("Documentos", "Documents"),
        detail: "\(s.templates.count) " + m.t("plantillas", "templates"),
        level: s.templates.isEmpty ? 0 : 1, destination: .documents,
        explanation: m.t("Hay plantillas disponibles", "Templates are available")),
    ]
    return HStack(spacing: 8) {
      ForEach(stages) { item in
        Button {
          m.navigate(item.destination)
        } label: {
          VStack(alignment: .leading, spacing: 9) {
            Text(item.title.uppercased()).font(.custom(Enki.condensed, size: 17)).lineLimit(2)
              .minimumScaleFactor(0.8)
            Text(item.detail.uppercased()).font(.custom(Enki.mono, size: 8)).foregroundStyle(
              .secondary
            ).lineLimit(2)
            Spacer()
          }.padding(10).frame(
            maxWidth: .infinity, minHeight: 140, maxHeight: 140, alignment: .leading
          )
          .background(alignment: .bottom) {
            Rectangle().fill(Enki.atmosphere.opacity(0.24)).frame(
              height: max(0, min(1, item.level)) * 55
            )
            .overlay(alignment: .top) {
              Rectangle().fill(Enki.atmosphere.opacity(0.4)).frame(height: 1)
            }
          }.overlay { Rectangle().stroke(Enki.rule, lineWidth: 0.7) }
        }.buttonStyle(.plain).help(item.explanation)
          .accessibilityLabel(item.title + ": " + item.detail + ". " + item.explanation)
      }
    }
  }
  private struct Next {
    var title: String
    var detail: String
    var action: String
    var section: AppSection
    var event: String?
  }
  private func next(_ s: Space) -> Next {
    if s.people.isEmpty {
      return Next(
        title: m.t("Inscribir personas", "Add people"),
        detail: m.t("Construye la lista de tu espacio", "Build your workspace roster"),
        action: m.t("Inscribir", "Add"), section: .people)
    }
    if s.components.isEmpty {
      return Next(
        title: m.t("Crear el primer componente", "Create the first component"),
        detail: m.t("Clasifica tus actividades", "Classify your activities"),
        action: m.t("Crear", "Create"), section: .classification)
    }
    if let e = s.events.first(where: { $0.status == .draft }) {
      return Next(
        title: m.t("Programar “", "Schedule “") + e.name + "”",
        detail: m.status(e.status.rawValue)
          + " · \(e.date) · \(e.participantIds.count)/\(e.capacity)",
        action: m.t("Programar", "Schedule"), section: .events, event: e.id)
    }
    if let e = s.events.filter({ $0.status == .scheduled }).sorted(by: {
      $0.date + $0.time < $1.date + $1.time
    }).first {
      return Next(
        title: m.t("Preparar “", "Prepare “") + e.name + "”",
        detail: "\(e.date) · \(e.participantIds.count)/\(e.capacity)", action: m.t("Abrir", "Open"),
        section: .events, event: e.id)
    }
    if !s.events.isEmpty {
      return Next(
        title: m.t("Generar un documento", "Generate a document"),
        detail: m.t("Usa la participación registrada", "Use recorded participation"),
        action: m.t("Crear PDF", "Create PDF"), section: .documents)
    }
    return Next(
      title: m.t("Crear el primer evento", "Create the first event"),
      detail: m.t("Fecha · componente · participantes", "Date · component · participants"),
      action: m.t("Crear", "Create"), section: .events)
  }
}
struct HistoryRail: View {
  @Environment(AppModel.self) private var m
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      MicroLabel(text: m.t("Historial", "History")).padding(.bottom, 10)
      PaperRule()
      ForEach(Array((m.branch?.revisions ?? []).suffix(5).reversed())) { r in
        VStack(alignment: .leading, spacing: 6) {
          MicroLabel(text: DateLabel.short(String(r.timestamp.prefix(10)), locale: m.locale))
          Text(r.label).font(.system(size: 11)).lineLimit(3)
        }.padding(.vertical, 14)
        PaperRule()
      }
      Spacer(minLength: 20)
      Button(m.t("Ver historial →", "View history →")) { m.navigate(.history) }.buttonStyle(
        ActionLink())
    }.padding(22).frame(maxHeight: .infinity).background { PaperGlassSurface(tint: Enki.side) }
      .overlay(alignment: .leading) {
        Rectangle().fill(Enki.rule).frame(width: 0.5)
      }
  }
}

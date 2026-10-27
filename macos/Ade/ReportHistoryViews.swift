import SwiftUI

struct ResultRow: Identifiable {
  var id: String
  var name: String
  var active: Bool
  var result: Participation
}
struct ResultsView: View {
  @Environment(AppModel.self) private var m
  @State private var filter = ReportFilter()
  @State private var search = ""
  @State private var attendancePerson: Person?
  @State private var computedRows: [ResultRow] = []
  @State private var calculating = false
  @State private var computedRequest: Request?
  private struct Request: Hashable {
    let space: String
    let heads: [String]
    let filter: ReportFilter
  }
  private var request: Request {
    Request(space: m.selectedSpace, heads: m.branch?.heads ?? [], filter: filter)
  }
  var body: some View {
    VStack(spacing: 0) {
      PageHeading(title: m.t("Resultados", "Results"), subtitle: m.space?.name ?? "") {
        Button(m.t("Exportar CSV…", "Export CSV…")) { export() }.buttonStyle(ActionLink()).disabled(calculating || computedRequest != request)
      }
      if let s = m.space {
        VStack(alignment: .leading, spacing: 14) {
          HStack {
            PaperPicker(
              m.t("Período", "Period"), selection: $filter.periodId,
              options: [PaperOption("", m.t("Todos", "All"))]
                + (s.periods).map { PaperOption($0.id, $0.name) })
            PaperPicker(
              m.t("Grupo", "Group"), selection: $filter.groupId,
              options: [PaperOption("", m.t("Todos", "All"))]
                + (s.groups).map { PaperOption($0.id, $0.name) })
          }
          HStack {
            PaperPicker(
              m.t("Componente", "Component"), selection: $filter.componentId,
              options: [PaperOption("", m.t("Todos", "All"))]
                + (s.components).map { PaperOption($0.id, $0.name) }
            ).onChange(of: filter.componentId) { filter.categoryId = "" }
            PaperPicker(
              m.t("Categoría", "Category"), selection: $filter.categoryId,
              options: [PaperOption("", m.t("Todas", "All"))]
                + (s.categories.filter {
                  filter.componentId.isEmpty || $0.componentId == filter.componentId
                }).map { PaperOption($0.id, $0.name) })
            PaperPicker(
              m.t("Evento", "Event"), selection: $filter.eventId,
              options: [PaperOption("", m.t("Todos", "All"))]
                + (s.events).map { PaperOption($0.id, $0.name) })
          }
          Text(
            m.t(
              "Porcentaje = presentes / (presentes + ausentes). Se excluyen pendientes, excusados, borradores, cancelados y eventos que no cuentan. Solo se evalúa a las personas de la lista; el grupo se comprueba en la fecha de cada evento. — significa sin denominador.",
              "Percentage = present / (present + absent). Pending, excused, draft, cancelled and non-counting events are excluded. Only listed participants count; group membership is evaluated on each event date. — means no denominator."
            )
          ).font(.callout).foregroundStyle(.secondary)
          TextField(m.t("Buscar persona", "Search people"), text: $search).textFieldStyle(
            PaperFieldStyle())
        }.padding(.horizontal, 28).padding(.bottom, 18)
        ScrollView {
          LazyVStack(spacing: 0) {
            HStack {
              MicroLabel(text: m.t("Persona", "Person")).frame(
                maxWidth: .infinity, alignment: .leading)
              ForEach(
                [
                  m.t("Presente", "Present"), m.t("Ausente", "Absent"), m.t("Excusado", "Excused"),
                  m.t("Pendiente", "Pending"), m.t("Excluido", "Excluded"), "%",
                ], id: \.self
              ) { title in
                Text(title.uppercased()).font(.custom(Enki.mono, size: 8)).frame(width: 68)
              }
            }.padding(.vertical, 12)
            PaperRule(strong: true)
            if calculating {
              ProgressView(m.t("Calculando participación…", "Calculating participation…"))
                .padding(24).frame(maxWidth: .infinity)
            } else if rows.isEmpty {
              Text(m.t("No hay personas que coincidan con la búsqueda.", "No people match your search."))
                .foregroundStyle(.secondary).padding(24)
            }
            ForEach(rows) { row in
              HStack {
                Button {
                  attendancePerson = s.person(row.id)
                } label: {
                  Text(row.name + (row.active ? "" : " · " + m.t("Inactivo", "Inactive")) + " →")
                    .font(.custom(Enki.condensed, size: 21)).frame(
                      maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).accessibilityIdentifier("result-person-" + row.id)
                Text(String(row.result.present)).frame(width: 68)
                Text(String(row.result.absent)).frame(width: 68)
                Text(String(row.result.excused)).frame(width: 68)
                Text(String(row.result.pending)).frame(width: 68)
                Text(String(row.result.excluded)).frame(width: 68)
                Text(row.result.formatted).foregroundStyle(Enki.accent).frame(width: 68)
              }.font(.custom(Enki.mono, size: 12)).padding(.vertical, 15).modifier(PaperHover())
              PaperRule()
            }
          }.padding(.horizontal, 28)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }.task(id: request) {
      let requested = request
      guard let space = m.space else { computedRows = []; computedRequest = nil; calculating = false; return }
      calculating = true
      computedRows = []
      computedRequest = nil
      do {
        let results = try await m.store.report(space, filter: requested.filter)
        guard !Task.isCancelled, request == requested else { return }
        computedRows = space.people.map { person in
          ResultRow(id: person.id, name: person.name, active: person.active,
                    result: results[person.id] ?? Participation())
        }
        computedRequest = requested
      } catch {
        guard !Task.isCancelled, request == requested else { return }
        m.error = m.explain(error)
      }
      calculating = false
    }.sheet(item: $attendancePerson) { PersonParticipationView(personID: $0.id) }
      .onChange(of: m.selectedSpace) {
        filter = ReportFilter()
        search = ""
      }
      .onChange(of: m.branch?.heads) {
        guard let s = m.space else {
          filter = ReportFilter()
          return
        }
        if !s.periods.contains(where: { $0.id == filter.periodId }) { filter.periodId = "" }
        if !s.groups.contains(where: { $0.id == filter.groupId }) { filter.groupId = "" }
        if !s.components.contains(where: { $0.id == filter.componentId }) {
          filter.componentId = ""
        }
        if !s.categories.contains(where: { $0.id == filter.categoryId }) { filter.categoryId = "" }
        if !s.events.contains(where: { $0.id == filter.eventId }) { filter.eventId = "" }
      }
  }
  private var rows: [ResultRow] {
    guard computedRequest == request else { return [] }
    return computedRows.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
  }
  private func export() {
    guard !calculating, computedRequest == request else { return }
    func cell(_ value: String) -> String {
      let safe = ["=", "+", "-", "@"].contains(String(value.prefix(1))) ? "'" + value : value
      return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    let header = "Person,Present,Absent,Excused,Pending,Excluded,Percentage,Revision\n"
    let csv =
      header
      + rows.map { r in
        [
          r.name, String(r.result.present), String(r.result.absent), String(r.result.excused),
          String(r.result.pending), String(r.result.excluded), r.result.formatted,
          m.branch?.heads.first ?? "",
        ].map(cell).joined(separator: ",")
      }.joined(separator: "\n")
    do {
      try Panels.save(Data(csv.utf8), name: "Ade-resultados.csv", type: .commaSeparatedText)
    } catch { m.error = m.explain(error) }
  }
}
struct HistoryView: View {
  @Environment(AppModel.self) private var m
  @State private var selected: String?
  @State private var confirm: Revision?
  var body: some View {
    VStack(spacing: 0) {
      PageHeading(title: m.t("Historial", "History"), subtitle: m.space?.name ?? "") {
        Button(m.t("Importar…", "Import…")) { Task { await m.importWorkspace() } }.buttonStyle(
          ActionLink()
        ).disabled(m.busy || m.pending != nil)
        Button(m.t("Exportar archivo…", "Export workspace…")) { m.exportWorkspace() }.buttonStyle(
          ActionLink())
      }
      HStack(spacing: 0) {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach((m.branch?.revisions ?? []).reversed()) { r in
              PaperSelectionRow(selected: selected == r.id, action: { selected = r.id }) {
                VStack(alignment: .leading, spacing: 6) {
                  HStack {
                    Text(r.label).font(.custom(Enki.condensed, size: 21))
                    if m.branch?.heads.contains(r.id) == true {
                      Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(
                        Enki.accent)
                    }
                  }
                  Text(r.author).font(.caption)
                  Text(r.timestamp).font(.custom(Enki.mono, size: 9)).foregroundStyle(.secondary)
                }
              }
            }
          }
        }.frame(width: 270).frame(maxHeight: .infinity)
        Rectangle().fill(Enki.rule).frame(width: 0.5)
        if let r = m.branch?.revisions.first(where: { $0.id == selected }) {
          VStack(alignment: .leading, spacing: 16) {
            Text(r.label).font(.custom(Enki.condensed, size: 28))
            Text("\(r.author) · \(r.timestamp)").foregroundStyle(.secondary)
            Text(
              "\(r.data.people.count) " + m.t("personas", "people") + " · \(r.data.events.count) "
                + m.t("eventos", "events") + " · \(r.data.attendance.count) "
                + m.t("asistencias", "attendance records"))
            HStack {
              Button(
                m.branch?.conflicted == true
                  ? m.t("Elegir esta versión…", "Choose this version…")
                  : m.t("Restaurar esta revisión…", "Restore this revision…")
              ) { confirm = r }.disabled(m.busy || m.pending != nil)
              Button(m.t("Exportar revisión…", "Export revision…")) { exportRevision(r) }
            }
            Text(
              m.t(
                "Cada restauración añade una revisión. Las versiones anteriores permanecen disponibles.",
                "Every restore adds a revision. Previous versions remain available.")
            ).font(.callout).foregroundStyle(.secondary)
            ScrollView([.horizontal, .vertical]) {
              RevisionDataView(revision: r, store: m.store)
                .font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(
                  maxWidth: .infinity, alignment: .leading
                ).padding()
            }.background(Enki.rule.opacity(0.2))
          }.padding(24).frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
        } else {
          EmptyState(
            title: m.t("Cambios recuperables", "Recoverable changes"),
            detail: m.t(
              "Selecciona una revisión para examinar sus datos completos. Los puntos marcan las versiones actuales.",
              "Select a revision to inspect its full data. Dots mark current versions."))
        }
      }
    }.onChange(of: m.selectedSpace) { selected = nil }
      .confirmationDialog(
        m.t(
          "¿Usar esta revisión como versión actual?", "Use this revision as the current version?"),
        isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
        titleVisibility: .visible
      ) {
        if let r = confirm {
          Button(m.t("Restaurar conservando el historial", "Restore and preserve history")) {
            Task { await m.restore(r) }
            confirm = nil
          }
        }
      } message: {
        Text(
          m.t(
            "Las demás versiones se conservarán y podrán recuperarse.",
            "Other versions will remain recoverable."))
      }
  }
  private func exportRevision(_ r: Revision) {
    guard let b = m.branch else { return }
    var ancestors = Set([r.id])
    var progress = true
    while progress {
      let before = ancestors.count
      for rev in b.revisions where ancestors.contains(rev.id) { ancestors.formUnion(rev.parents) }
      progress = before != ancestors.count
    }
    let db = Database(spaces: [
      Branch(id: b.id, revisions: b.revisions.filter { ancestors.contains($0.id) }, heads: [r.id])
    ])
    do { try Panels.save(WorkspaceCodec.encode(db), name: "Ade-revision.json", type: .json) } catch
    { m.error = m.explain(error) }
  }
}
struct SettingsView: View {
  @Environment(AppModel.self) private var m
  @AppStorage("ade-ambient-motion") private var ambientMotion = true
  @State private var name = ""
  @State private var zone = ""
  var body: some View {
    @Bindable var model = m
    VStack(spacing: 0) {
      PageHeading(title: m.t("Configuración", "Settings"), subtitle: "Adê · " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.4.0")) { EmptyView() }
      ScrollView {
        PaperForm {
          PaperSection(m.t("Apariencia · día y noche", "Appearance · day and night")) {
            DayThemeChooser()
            Text(
              m.t(
                "El icono del Dock acompaña al tema mientras Adê está abierta.",
                "The Dock icon follows the theme while Adê is open.")
            ).font(.caption).foregroundStyle(.secondary)
          }
          PaperSection(m.t("Preferencias", "Preferences")) {
            Toggle(m.t("Ambiente animado", "Animated atmosphere"), isOn: $ambientMotion)
              .accessibilityIdentifier("ambient-motion")
            Text(
              m.t(
                "Una trama de agua acompaña los cuatro temas. Respeta los ajustes de accesibilidad y se pausa en segundo plano.",
                "A flowing halftone accompanies all four themes. Respects accessibility settings and pauses in the background."
              )
            )
            .font(.caption).foregroundStyle(.secondary)
            Button(m.t("Repetir apertura audiovisual →", "Replay audiovisual opening →")) {
              m.welcomeRequested = true
            }
            .accessibilityIdentifier("replay-welcome")
            PaperPicker(
              m.t("Idioma", "Language"), selection: $model.locale,
              options: [PaperOption("es", "Español"), PaperOption("en", "English")])
            PaperInput(m.t("Autor de los cambios", "Revision author")) {
              TextField(m.t("Autor de los cambios", "Revision author"), text: $model.author)
            }
          }
          PaperSection(m.t("Espacio actual", "Current space")) {
            PaperInput(m.t("Nombre", "Name")) {
              TextField(m.t("Nombre", "Name"), text: $name).accessibilityIdentifier(
                "settings-space-name")
            }
            PaperInput(m.t("Zona horaria IANA", "IANA time zone")) {
              TextField(m.t("Zona horaria IANA", "IANA time zone"), text: $zone)
            }
            Button(m.t("Guardar espacio", "Save space")) {
              Task {
                _ = await m.edit(
                  .settings(name, zone),
                  label: m.t("Configuración del espacio", "Space settings"))
              }
            }.disabled(!m.canEdit)
          }
          PaperSection(m.t("Archivo local", "Local workspace")) {
            Button(
              m.t("Exportar todos los espacios e historial…", "Export all spaces and history…")
            ) { m.exportWorkspace() }
            Button(m.t("Importar y combinar versiones…", "Import and merge versions…")) {
              Task { await m.importWorkspace() }
            }.disabled(m.busy || m.pending != nil)
            Button(
              m.t("Exportar copia de recuperación anterior…", "Export previous recovery backup…")
            ) { Task { await m.recoverBackup() } }
            Button(m.t("Recargar archivo local", "Reload local workspace")) {
              Task { await m.load() }
            }.disabled(m.busy || m.pending != nil)
            Text(
              m.t(
                "Adê guarda los datos en su contenedor local. La colaboración funciona intercambiando archivos: si dos personas editan desde la misma revisión, ambas versiones se conservan para resolverlas manualmente.",
                "Adê stores data in its local container. Collaboration uses exchanged files: when two people edit the same revision, both versions are preserved for manual resolution."
              )
            ).foregroundStyle(.secondary)
          }
          PaperSection("ENKI · ASTRAL PAPER") {
            Text(
              m.t(
                "Índigo y Grafito, de día y de noche. Tipografía condensada, textura y movimiento opcional.",
                "Indigo and Graphite, by day and by night. Condensed typography, texture and optional motion."
              ))
            Text("Barlow Condensed · IBM Plex Mono · Inter").font(.custom(Enki.mono, size: 11))
          }
        }.padding(32)
      }
    }.onAppear {
      name = m.space?.name ?? ""
      zone = m.space?.timeZone ?? ""
    }.onChange(of: m.selectedSpace) {
      name = m.space?.name ?? ""
      zone = m.space?.timeZone ?? ""
    }
  }
}

private struct RevisionDataView: View {
  let revision: Revision
  let store: LocalStore
  @State private var text = ""
  var body: some View {
    Text(text).task(id: revision.id) {
      text = ""
      let value = (try? await store.revisionText(revision.data)) ?? ""
      guard !Task.isCancelled else { return }
      text = value
    }
  }
}

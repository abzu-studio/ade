import SwiftUI

struct EventsView: View {
  @Environment(AppModel.self) private var m
  @State private var draft: Activity?
  @State private var quickName = ""
  @State private var query = ""
  @State private var status: EventStatus?
  var body: some View {
    Group {
      if let id = m.selectedEvent, let event = m.space?.event(id) {
        EventDetail(event: event, edit: { draft = event }).id(event.id)
      } else {
        VStack(alignment: .leading, spacing: 0) {
          HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 9) {
              MicroLabel(
                text: m.space?.periods.first(where: { $0.start <= Day.today && $0.end >= Day.today }
                )?.name ?? m.space?.name ?? "")
              Text(m.t("EVENTOS", "EVENTS")).font(.custom(Enki.display, size: 48)).foregroundStyle(
                Enki.heading)
            }
            Spacer(minLength: 30)
            Button(m.t("+ Añadir evento", "+ Add event"), action: newEvent)
              .buttonStyle(DayPrimaryButton()).accessibilityIdentifier("event-new").disabled(
                !m.canEdit)
          }.padding(.top, 22).padding(.bottom, 8)
          PaperRule(strong: true).padding(.vertical, 12)
          HStack(spacing: 0) {
            filterButton(nil)
            ForEach(EventStatus.allCases, id: \.rawValue) { filterButton($0) }
            Spacer(minLength: 0)
            TextField(m.t("Filtrar…", "Filter…"), text: $query).textFieldStyle(.plain).font(
              .custom(Enki.mono, size: 9)
            ).padding(9).frame(width: 190).overlay { Rectangle().stroke(Enki.rule, lineWidth: 0.7) }
          }.padding(.bottom, 12)
          PaperRule(strong: true)
          ScrollView {
            LazyVStack(spacing: 0) { ForEach(events) { eventRow($0) } }

            if events.isEmpty {
              let none = m.space?.events.isEmpty != false
              VStack(alignment: .leading, spacing: 12) {
                Text(none ? m.t("SIN EVENTOS", "NO EVENTS") : m.t("SIN COINCIDENCIAS", "NO MATCHES"))
                  .font(.custom(Enki.display, size: 24))
                Text(
                  none
                    ? m.t(
                      "Crea un evento con su componente, fecha y participantes.",
                      "Create an event with its component, date and participants.")
                    : m.t(
                      "Ningún evento coincide con este filtro.",
                      "No event matches this filter.")
                ).font(.callout).foregroundStyle(.secondary)
                if !none {
                  Button(m.t("Limpiar filtro", "Clear filter")) {
                    query = ""
                    status = nil
                  }.buttonStyle(ActionLink())
                }
              }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 40)
            }
          }
        }.padding(.horizontal, 32)
      }
    }.modifier(PaperArrival(trigger: m.selectedEvent ?? "events"))
      .sheet(item: $draft) {
        EventEditor(
          value: $0,
          onSaved: {
            m.openEvent($0)
            quickName = ""
          })
      }
  }
  private func newEvent() {
    var e = Activity()
    e.name = quickName
    e.componentId = m.space?.components.first?.id ?? ""
    draft = e
  }
  private var events: [Activity] {
    (m.space?.events ?? []).filter {
      (status == nil || $0.status == status)
        && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query))
    }.sorted {
      let a = ($0.status == .draft || $0.status == .scheduled) ? 0 : $0.status == .completed ? 1 : 2
      let b = ($1.status == .draft || $1.status == .scheduled) ? 0 : $1.status == .completed ? 1 : 2
      if a != b { return a < b }
      return a == 0 ? $0.date + $0.time < $1.date + $1.time : $0.date + $0.time > $1.date + $1.time
    }
  }
  private func filterButton(_ value: EventStatus?) -> some View {
    let count = (m.space?.events ?? []).filter { value == nil || $0.status == value }.count
    return Button {
      status = value
    } label: {
      Text(
        (value.map { m.status($0.rawValue) } ?? m.t("Todos", "All")).uppercased() + " · \(count)"
      ).font(.custom(Enki.mono, size: 9)).tracking(1.1).padding(.bottom, 4).foregroundStyle(
        status == value ? Enki.paper : Enki.ink.opacity(0.65)
      ).padding(.horizontal, 9).padding(.top, 8).padding(.bottom, 4)
        .background(status == value ? Enki.ink : .clear)
        .overlay { Rectangle().stroke(Enki.rule, lineWidth: 0.5) }
    }.buttonStyle(.plain)
  }
  private func eventRow(_ e: Activity) -> some View {
    HStack(spacing: 20) {
      VStack(alignment: .leading, spacing: 2) {
        MicroLabel(text: DateLabel.short(e.date, locale: m.locale, weekday: true))
        MicroLabel(text: e.time)
      }.frame(width: 114, alignment: .leading)
      Button {
        m.openEvent(e.id)
      } label: {
        VStack(alignment: .leading, spacing: 6) {
          Text(e.name.uppercased()).font(.custom(Enki.condensed, size: 22)).strikethrough(
            e.status == .cancelled
          ).lineLimit(2)
          Text(classification(e).uppercased()).font(.custom(Enki.mono, size: 7)).tracking(1.1)
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
      }.buttonStyle(.plain).accessibilityLabel(e.name).accessibilityIdentifier("event-row-" + e.id)
      HStack(alignment: .firstTextBaseline, spacing: 2) {
        Text(String(e.participantIds.count)).font(.custom(Enki.condensed, size: 22))
          .foregroundStyle(
            Enki.accent)
        Text("/\(e.capacity)").font(.custom(Enki.mono, size: 8))
      }.frame(width: 70, alignment: .leading)
      StatusStamp(
        text: m.status(e.status.rawValue), filled: e.status == .completed,
        muted: e.status == .cancelled, dashed: e.status == .draft,
        angle: e.status == .draft || e.status == .cancelled ? 0 : -4
      ).frame(width: 130)
      Button(actionLabel(e)) {
        if e.status == .completed {
          m.documentEvent = e.id
          m.navigate(.documents)
        } else {
          m.openEvent(e.id, tab: isVolunteer(e) ? 1 : 0)
        }
      }.buttonStyle(ActionLink()).frame(width: 172, alignment: .trailing)
    }.foregroundStyle(Enki.ink).opacity(
      e.status == .cancelled ? 0.48 : e.status == .draft ? 0.7 : 1
    ).padding(.vertical, 10)
      .overlay(alignment: .bottom) { PaperRule() }
      .modifier(PaperHover())
  }
  private func classification(_ e: Activity) -> String {
    let s = m.space
    let c = s?.components.first { $0.id == e.componentId }?.name ?? ""
    let cat = s?.categories.first { $0.id == e.categoryId }?.name
    return c + (cat.map { " · " + $0 } ?? "")
  }
  private func isVolunteer(_ e: Activity) -> Bool {
    m.space?.components.first { $0.id == e.componentId }?.name.localizedCaseInsensitiveContains(
      "volunt") == true
  }
  private func actionLabel(_ e: Activity) -> String {
    switch e.status {
    case .draft: m.t("Programar →", "Schedule →")
    case .completed: m.t("Ver PDF →", "View PDF →")
    case .cancelled: m.t("Ver detalle", "View details")
    case .scheduled:
      isVolunteer(e)
        ? m.t("Sugerir voluntarios →", "Suggest volunteers →")
        : m.t("Abrir asistencia →", "Open attendance →")
    }
  }
}
struct EventDetail: View {
  @Environment(AppModel.self) private var m
  var event: Activity
  var edit: () -> Void
  @State private var duplicate = false
  @State private var showingActions = false
  @State private var confirmDelete = false
  @State private var duplicateDay = Day.today
  @State private var eventHistory: [Revision] = []
  @State private var eventHistoryKey = ""
  var body: some View {
    HStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 0) {
        HStack {
          MicroLabel(
            text: "[ " + DateLabel.short(event.date, locale: m.locale, weekday: true) + " · "
              + event.time + " · "
              + (m.space?.components.first { $0.id == event.componentId }?.name ?? "") + " ]")
          Spacer()

        }.padding(.top, 22).padding(.bottom, 5)
        HStack(alignment: .center) {
          Text(event.name.uppercased()).font(.custom(Enki.display, size: 40)).foregroundStyle(
            Enki.heading
          ).lineLimit(2).accessibilityLabel(event.name)
          Spacer()
          actions
        }.padding(.bottom, 10)
        HStack(spacing: 8) {
          Text(
            event.countsForAttendance
              ? m.t("CUENTA PARA ASISTENCIA", "COUNTS FOR ATTENDANCE")
              : m.t("NO CUENTA PARA ASISTENCIA", "DOES NOT COUNT")
          )
          .font(.custom(Enki.mono, size: 9)).foregroundStyle(Enki.accent)
          .padding(6).overlay { Rectangle().stroke(Enki.accent, lineWidth: 0.6) }
          MicroLabel(text: "\(event.participantIds.count) " + m.t("EN LA LISTA", "ON THE ROSTER"))
          Spacer()
        }.padding(.bottom, 15)
        HStack(spacing: 24) {
          eventTab(m.t("Evento", "Event"), 2)
          eventTab(m.t("Voluntarios", "Volunteers"), 1)
          eventTab(m.t("Asistencia", "Attendance"), 0)
          Spacer()
        }
        PaperRule()
        Group {
          if m.eventTab == 0 {
            AttendanceView(event: event)
          } else if m.eventTab == 1 {
            VolunteersView(event: event)
          } else {
            context
          }
        }.modifier(PaperArrival(trigger: String(m.eventTab)))
      }.padding(.horizontal, 32).frame(
        maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      if m.eventTab == 0 { AttendanceRail(event: event).frame(width: 228) }
    }.confirmationDialog(
      m.t("¿Eliminar este borrador?", "Delete this draft?"),
      isPresented: $confirmDelete,
      titleVisibility: .visible
    ) {
      Button(m.t("Eliminar", "Delete"), role: .destructive) {
        Task {
          _ = await m.edit(
            .delete(.events, event.id), label: m.t("Eliminar borrador", "Delete draft"))
        }
      }
      Button(m.t("Cancelar", "Cancel"), role: .cancel) {}
    } message: {
      Text(
        m.t(
          "Solo se elimina un borrador. Se puede deshacer durante esta sesión.",
          "Only a draft is deleted. This can be undone during this session."))
    }
    .sheet(isPresented: $duplicate) {
      SheetFrame(
        title: m.t("Duplicar evento", "Duplicate event"),
        save: {
          await m.edit(
            .duplicate(event.id, newID(), duplicateDay),
            label: m.t("Duplicar evento", "Duplicate event"))
        }
      ) {
        PaperForm {
          DayField(title: m.t("Fecha de la copia", "Copy date"), value: $duplicateDay)
          Text(
            m.t(
              "Se crea un borrador sin participantes, asistencia ni selecciones.",
              "Creates a draft with no participants, attendance or selections."))
        }
      }
    }
  }
  private func eventTab(_ title: String, _ value: Int) -> some View {
    Button {
      m.eventTab = value
    } label: {
      Text(title.uppercased()).font(.custom(Enki.mono, size: 10)).tracking(1)
        .padding(.vertical, 10).foregroundStyle(
          m.eventTab == value ? Enki.accent : Enki.ink.opacity(0.55)
        )
        .overlay(alignment: .bottom) {
          if m.eventTab == value { Rectangle().fill(Enki.accent).frame(height: 2) }
        }
    }.buttonStyle(.plain).accessibilityLabel(m.t("Pestaña ", "Tab ") + title)
      .accessibilityIdentifier("event-tab-\(value)")
  }
  private var actions: some View {
    Button {
      showingActions = true
    } label: {
      StatusStamp(
        text: m.status(event.status.rawValue), filled: event.status == .completed,
        muted: event.status == .cancelled, dashed: event.status == .draft)
    }.buttonStyle(.plain).accessibilityIdentifier("event-actions").help(
      m.t("Estado, lista, voluntariado y contexto", "Status, roster, volunteers and context")
    )
    .popover(isPresented: $showingActions, arrowEdge: .bottom) {
      VStack(alignment: .leading, spacing: 14) {
        MicroLabel(text: m.t("Evento", "Event"))
        Button(m.t("Asistencia", "Attendance")) {
          m.eventTab = 0
          showingActions = false
        }
        Button(m.t("Voluntariado", "Volunteers")) {
          m.eventTab = 1
          showingActions = false
        }
        Button(m.t("Contexto e historial", "Context and history")) {
          m.eventTab = 2
          showingActions = false
        }
        PaperRule()
        Button(m.t("Editar evento y lista", "Edit event and roster")) {
          showingActions = false
          edit()
        }.disabled(!m.canEdit || event.status == .cancelled)
        Button(m.t("Duplicar…", "Duplicate…")) {
          showingActions = false
          duplicateDay = event.date
          duplicate = true
        }.disabled(!m.canEdit)
        ForEach(event.status.next, id: \.rawValue) { state in
          Button(m.t("Cambiar a: ", "Change to: ") + m.status(state.rawValue)) {
            showingActions = false
            Task {
              _ = await m.edit(
                .eventStatus(event.id, state),
                label: m.t("Estado: ", "Status: ") + m.status(state.rawValue))
            }
          }.disabled(!m.canEdit)
        }
        if event.status == .draft {
          Button(m.t("Eliminar borrador", "Delete draft"), role: .destructive) {
            showingActions = false
            confirmDelete = true
          }.disabled(!m.canEdit)
        }
      }.buttonStyle(.plain).padding(22).frame(width: 280, alignment: .leading)
        .background { PaperGlassSurface() }
    }
  }
  private var context: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        Text(
          m.t("Componente: ", "Component: ")
            + (m.space?.components.first { $0.id == event.componentId }?.name ?? ""))
        Text(
          m.t("Categoría: ", "Category: ")
            + (m.space?.categories.first { $0.id == event.categoryId }?.name ?? "—"))
        Text(
          "\(event.participantIds.count) / \(event.capacity) · "
            + m.t("cupo total", "total capacity"))
        Text(event.notes.isEmpty ? m.t("Sin notas", "No notes") : event.notes).textSelection(
          .enabled)
        PaperRule()
        MicroLabel(text: m.t("Historial del evento", "Event history"))
        ForEach(eventHistory) { r in
          VStack(alignment: .leading, spacing: 5) {
            Text(r.label)
            MicroLabel(text: r.timestamp + " · " + r.author)
          }
        }
      }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 18)
    }
    .onAppear { refreshEventHistory() }
    .onChange(of: m.branch?.visible?.id) { refreshEventHistory() }
    .onChange(of: m.branch?.revisions.count) { refreshEventHistory() }
  }
  private func refreshEventHistory() {
    let key = (m.branch?.visible?.id ?? "") + "|" + event.id + "|"
      + String(m.branch?.revisions.count ?? 0)
    guard key != eventHistoryKey else { return }
    eventHistoryKey = key
    eventHistory = eventRevisions
  }
  private var eventRevisions: [Revision] {
    guard let b = m.branch else { return [] }
    return b.revisions.filter { r in
      guard r.data.event(event.id) != nil else { return false }
      guard let parent = b.revisions.first(where: { $0.id == r.parents.first }) else { return true }
      return r.data.event(event.id) != parent.data.event(event.id)
        || r.data.attendance.filter { $0.eventId == event.id }
          != parent.data.attendance.filter { $0.eventId == event.id }
        || r.data.volunteers.filter { $0.eventId == event.id }
          != parent.data.volunteers.filter { $0.eventId == event.id }
    }.reversed()
  }
}
struct EventEditor: View {
  @Environment(AppModel.self) private var m
  @State private var event: Activity
  @State private var group = ""
  @State private var search = ""
  var onSaved: (String) -> Void
  init(value: Activity, onSaved: @escaping (String) -> Void) {
    _event = State(initialValue: value)
    self.onSaved = onSaved
  }
  var body: some View {
    SheetFrame(
      title: m.t("Evento y participantes", "Event and participants"),
      save: {
        guard let clock = canonicalClock(event.time) else {
          m.error = m.t(
            "La hora usa HH:mm, por ejemplo 09:00.", "Time uses HH:mm, for example 09:00.")
          return false
        }
        if event.time != clock { event.time = clock }
        if event.componentId.isEmpty {
          m.error = m.t(
            "Elige un componente antes de guardar. Crea uno en Componentes si todavía no hay ninguno.",
            "Choose a component before saving. Create one in Components if there are none yet.")
          return false
        }
        let ok = await m.edit(.event(event), label: m.t("Guardar evento", "Save event"))
        if ok { onSaved(event.id) }
        return ok
      }
    ) {
      if let s = m.space {
        PaperForm {
          PaperInput(m.t("Nombre", "Name")) { TextField(m.t("Nombre", "Name"), text: $event.name) }
            .accessibilityIdentifier("field-name")
          DayField(title: m.t("Fecha", "Date"), value: $event.date)
          PaperInput(m.t("Hora (HH:mm)", "Time (HH:mm)")) {
            TextField(m.t("Hora (HH:mm)", "Time (HH:mm)"), text: $event.time)
          }
          Text(s.timeZone).font(.caption).foregroundStyle(.secondary)
          PaperPicker(
            m.t("Componente", "Component"), selection: $event.componentId,
            options: [PaperOption("", "—")] + (s.components).map { PaperOption($0.id, $0.name) }
          ).onChange(of: event.componentId) { event.categoryId = nil }
          if s.components.isEmpty {
            Text(
              m.t(
                "Todavía no hay componentes. Crea uno en Componentes y vuelve a este evento.",
                "There are no components yet. Create one in Components, then return to this event.")
            ).font(.caption).foregroundStyle(.secondary)
          }
          PaperPicker(
            m.t("Categoría", "Category"),
            selection: Binding(
              get: { event.categoryId ?? "" }, set: { event.categoryId = $0.isEmpty ? nil : $0 }),
            options: [PaperOption("", m.t("Ninguna", "None"))]
              + (s.categories.filter { $0.componentId == event.componentId }).map {
                PaperOption($0.id, $0.name)
              })
          PaperInput(m.t("Cupo total", "Total capacity")) {
            TextField(m.t("Cupo total", "Total capacity"), value: $event.capacity, format: .number)
          }
          PaperInput(m.t("Cupo de voluntariado", "Volunteer capacity")) {
            TextField(
              m.t("Cupo de voluntariado", "Volunteer capacity"), value: $event.volunteerCapacity,
              format: .number)
          }
          Toggle(
            m.t("Cuenta para asistencia", "Counts for attendance"), isOn: $event.countsForAttendance
          )
          PaperInput(m.t("Notas", "Notes")) {
            TextField(m.t("Notas", "Notes"), text: $event.notes, axis: .vertical)
          }.lineLimit(3...6)
          PaperSection(m.t("Lista de participantes", "Participant roster")) {
            HStack {
              PaperPicker(
                m.t("Grupo en esa fecha", "Group on event date"), selection: $group,
                options: [PaperOption("", "—")] + (s.groups).map { PaperOption($0.id, $0.name) })
              Button(m.t("Añadir", "Add")) {
                for p in s.people
                where p.active && s.member(p.id, group: group, on: event.date)
                  && !event.participantIds.contains(p.id)
                { event.participantIds.append(p.id) }
              }.disabled(group.isEmpty)
            }
            PaperInput(m.t("Buscar persona", "Search people")) {
              TextField(m.t("Buscar persona", "Search people"), text: $search)
            }
            ForEach(
              s.people.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
            ) { p in
              Toggle(
                p.name + (p.active ? "" : m.t(" · Inactivo", " · Inactive")),
                isOn: Binding(
                  get: { event.participantIds.contains(p.id) },
                  set: { yes in
                    if yes {
                      event.participantIds.append(p.id)
                    } else {
                      event.participantIds.removeAll { $0 == p.id }
                    }
                  })
              ).disabled(!p.active && !event.participantIds.contains(p.id))
            }
            Text("\(event.participantIds.count) / \(event.capacity)").monospacedDigit()
          }
        }
      }
    }
  }
}
struct RecordNote: Identifiable {
  var id = newID()
  var attendance: Attendance?
  var volunteer: Volunteer?
}
struct RecordNoteEditor: View {
  @Environment(AppModel.self) private var m
  @State private var note: String
  var record: RecordNote
  init(record: RecordNote) {
    self.record = record
    _note = State(initialValue: record.attendance?.notes ?? record.volunteer?.notes ?? "")
  }
  var body: some View {
    SheetFrame(
      title: m.t("Notas de participación", "Participation notes"),
      save: {
        if var a = record.attendance {
          a.notes = note
          return await m.edit(.attendance(a), label: m.t("Notas de asistencia", "Attendance notes"))
        }
        if var v = record.volunteer {
          v.notes = note
          return await m.edit(.volunteer(v), label: m.t("Notas de voluntariado", "Volunteer notes"))
        }
        return false
      }
    ) {
      PaperTextEditor(text: $note).font(.body).frame(minHeight: 300).border(Enki.rule)
      Text(
        m.t(
          "Las notas anteriores se conservan en el historial.",
          "Previous notes remain in revision history.")
      ).foregroundStyle(.secondary)
    }
  }
}
struct AttendanceView: View {
  @Environment(\.paperReduceMotion) private var reducedMotion
  @Environment(AppModel.self) private var m
  var event: Activity
  @State private var query = ""
  @State private var note: RecordNote?
  @State private var selectedPerson = ""
  @FocusState private var rosterFocused: Bool
  private var visiblePeople: [Person] {
    guard m.space != nil else { return [] }
    return event.participantIds.compactMap { m.personRecord($0) }.filter {
      query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 12) {
        Text(m.t("presente / (presente + ausente)", "present / (present + absent)")).font(.custom(Enki.mono, size: 9))
        Text(
          m.t(
            "Excusado y pendiente no cuentan. Cada marca conserva su historial.",
            "Excused and pending do not count. Every mark keeps its history.")
        ).font(.system(size: 11))
      }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(Enki.atmosphere.opacity(0.07))
        .overlay(alignment: .leading) { Rectangle().fill(Enki.present).frame(width: 3) }
        .padding(.vertical, 12)
      if !event.canRecord {
        Text(
          m.t(
            "Programa o reabre el evento para registrar asistencia.",
            "Schedule or reopen the event to record attendance.")
        ).font(.callout).padding(.vertical, 12)
      }
      if !event.participantIds.isEmpty {
        HStack(spacing: 12) {
          PaperInput(m.t("Buscar participante…", "Find participant…")) {
            TextField(m.t("Buscar participante…", "Find participant…"), text: $query)
              .accessibilityIdentifier("attendance-search")
          }.textFieldStyle(.plain).font(.custom(Enki.mono, size: 10))
          if !query.isEmpty {
            Text("\(visiblePeople.count)").font(.custom(Enki.mono, size: 10)).foregroundStyle(
              .secondary)
            Button(m.t("Limpiar", "Clear")) { query = "" }.buttonStyle(ActionLink())
          }
        }.padding(.vertical, 12)
      }
      HStack {
        MicroLabel(text: m.t("ELIGE UNA FILA · ↑ ↓ MOVER · P A E X MARCAR · N NOTA",
                             "SELECT A ROW · ↑ ↓ MOVE · P A E X MARK · N NOTE"))
        Spacer()
      }.foregroundStyle(.secondary).padding(.vertical, 8)
      ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 0) {
          if m.space != nil {
            ForEach(Array(event.participantIds.enumerated()), id: \.element) { index, id in
              if let p = m.personRecord(id),
                query.isEmpty || p.name.localizedCaseInsensitiveContains(query)
              {
                let record = m.attendanceRecord(event: event.id, person: id)
                  ?? Attendance(eventId: event.id, personId: id)
                VStack(alignment: .leading, spacing: 0) {
                  HStack(spacing: 14) {
                    Text(String(format: "%02d", index + 1)).font(.custom(Enki.mono, size: 8))
                      .foregroundStyle(Enki.accent).frame(width: 20, alignment: .leading)
                    Button {
                      selectedPerson = id
                      rosterFocused = true
                    } label: {
                      Text(p.name.uppercased()).font(.custom(Enki.display, size: 18)).lineLimit(2)
                        .foregroundStyle(selectedPerson == id ? Enki.accent : Enki.ink)
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("attendance-row-" + id)
                      .accessibilityAddTraits(selectedPerson == id ? .isSelected : [])
                    VStack(alignment: .leading, spacing: 3) {
                      Text(m.groupLabel(person: id, on: event.date).uppercased()).font(
                        .custom(Enki.mono, size: 7)
                      ).tracking(1)
                        .foregroundStyle(Enki.ink.opacity(0.65)).lineLimit(1)
                      if record.status == .pending {
                        Text(m.t("PENDIENTE", "PENDING")).font(.custom(Enki.mono, size: 6))
                          .tracking(0.8).foregroundStyle(Enki.accent)
                      }
                    }.frame(width: 65, alignment: .leading)
                    HStack(spacing: 5) {
                      attendanceButton(.present, record, p)
                      attendanceButton(.absent, record, p)
                      attendanceButton(.excused, record, p)
                      attendanceButton(.pending, record, p)
                    }
                    PaperMenu {
                      Button(m.t("Notas…", "Notes…")) { note = RecordNote(attendance: record) }
                      Button(m.t("Marcar pendiente", "Mark pending")) { set(.pending, record, p) }
                    } label: {
                      Image(systemName: record.notes.isEmpty ? "ellipsis" : "note.text")
                    }.frame(width: 14).opacity(0.65).disabled(
                      !m.canEdit || !event.canRecord
                    ).help(m.t("Notas y estado pendiente", "Notes and pending state"))
                  }.padding(.vertical, 11).padding(.leading, 6)
                  if !record.notes.isEmpty {
                    Text(record.notes).font(.caption).foregroundStyle(.secondary).textSelection(
                      .enabled
                    ).padding(.leading, 34).padding(.bottom, 10)
                  }
                  PaperRule()
                }.background(selectedPerson == id ? Enki.accent.opacity(0.12) : .clear)
                  .overlay(alignment: .leading) {
                    if selectedPerson == id { Rectangle().fill(Enki.accent).frame(width: 3) }
                  }.id(id)
              }
            }
          }
        }
      }.focusable().focusEffectDisabled().focused($rosterFocused)
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "paexnPAEXN")) { key in
          guard rosterFocused, m.canEdit, event.canRecord, m.space != nil,
            let person = visiblePeople.first(where: { $0.id == selectedPerson }) else { return .ignored }
          let record = m.attendanceRecord(event: event.id, person: person.id)
            ?? Attendance(eventId: event.id, personId: person.id)
          if key.characters.lowercased() == "n" { note = RecordNote(attendance: record); return .handled }
          let states: [String: AttendanceStatus] = ["p": .present, "a": .absent, "e": .excused, "x": .pending]
          guard let state = states[key.characters.lowercased()] else { return .ignored }
          set(state, record, person, advance: true)
          return .handled
        }
        .onChange(of: selectedPerson) { proxy.scrollTo(selectedPerson) }
        .onAppear {
          if selectedPerson.isEmpty || !visiblePeople.contains(where: { $0.id == selectedPerson }) {
            selectedPerson = visiblePeople.first?.id ?? ""
          }
          rosterFocused = true
        }
      }
      if !query.isEmpty && visiblePeople.isEmpty && !event.participantIds.isEmpty {
        Text(m.t("Sin coincidencias en la lista.", "No matches on the roster."))
          .foregroundStyle(.secondary).padding(.vertical, 8)
      }
      if event.participantIds.isEmpty {
        EmptyState(
          title: m.t("La lista está vacía", "The roster is empty"),
          detail: m.t(
            "Añade participantes en Acciones o selecciona voluntarios.",
            "Add participants in Actions or select volunteers."))
      }
    }.sheet(item: $note) { RecordNoteEditor(record: $0) }
  }
  private func move(_ delta: Int) {
    let people = visiblePeople
    guard !people.isEmpty else { return }
    let index = people.firstIndex { $0.id == selectedPerson }
    selectedPerson = people[min(people.count - 1, max(0, (index ?? (delta > 0 ? -1 : 1)) + delta))].id
  }
  private func set(_ value: AttendanceStatus, _ old: Attendance, _ p: Person, advance: Bool = false) {
    selectedPerson = p.id
    if old.status == value {
      if advance { move(1) }
      return
    }
    var changed = old
    changed.status = value
    Task {
      let saved = await m.edit(
        .attendance(changed),
        label: m.t("Asistencia: ", "Attendance: ") + "\(p.name) · \(m.status(value.rawValue))")
      if saved && advance && selectedPerson == p.id { move(1) }
    }
  }
  private func attendanceButton(_ state: AttendanceStatus, _ record: Attendance, _ person: Person)
    -> some View
  {
    Button {
      set(state, record, person)
    } label: {
      Group {
        if record.status == state {
          StatusStamp(
            text: m.status(state.rawValue), filled: state == .present,
            dashed: state == .excused || state == .pending,
            angle: state == .excused ? -1 : state == .absent ? 3 : -4
          )
          .transition(
            reducedMotion
              ? .identity
              : .asymmetric(
                insertion: .scale(scale: 1.08).combined(with: .opacity), removal: .opacity))
        } else {
          Text(m.status(state.rawValue).uppercased()).font(.custom(Enki.mono, size: 9)).tracking(0.6)
            .foregroundStyle(Enki.ink.opacity(0.72)).padding(.bottom, 3).frame(maxWidth: .infinity)
            .overlay(alignment: .bottom) {
              DottedLine().stroke(
                Enki.ink.opacity(0.5), style: StrokeStyle(lineWidth: 0.5, dash: [1, 1])
              ).frame(height: 1)
            }
        }
      }.frame(width: 92, height: 34).contentShape(Rectangle())
        .animation(reducedMotion ? nil : PaperMotion.response, value: record.status)
    }.buttonStyle(PaperButtonStyle(lift: 1)).help(markHelp(state)).accessibilityLabel(
      m.status(state.rawValue) + " · " + person.name
    )
    .accessibilityIdentifier("attendance-" + person.id + "-" + state.rawValue).accessibilityValue(
      record.status == state ? m.t("Seleccionado", "Selected") : ""
    ).disabled(!m.canEdit || !event.canRecord)
  }
  private func markHelp(_ state: AttendanceStatus) -> String {
    switch state {
    case .present: return m.t("Presente · tecla P", "Present · P")
    case .absent: return m.t("Ausente · tecla A", "Absent · A")
    case .excused: return m.t("Excusado · tecla E", "Excused · E")
    case .pending: return m.t("Pendiente · tecla X", "Pending · X")
    }
  }
}
struct DottedLine: Shape {
  func path(in rect: CGRect) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: 0, y: rect.midY))
    p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
    return p
  }
}
struct AttendanceRail: View {
  @Environment(AppModel.self) private var m
  var event: Activity
  private var result: Participation {
    guard m.space != nil else { return Participation() }
    return m.participation(filter: ReportFilter(eventId: event.id))
  }
  private var counts: [AttendanceStatus: Int] {
    guard m.space != nil else { return [:] }
    return m.attendanceCounts(for: event)
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(spacing: 8) {
        Text(m.t("ASISTENCIA · ESTE EVENTO", "ATTENDANCE · THIS EVENT"))
          .font(.custom(Enki.mono, size: 8)).tracking(0.8).foregroundStyle(Enki.onDark.opacity(0.7))
        Text(result.percentage.map { String(format: "%.0f%%", $0) } ?? "—")
          .font(.custom(Enki.display, size: 78)).foregroundStyle(Enki.onDark)
          .minimumScaleFactor(0.65).lineLimit(1).modifier(PaperNumber(value: result.formatted))
        Text("\(result.present) / (\(result.present) + \(result.absent))")
          .font(.custom(Enki.mono, size: 10)).foregroundStyle(Enki.onDark.opacity(0.8))
      }.padding(.vertical, 22).frame(maxWidth: .infinity)
        .background { PaperAccentSurface(tint: Enki.deep, cornerRadius: 2) }.padding(.top, 22).padding(
          .bottom, 18)
      ForEach(AttendanceStatus.allCases, id: \.rawValue) { state in
        HStack {
          Text(m.status(state.rawValue).uppercased()).tracking(1)
          Spacer()
          Text(String(counts[state] ?? 0)).modifier(PaperNumber(value: String(counts[state] ?? 0)))
        }.font(.custom(Enki.mono, size: 9)).foregroundStyle(
          state == .pending || state == .excused ? Enki.ink.opacity(0.55) : Enki.ink
        ).padding(.vertical, 6)
        PaperRule()
      }
      if !event.canRecord || !event.countsForAttendance {
        Text(
          m.t("Este evento está excluido del cálculo.", "This event is excluded from calculation.")
        ).font(.caption).padding(.top, 16)
      }
      Spacer(minLength: 25)
      Text(
        m.t(
          "Pendiente y excusado no cuentan. Solo se evalúa la lista del evento.",
          "Pending and excused do not count. Only the event roster is evaluated.")
      ).font(.system(size: 10)).foregroundStyle(Enki.ink.opacity(0.6)).lineSpacing(3)
    }.padding(.horizontal, 22).padding(.bottom, 22).frame(maxHeight: .infinity)
      .background { PaperGlassSurface(tint: Enki.side) }.overlay(alignment: .leading) {
        VerticalDottedLine().stroke(Enki.rule, style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
          .frame(width: 1)
      }
  }
}
struct VolunteersView: View {
  @Environment(AppModel.self) private var m
  var event: Activity
  @State private var candidate = ""
  @State private var note: RecordNote?
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        if let s = m.space {
          let volunteers = s.volunteers.filter { $0.eventId == event.id }
          HStack {
            Text(m.t("Cupos ocupados", "Occupied seats"))
            Spacer()
            Text(
              "\(volunteers.filter { $0.status.occupiesSeat }.count) / \(event.volunteerCapacity)"
            ).monospacedDigit()
          }
          HStack {
            PaperPicker(
              m.t("Persona interesada", "Interested person"), selection: $candidate,
              options: [PaperOption("", "—")]
                + (s.people.filter { p in p.active && !volunteers.contains { $0.personId == p.id } })
                .map { PaperOption($0.id, $0.name) }
            ).accessibilityIdentifier("volunteer-candidate")
            Button(m.t("Registrar interés", "Register interest")) {
              Task {
                if await m.edit(
                  .volunteer(Volunteer(eventId: event.id, personId: candidate)),
                  label: m.t("Registrar interés", "Register interest"))
                {
                  candidate = ""
                }
              }
            }.disabled(
              candidate.isEmpty || !m.canEdit || event.status == .cancelled
                || event.status == .completed)
          }
          Text(
            m.t(
              "Puntuación: voluntariados previos completados × 3 + asistencias previas × 1. La selección siempre es manual.",
              "Score: prior completed volunteering × 3 + prior attendance × 1. Selection is always manual."
            )
          ).font(.caption).foregroundStyle(.secondary)
          ForEach(m.volunteerSuggestions(for: event)) { suggestion in
            VStack(alignment: .leading, spacing: 7) {
              HStack {
                Text(suggestion.name).font(.custom(Enki.condensed, size: 21))
                Spacer()
                Text("\(suggestion.score) pt").font(.custom(Enki.mono, size: 12))
                Button(m.t("Seleccionar", "Select")) {
                  if var v = volunteers.first(where: { $0.personId == suggestion.id }) {
                    v.status = .selected
                    Task {
                      _ = await m.edit(.volunteer(v), label: m.t("Seleccionar voluntario", "Select volunteer"))
                    }
                  }
                }.disabled(
                  !m.canEdit || !suggestion.active || event.status == .cancelled
                    || event.status == .completed)
              }
              Text("\(suggestion.completed) × 3 + \(suggestion.present) × 1").foregroundStyle(
                .secondary)
              if !suggestion.active { Text(m.t("Persona inactiva", "Inactive person")) }
            }.padding(.vertical, 8)
            Divider()
          }
          Text(m.t("REGISTROS Y ESTADOS", "RECORDS AND STATUS")).font(.custom(Enki.mono, size: 11))
          ForEach(volunteers) { v in
            VStack(alignment: .leading, spacing: 7) {
              HStack {
                Text(m.personRecord(v.personId)?.name ?? "")
                Spacer()
                Text(m.status(v.status.rawValue)).font(.caption)
                PaperMenu(m.t("Cambiar", "Change")) {
                  ForEach(v.status.next, id: \.rawValue) { state in
                    Button(m.status(state.rawValue)) {
                      var changed = v
                      changed.status = state
                      Task {
                        _ = await m.edit(
                          .volunteer(changed),
                          label: m.t("Voluntariado: ", "Volunteering: ") + m.status(state.rawValue))
                      }
                    }
                  }
                }
                Button(m.t("Notas", "Notes")) { note = RecordNote(volunteer: v) }
              }.disabled(!m.canEdit || event.status == .cancelled)
              if !v.notes.isEmpty { Text(v.notes).font(.caption).foregroundStyle(.secondary) }
            }.padding(.vertical, 8)
            Divider()
          }
          Text(
            m.t(
              "Declinar libera el cupo de voluntariado y conserva a la persona en la lista. Completar voluntariado no cambia la asistencia.",
              "Declining frees a volunteer seat and keeps the participant on the roster. Completing volunteering does not change attendance."
            )
          ).font(.caption).foregroundStyle(.secondary)
        }
      }.padding(14)
    }.sheet(item: $note) { RecordNoteEditor(record: $0) }
  }
}

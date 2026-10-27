import SwiftUI

enum CatalogKind: String, Identifiable {
  case person, group, membership, period, component, category
  var id: String { rawValue }
}
private struct DeleteRequest: Identifiable {
  let id = UUID()
  let collection: Collection
  let recordID: String
  let name: String
}
struct CatalogDraft: Identifiable {
  var id = newID()
  var kind: CatalogKind
  var name = ""
  var email = ""
  var notes = ""
  var active = true
  var personId = ""
  var groupId = ""
  var componentId = ""
  var start = Day.today
  var end = Day.today
  var openEnded = true
  var creating = false
  init(kind: CatalogKind) {
    self.kind = kind
    creating = true
  }
  init(_ p: Person) {
    kind = .person
    id = p.id
    name = p.name
    email = p.email
    active = p.active
    notes = p.notes
  }
  init(_ p: Named, kind: CatalogKind) {
    self.kind = kind
    id = p.id
    name = p.name
  }
  init(_ p: Membership) {
    kind = .membership
    id = p.id
    personId = p.personId
    groupId = p.groupId
    start = p.start
    end = p.end ?? Day.today
    openEnded = p.end == nil
  }
  init(_ p: Period) {
    kind = .period
    id = p.id
    name = p.name
    start = p.start
    end = p.end
  }
  init(_ p: Category) {
    kind = .category
    id = p.id
    name = p.name
    componentId = p.componentId
  }
  var command: Edit {
    switch kind {
    case .person:
      .person(
        Person(
          id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), email: email,
          active: active, notes: notes))
    case .group: .group(Named(id: id, name: name))
    case .component: .component(Named(id: id, name: name))
    case .category: .category(Category(id: id, name: name, componentId: componentId))
    case .period: .period(Period(id: id, name: name, start: start, end: end))
    case .membership:
      .membership(
        Membership(
          id: id, personId: personId, groupId: groupId, start: start, end: openEnded ? nil : end))
    }
  }
}
struct CatalogView: View {
  @Environment(AppModel.self) private var m
  var section: AppSection
  @State private var query = ""
  @State private var draft: CatalogDraft?
  @State private var attendancePerson: Person?
  @State private var pendingDelete: DeleteRequest?
  var body: some View {
    VStack(spacing: 0) {
      PageHeading(title: section.title(m), subtitle: m.space?.name ?? "") {
        switch section {
        case .people: add(.person, m.t("Añadir persona", "Add person"))
        case .groups:
          add(.group, m.t("Nuevo grupo", "New group"))
          add(.membership, m.t("Añadir membresía", "Add membership"))
        case .periods: add(.period, m.t("Nuevo período", "New period"))
        default:
          add(.component, m.t("Nuevo componente", "New component"))
          add(.category, m.t("Nueva categoría", "New category"))
        }
      }
      if let s = m.space {
        if section == .people {
          people(s)
        } else {
          ScrollView {
            VStack(alignment: .leading, spacing: 0) {
              if section == .groups {
                ForEach(s.groups) { g in
                  row(
                    g.name, "", edit: { draft = CatalogDraft(g, kind: .group) },
                    collection: .groups, id: g.id)
                }
                Divider().padding(.vertical, 20)
                Text(m.t("MEMBRESÍAS · FECHAS INCLUSIVAS", "MEMBERSHIPS · INCLUSIVE DATES")).font(
                  .custom(Enki.mono, size: 11)
                ).padding(.bottom, 12)
                ForEach(s.memberships) { v in
                  row(
                    s.person(v.personId)?.name ?? "",
                    "\(s.groups.first { $0.id == v.groupId }?.name ?? "") · \(v.start) → \(v.end ?? "∞")",
                    edit: { draft = CatalogDraft(v) }, collection: .memberships, id: v.id)
                }
              } else if section == .periods {
                ForEach(s.periods) { p in
                  row(
                    p.name, "\(p.start) → \(p.end)", edit: { draft = CatalogDraft(p) },
                    collection: .periods, id: p.id)
                }
              } else {
                ForEach(s.components) { c in
                  row(
                    c.name, m.t("Componente", "Component"),
                    edit: { draft = CatalogDraft(c, kind: .component) }, collection: .components,
                    id: c.id)
                  ForEach(s.categories.filter { $0.componentId == c.id }) { cat in
                    row(
                      cat.name, m.t("Categoría", "Category"), edit: { draft = CatalogDraft(cat) },
                      collection: .categories, id: cat.id
                    ).padding(.leading, 30)
                  }
                }
              }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 28)
          }.frame(maxWidth: .infinity, maxHeight: .infinity).overlay {
            if isEmpty(s) {
              EmptyState(
                title: m.t("Sin registros", "No records"),
                detail: m.t(
                  "Añade el primer registro con las acciones de arriba.",
                  "Add the first record using the actions above."))
            }
          }
        }
      }
    }.sheet(item: $draft) { CatalogEditor(value: $0) }
      .sheet(item: $attendancePerson) { PersonParticipationView(personID: $0.id) }
      .confirmationDialog(
        pendingDelete.map { m.t("¿Eliminar \($0.name)?", "Delete \($0.name)?") } ?? "",
        isPresented: Binding(
          get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
        titleVisibility: .visible
      ) {
        Button(m.t("Eliminar", "Delete"), role: .destructive) {
          if let request = pendingDelete {
            Task {
              _ = await m.edit(
                .delete(request.collection, request.recordID),
                label: m.t("Eliminar \(request.name)", "Delete \(request.name)"))
            }
          }
          pendingDelete = nil
        }
        Button(m.t("Cancelar", "Cancel"), role: .cancel) { pendingDelete = nil }
      } message: {
        Text(
          m.t(
            "Se puede deshacer durante esta sesión. Un registro que sigue en uso no se elimina.",
            "This can be undone during this session. A record that is still in use is not deleted."))
      }
  }
  private func isEmpty(_ s: Space) -> Bool {
    section == .groups
      ? s.groups.isEmpty && s.memberships.isEmpty
      : section == .periods ? s.periods.isEmpty : s.components.isEmpty
  }
  private func add(_ kind: CatalogKind, _ text: String) -> some View {
    Button(text) { draft = CatalogDraft(kind: kind) }.accessibilityIdentifier(
      "add-" + kind.rawValue
    ).buttonStyle(ActionLink()).disabled(!m.canEdit)
  }
  private func row(
    _ name: String, _ detail: String, edit: @escaping () -> Void, collection: Collection, id: String
  ) -> some View {
    VStack(spacing: 0) {
      HStack {
        VStack(alignment: .leading, spacing: 5) {
          Text(name).font(.custom(Enki.condensed, size: 21))
          if !detail.isEmpty { Text(detail).foregroundStyle(.secondary) }
        }
        Spacer()
        Button(m.t("Editar", "Edit"), action: edit).buttonStyle(ActionLink()).disabled(!m.canEdit)
        PaperMenu {
          Button(m.t("Eliminar registro", "Delete record"), role: .destructive) {
            let title = name.isEmpty ? m.t("este registro", "this record") : name
            pendingDelete = DeleteRequest(collection: collection, recordID: id, name: title)
          }
        } label: {
          Image(systemName: "ellipsis")
        }.frame(width: 24).disabled(!m.canEdit)
      }.padding(.vertical, 16).modifier(PaperHover())
      Divider()
    }
  }
  private func people(_ s: Space) -> some View {
    VStack {
      TextField(m.t("Buscar por nombre o correo", "Search name or email"), text: $query)
        .textFieldStyle(PaperFieldStyle()).padding(.horizontal, 28)
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          HStack {
            MicroLabel(text: m.t("Persona / correo", "Person / email"))
            Spacer()
            MicroLabel(text: m.t("Estado / acciones", "Status / actions"))
          }.padding(.vertical, 12)
          PaperRule(strong: true)
          ForEach(
            s.people.filter {
              query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
                || $0.email.localizedCaseInsensitiveContains(query)
            }
          ) { p in
            HStack(spacing: 20) {
              VStack(alignment: .leading, spacing: 5) {
                Text(p.name).font(.custom(Enki.condensed, size: 22))
                Text(p.email).font(.custom(Enki.mono, size: 10)).textSelection(.enabled)
              }.frame(maxWidth: .infinity, alignment: .leading)
              StatusStamp(
                text: p.active ? m.t("Activo", "Active") : m.t("Inactivo", "Inactive"),
                muted: !p.active, angle: 0)
              Button(m.t("Asistencia →", "Attendance →")) { attendancePerson = p }
                .accessibilityIdentifier("person-attendance-" + p.id)
              Button(m.t("Editar", "Edit")) { draft = CatalogDraft(p) }.buttonStyle(ActionLink())
                .disabled(!m.canEdit)
              PaperMenu {
                Button(m.t("Eliminar", "Delete"), role: .destructive) {
                  pendingDelete = DeleteRequest(collection: .people, recordID: p.id, name: p.name)
                }
              } label: {
                Image(systemName: "ellipsis")
              }.disabled(!m.canEdit)
            }.padding(.vertical, 15).modifier(PaperHover())
            PaperRule()
          }
        }.padding(.horizontal, 28).frame(maxWidth: .infinity)
      }.frame(maxWidth: .infinity, maxHeight: .infinity).overlay {
        if s.people.isEmpty {
          EmptyState(
            title: m.t("Sin personas", "No people"),
            detail: m.t(
              "Añade personas antes de crear participantes o membresías.",
              "Add people before choosing participants or memberships."))
        } else if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          && !s.people.contains(where: {
            $0.name.localizedCaseInsensitiveContains(query)
              || $0.email.localizedCaseInsensitiveContains(query)
          })
        {
          Text(m.t("Sin coincidencias.", "No matches.")).foregroundStyle(.secondary)
        }
      }
    }
  }
}
struct CatalogEditor: View {
  @Environment(AppModel.self) private var m
  @State private var draft: CatalogDraft
  init(value: CatalogDraft) { _draft = State(initialValue: value) }
  var body: some View {
    SheetFrame(
      title: draft.creating
        ? m.t("Nuevo registro", "New record") : m.t("Editar registro", "Edit record"),
      save: { await m.edit(draft.command, label: saveLabel(draft.kind)) }
    ) {
      PaperForm {
        if draft.kind != .membership {
          PaperInput(m.t("Nombre", "Name")) { TextField(m.t("Nombre", "Name"), text: $draft.name) }
            .accessibilityIdentifier("field-name")
        }
        if draft.kind == .person {
          PaperInput(m.t("Correo", "Email")) {
            TextField(m.t("Correo", "Email"), text: $draft.email)
          }.accessibilityIdentifier(
            "field-email")
          Toggle(m.t("Persona activa", "Active person"), isOn: $draft.active)
          Text(
            m.t(
              "Desactivar conserva toda su participación anterior.",
              "Deactivation preserves all prior participation.")
          ).font(.caption).foregroundStyle(.secondary)
          PaperInput(m.t("Notas", "Notes")) {
            TextField(m.t("Notas", "Notes"), text: $draft.notes, axis: .vertical)
          }.lineLimit(4...10)
        }
        if draft.kind == .membership, let s = m.space {
          PaperPicker(
            m.t("Persona", "Person"), selection: $draft.personId,
            options: [PaperOption("", "—")] + (s.people).map { PaperOption($0.id, $0.name) })
          PaperPicker(
            m.t("Grupo", "Group"), selection: $draft.groupId,
            options: [PaperOption("", "—")] + (s.groups).map { PaperOption($0.id, $0.name) })
        }
        if draft.kind == .membership || draft.kind == .period {
          DayField(title: m.t("Desde", "From"), value: $draft.start)
          if draft.kind == .membership {
            Toggle(m.t("Sin fecha final", "Open ended"), isOn: $draft.openEnded)
          }
          if draft.kind == .period || !draft.openEnded {
            DayField(title: m.t("Hasta (inclusive)", "Through (inclusive)"), value: $draft.end)
          }
        }
        if draft.kind == .category, let s = m.space {
          PaperPicker(
            m.t("Componente", "Component"), selection: $draft.componentId,
            options: [PaperOption("", "—")] + (s.components).map { PaperOption($0.id, $0.name) })
        }
      }
    }
  }
  private func saveLabel(_ kind: CatalogKind) -> String {
    switch kind {
    case .person: m.t("Guardar persona", "Save person")
    case .group: m.t("Guardar grupo", "Save group")
    case .membership: m.t("Guardar membresía", "Save membership")
    case .period: m.t("Guardar período", "Save period")
    case .component: m.t("Guardar componente", "Save component")
    case .category: m.t("Guardar categoría", "Save category")
    }
  }
}

import Foundation

enum Edit {
  case settings(String, String)
  case person(Person)
  case group(Named)
  case membership(Membership)
  case period(Period)
  case component(Named)
  case category(Category)
  case template(DocumentTemplate)
  case event(Activity)
  case duplicate(String, String, String)
  case eventStatus(String, EventStatus)
  case attendance(Attendance)
  case volunteer(Volunteer)
  case delete(Collection, String)
}
enum Collection: String, CaseIterable {
  case people, groups, memberships, periods, components, categories, templates, events
}
struct ReportFilter: Hashable {
  var periodId = ""
  var groupId = ""
  var componentId = ""
  var categoryId = ""
  var eventId = ""
  var uncategorized = false
}
struct Participation {
  var present = 0
  var absent = 0
  var excused = 0
  var pending = 0
  var excluded = 0
  var denominator: Int { present + absent }
  var percentage: Double? { denominator == 0 ? nil : Double(present) / Double(denominator) * 100 }
  var formatted: String { percentage.map { String(format: "%.1f%%", $0) } ?? "—" }
}
struct ParticipationSlice: Identifiable {
  enum Kind { case overall, component, category, uncategorized }
  var id: String
  var name: String
  var kind: Kind
  var componentId: String = ""
  var result: Participation
}
struct Suggestion: Identifiable {
  var id: String
  var name: String
  var active: Bool
  var completed: Int
  var present: Int
  var score: Int { completed * 3 + present }
}

private enum RevisionStamps {
  static let lock = NSLock()
  static let fractional: ISO8601DateFormatter = {
    let format = ISO8601DateFormatter()
    format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return format
  }()
  static let basic = ISO8601DateFormatter()
}

enum Rules {
  static func unique(_ values: [String], _ message: String) throws {
    try require(Set(values).count == values.count, message)
  }
  static func identifier(_ s: String) throws {
    try require(
      s.count <= 120 && s.range(of: #"^[a-zA-Z0-9_-]+$"#, options: .regularExpression) != nil,
      "Identificador inválido")
  }
  static func title(_ s: String) throws {
    try require(
      !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && s.count <= 240,
      "El nombre es obligatorio (máximo 240 caracteres).")
  }
  static func note(_ s: String) throws {
    try require(s.count <= 20000, "El texto supera 20 000 caracteres.")
  }
  static func day(_ s: String) throws { try require(Day.date(s) != nil, "Fecha inválida: \(s)") }
  static func validate(_ s: Space) throws {
    try identifier(s.id)
    try title(s.name)
    try require(TimeZone(identifier: s.timeZone) != nil, "Zona horaria inválida")
    let ids =
      s.people.map(\.id) + s.groups.map(\.id) + s.memberships.map(\.id) + s.periods.map(\.id)
      + s.components.map(\.id) + s.categories.map(\.id) + s.events.map(\.id)
      + s.attendance.map(\.id) + s.volunteers.map(\.id) + s.templates.map(\.id)
    try unique(ids, "Identificadores duplicados en el espacio")
    for id in ids { try identifier(id) }
    for p in s.people {
      try title(p.name)
      try note(p.notes)
      try require(
        p.email.isEmpty
          || p.email.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil,
        "Correo electrónico inválido")
    }
    for n in s.groups + s.components { try title(n.name) }
    for c in s.categories {
      try title(c.name)
      try require(
        s.components.contains { $0.id == c.componentId }, "Componente de categoría inexistente")
    }
    for p in s.periods {
      try title(p.name)
      try day(p.start)
      try day(p.end)
      try require(p.start <= p.end, "El período termina antes de comenzar")
    }
    for (i, m) in s.memberships.enumerated() {
      try day(m.start)
      if let end = m.end {
        try day(end)
        try require(m.start <= end, "Fechas de membresía inválidas")
      }
      try require(
        s.person(m.personId) != nil && s.groups.contains { $0.id == m.groupId },
        "Miembro o grupo inexistente")
      try require(
        !s.memberships.dropFirst(i + 1).contains { n in
          n.personId == m.personId && n.groupId == m.groupId && m.start <= (n.end ?? "9999-12-31")
            && n.start <= (m.end ?? "9999-12-31")
        }, "Las membresías de una persona en el mismo grupo no pueden solaparse")
    }
    for e in s.events {
      try title(e.name)
      try note(e.notes)
      try day(e.date)
      try require(
        e.time.range(of: #"^([01]\d|2[0-3]):[0-5]\d$"#, options: .regularExpression) != nil,
        "Hora inválida")
      try require(
        s.components.contains { $0.id == e.componentId },
        "Todo evento necesita un componente válido")
      try require(
        e.categoryId == nil
          || s.categories.contains { $0.id == e.categoryId && $0.componentId == e.componentId },
        "La categoría no pertenece al componente")
      try unique(e.participantIds, "Participante duplicado")
      try require(
        e.participantIds.allSatisfy { s.person($0) != nil },
        "Participante inexistente o de otro espacio")
      try require(
        (0...100000).contains(e.capacity) && (0...100000).contains(e.volunteerCapacity),
        "Capacidad inválida")
      try require(e.participantIds.count <= e.capacity, "Se excedió la capacidad del evento")
      try require(
        e.volunteerCapacity <= e.capacity, "La capacidad de voluntarios supera la del evento")
      try require(
        s.volunteers.filter { $0.eventId == e.id && $0.status.occupiesSeat }.count
          <= e.volunteerCapacity, "Se excedió la capacidad de voluntarios")
    }
    try unique(s.attendance.map { $0.eventId + "/" + $0.personId }, "Asistencia duplicada")
    for a in s.attendance {
      try note(a.notes)
      try require(
        s.event(a.eventId)?.participantIds.contains(a.personId) == true,
        "Solo se registra asistencia para personas en la lista del evento")
    }
    try unique(s.volunteers.map { $0.eventId + "/" + $0.personId }, "Voluntariado duplicado")
    for v in s.volunteers {
      try note(v.notes)
      try require(
        s.event(v.eventId) != nil && s.person(v.personId) != nil, "Voluntario o evento inexistente")
      try require(
        !v.status.occupiesSeat || s.event(v.eventId)!.participantIds.contains(v.personId),
        "Los voluntarios seleccionados deben estar en la lista del evento")
    }
    for t in s.templates {
      try title(t.name)
      try require(
        (24...240).contains(t.marginTop) && (40...240).contains(t.marginBottom),
        "Márgenes inválidos")
      try require((1...200).contains(t.blocks.count), "La plantilla necesita entre 1 y 200 bloques")
      try unique(t.blocks.map(\.id), "Bloque duplicado")
      if let bg = t.backgroundPDF {
        try require(
          bg.count <= 14_000_000
            && Data(base64Encoded: bg)?.starts(with: Data("%PDF-".utf8)) == true,
          "PDF de fondo inválido")
      }
      for b in t.blocks {
        try identifier(b.id)
        switch b.type {
        case .text:
          try require(
            b.text != nil && b.size != nil && (8...36).contains(b.size!), "Bloque de texto inválido"
          )
          try note(b.text!)
        case .columns:
          try require(b.left != nil && b.right != nil, "Columnas incompletas")
          try note(b.left!)
          try note(b.right!)
        case .image:
          try require(b.width != nil && (20...500).contains(b.width!), "Ancho de imagen inválido")
          guard let data = b.data, let comma = data.firstIndex(of: ",") else {
            throw RuleError("Imagen incompleta")
          }
          try require(
            data.count <= 14_000_000
              && (data.hasPrefix("data:image/png;base64,")
                || data.hasPrefix("data:image/jpeg;base64,"))
              && Data(base64Encoded: String(data[data.index(after: comma)...])) != nil,
            "Imagen inválida")
        case .participants, .pageBreak: break
        }
        let keys = Set((try WorkspaceCodec.object(b) as! [String: Any]).keys)
        let allowed: Set<String>
        switch b.type {
        case .text: allowed = ["id", "type", "text", "size"]
        case .columns: allowed = ["id", "type", "left", "right"]
        case .image: allowed = ["id", "type", "data", "width"]
        default: allowed = ["id", "type"]
        }
        try require(keys == allowed, "Campos de bloque inválidos")
      }
    }
  }
  static func heads(_ revisions: [Revision]) -> [String] {
    let parents = Set(revisions.flatMap(\.parents))
    return revisions.filter { !parents.contains($0.id) }.map(\.id).sorted()
  }
  static func validate(_ db: Database) throws {
    try require(db.schemaVersion == 1, "Versión de datos no compatible")
    try unique(db.spaces.map(\.id), "Espacios duplicados")
    for b in db.spaces {
      try identifier(b.id)
      try require(!b.revisions.isEmpty, "Historial vacío")
      try unique(b.revisions.map(\.id), "Revisiones duplicadas")
      let lookup = Dictionary(uniqueKeysWithValues: b.revisions.map { ($0.id, $0) })
      for r in b.revisions {
        try identifier(r.id)
        try title(r.author)
        try title(r.label)
        RevisionStamps.lock.lock()
        let stamped =
          RevisionStamps.fractional.date(from: r.timestamp) != nil
          || RevisionStamps.basic.date(from: r.timestamp) != nil
        RevisionStamps.lock.unlock()
        try require(stamped, "Fecha de revisión inválida")
        try require(r.data.id == b.id, "Revisión de otro espacio")
        try unique(r.parents, "Padres duplicados")
        try require(
          r.parents.allSatisfy { lookup[$0] != nil && $0 != r.id }, "Historial incompleto")
        try validate(r.data)
      }
      var visited = Set<String>()
      var progress = true
      while progress {
        progress = false
        for r in b.revisions
        where !visited.contains(r.id) && r.parents.allSatisfy({ visited.contains($0) }) {
          visited.insert(r.id)
          progress = true
        }
      }
      try require(visited.count == lookup.count, "Ciclo en el historial")
      try require(
        b.revisions.filter { $0.parents.isEmpty }.count == 1,
        "El espacio necesita una única revisión inicial")
      try require(b.heads.sorted() == heads(b.revisions), "Cabeceras de historial inválidas")
    }
  }
  static func participation(_ s: Space, person: String, filter f: ReportFilter = .init()) throws
    -> Participation
  {
    try ParticipationIndex(s).participation(person: person, filter: f)
  }
  /// Reuses one index for an entire report; searching the UI never recalculates records.
  static func report(_ s: Space, filter: ReportFilter = .init()) throws -> [String: Participation] {
    let index = ParticipationIndex(s)
    var result: [String: Participation] = [:]
    for person in s.people { result[person.id] = try index.participation(person: person.id, filter: filter) }
    return result
  }
  /// Every subtotal is evaluated from records, never by averaging rounded percentages.
  /// Period/group scope is identical across the total, components and their categories.
  static func participationBreakdown(
    _ s: Space, person: String, period: String = "",
    group: String = ""
  ) throws -> [ParticipationSlice] {
    let index = ParticipationIndex(s)
    let scope = ReportFilter(periodId: period, groupId: group)
    var rows = [
      ParticipationSlice(
        id: "overall", name: "", kind: .overall,
        result: try index.participation(person: person, filter: scope))
    ]
    for component in s.components {
      var filter = scope
      filter.componentId = component.id
      rows.append(
        ParticipationSlice(
          id: "component-" + component.id, name: component.name,
          kind: .component, componentId: component.id,
          result: try index.participation(person: person, filter: filter)))
      for category in s.categories where category.componentId == component.id {
        filter.categoryId = category.id
        rows.append(
          ParticipationSlice(
            id: "category-" + category.id, name: category.name,
            kind: .category, componentId: component.id,
            result: try index.participation(person: person, filter: filter)))
      }
      filter.categoryId = ""
      filter.uncategorized = true
      rows.append(
        ParticipationSlice(
          id: "uncategorized-" + component.id, name: "",
          kind: .uncategorized, componentId: component.id,
          result: try index.participation(person: person, filter: filter)))
    }
    return rows
  }
  static func suggestions(_ s: Space, event: Activity) -> [Suggestion] {
    let cutoff = event.date + "T" + event.time
    var previous: [Activity] = []
    previous.reserveCapacity(s.events.count)
    for item in s.events
    where item.id != event.id && item.canRecord && item.date + "T" + item.time < cutoff {
      previous.append(item)
    }
    var completedEvents: [String: Set<String>] = [:]
    for record in s.volunteers where record.status == .completed {
      completedEvents[record.personId, default: []].insert(record.eventId)
    }
    var roster: [String: Set<String>] = [:]
    for item in previous where item.countsForAttendance {
      roster[item.id] = Set(item.participantIds)
    }
    var seenRecord = Set<String>()
    var firstPresent = Set<String>()
    seenRecord.reserveCapacity(s.attendance.count)
    for record in s.attendance {
      let key = record.personId + "/" + record.eventId
      if seenRecord.insert(key).inserted, record.status == .present { firstPresent.insert(key) }
    }
    var people: [String: Person] = [:]
    people.reserveCapacity(s.people.count)
    for person in s.people where people[person.id] == nil { people[person.id] = person }
    return s.volunteers.filter { $0.eventId == event.id && $0.status == .interested }.compactMap {
      v in
      guard let p = people[v.personId] else { return nil }
      let done = completedEvents[p.id] ?? []
      var completed = 0
      var present = 0
      for item in previous {
        if done.contains(item.id) { completed += 1 }
        if item.countsForAttendance, roster[item.id]?.contains(p.id) == true,
          firstPresent.contains(p.id + "/" + item.id)
        {
          present += 1
        }
      }
      return Suggestion(
        id: p.id, name: p.name, active: p.active, completed: completed, present: present)
    }.sorted { a, b in
      if a.score != b.score { return a.score > b.score }
      let c = a.name.compare(b.name, locale: Locale(identifier: "es"))
      return c == .orderedSame ? a.id < b.id : c == .orderedAscending
    }
  }
  static func upsert<T: Entity>(_ list: inout [T], _ value: T) {
    if let i = list.firstIndex(where: { $0.id == value.id }) {
      list[i] = value
    } else {
      list.append(value)
    }
  }
  static func apply(_ edit: Edit, to original: Space) throws -> Space {
    var s = original
    switch edit {
    case .settings(let name, let zone):
      s.name = name
      s.timeZone = zone
    case .person(let v): upsert(&s.people, v)
    case .group(let v): upsert(&s.groups, v)
    case .membership(let v): upsert(&s.memberships, v)
    case .period(let v): upsert(&s.periods, v)
    case .component(let v): upsert(&s.components, v)
    case .category(let v): upsert(&s.categories, v)
    case .template(let v): upsert(&s.templates, v)
    case .event(let v):
      let prior = s.event(v.id)
      try require(prior?.status != .cancelled, "Reabre el evento antes de editarlo")
      try require(
        prior.map { $0.status == v.status } ?? (v.status == .draft),
        "Usa la acción de estado para programar, completar o cancelar")
      try require(
        v.participantIds.allSatisfy {
          prior?.participantIds.contains($0) == true || s.person($0)?.active == true
        }, "No se pueden añadir personas inactivas")
      for a in s.attendance where a.eventId == v.id && !v.participantIds.contains(a.personId) {
        try require(
          a.status == .pending && a.notes.isEmpty,
          "No se puede quitar a una persona con asistencia o notas registradas")
      }
      s.attendance.removeAll { $0.eventId == v.id && !v.participantIds.contains($0.personId) }
      upsert(&s.events, v)
    case .duplicate(let event, let id, let date):
      guard var e = s.event(event) else { throw RuleError("Evento inexistente") }
      try require(s.event(id) == nil, "Identificador ya utilizado")
      e.id = id
      e.name = String(e.name.prefix(232)) + " (copia)"
      e.date = date
      e.status = .draft
      e.participantIds = []
      s.events.append(e)
    case .eventStatus(let id, let status):
      guard let i = s.events.firstIndex(where: { $0.id == id }) else {
        throw RuleError("Evento inexistente")
      }
      try require(s.events[i].status.next.contains(status), "Cambio de estado no permitido")
      if status == .draft {
        try require(
          !s.attendance.contains { $0.eventId == id && $0.status != .pending }
            && !s.volunteers.contains { $0.eventId == id && $0.status.occupiesSeat },
          "El evento tiene participación; no puede volver a borrador")
      }
      s.events[i].status = status
    case .attendance(let a):
      guard let e = s.event(a.eventId) else { throw RuleError("Evento inexistente") }
      try require(e.canRecord, "Registra asistencia en un evento programado o completado")
      try require(
        e.participantIds.contains(a.personId), "La persona no está en la lista del evento")
      try require(
        s.record(a.eventId, a.personId).map { $0.id == a.id } ?? true,
        "Identificador de asistencia incorrecto")
      try require(
        s.attendance.first { $0.id == a.id }.map {
          $0.eventId == a.eventId && $0.personId == a.personId
        } ?? true, "No se puede reasignar una asistencia")
      upsert(&s.attendance, a)
    case .volunteer(let v):
      guard let i = s.events.firstIndex(where: { $0.id == v.eventId }), let p = s.person(v.personId)
      else { throw RuleError("Evento o persona inexistente") }
      try require(s.events[i].status != .cancelled, "Evento cancelado")
      let old = s.volunteers.first { $0.eventId == v.eventId && $0.personId == v.personId }
      try require(old.map { $0.id == v.id } ?? true, "Identificador de voluntariado incorrecto")
      try require(
        s.volunteers.first { $0.id == v.id }.map {
          $0.personId == v.personId && $0.eventId == v.eventId
        } ?? true, "No se puede reasignar un voluntariado")
      try require(
        old.map { $0.status == v.status || $0.status.next.contains(v.status) }
          ?? (v.status == .interested), "Transición de voluntariado no permitida")
      if old == nil || (old!.status != v.status && [.interested, .selected].contains(v.status)) {
        try require(p.active, "No se pueden inscribir o seleccionar personas inactivas")
        try require(
          s.events[i].status != .completed, "Reabre el evento antes de inscribir o seleccionar")
      }
      if v.status.occupiesSeat && !s.events[i].participantIds.contains(p.id) {
        s.events[i].participantIds.append(p.id)
      }
      upsert(&s.volunteers, v)
    case .delete(let collection, let id):
      func remove<T: Entity>(_ list: inout [T]) throws {
        try require(list.contains { $0.id == id }, "Registro inexistente")
        list.removeAll { $0.id == id }
      }
      switch collection {
      case .people:
        try require(
          !s.memberships.contains { $0.personId == id }
            && !s.events.contains { $0.participantIds.contains(id) }
            && !s.attendance.contains { $0.personId == id }
            && !s.volunteers.contains { $0.personId == id },
          "La persona sigue en uso.")
        try remove(&s.people)
      case .groups:
        try require(!s.memberships.contains { $0.groupId == id }, "El grupo sigue en uso.")
        try remove(&s.groups)
      case .memberships: try remove(&s.memberships)
      case .periods: try remove(&s.periods)
      case .components:
        try require(
          !s.categories.contains { $0.componentId == id }
            && !s.events.contains { $0.componentId == id },
          "El componente sigue en uso.")
        try remove(&s.components)
      case .categories:
        try require(!s.events.contains { $0.categoryId == id }, "La categoría sigue en uso.")
        try remove(&s.categories)
      case .templates: try remove(&s.templates)
      case .events:
        try require(
          s.event(id)?.status == .draft, "Solo se eliminan borradores; cancela los demás eventos")
        try remove(&s.events)
        s.attendance.removeAll { $0.eventId == id }
        s.volunteers.removeAll { $0.eventId == id }
      }
    }
    try validate(s)
    return s
  }
  static func create(
    _ db: Database, name: String, author: String, zone: String = "America/Puerto_Rico",
    label: String = "Crear espacio"
  ) throws -> Database {
    var result = db
    var s = Space(name: name)
    s.timeZone = zone
    try validate(s)
    try title(author)
    try title(label)
    let r = Revision(parents: [], author: author, label: label, data: s)
    result.spaces.append(Branch(id: s.id, revisions: [r], heads: [r.id]))
    return result
  }
  static func append(_ db: Database, space: String, data: Space, label: String, author: String)
    throws -> Database
  {
    guard let i = db.spaces.firstIndex(where: { $0.id == space }) else {
      throw RuleError("Espacio inexistente")
    }
    try require(data.id == space, "Datos de otro espacio")
    try validate(data)
    try title(author)
    try title(label)
    var result = db
    let r = Revision(parents: result.spaces[i].heads, author: author, label: label, data: data)
    result.spaces[i].revisions.append(r)
    result.spaces[i].heads = [r.id]
    return result
  }
  static func execute(_ db: Database, space: String, edit: Edit, label: String, author: String)
    throws -> Database
  {
    guard let b = db.spaces.first(where: { $0.id == space }) else {
      throw RuleError("Espacio inexistente")
    }
    return try append(
      db, space: space, data: apply(edit, to: b.current()), label: label, author: author)
  }
  static func restore(
    _ db: Database, space: String, revision: String, author: String, label: String? = nil
  ) throws -> Database {
    guard let b = db.spaces.first(where: { $0.id == space }),
      let r = b.revisions.first(where: { $0.id == revision })
    else { throw RuleError("Revisión inexistente") }
    let text =
      label
      ?? (b.conflicted
        ? "Resolver conflicto conservando historial" : "Restaurar: " + String(r.label.prefix(225)))
    return try append(db, space: space, data: r.data, label: text, author: author)
  }
  static func merge(_ local: Database, _ remote: Database) throws -> Database {
    try validate(local)
    try validate(remote)
    var result = local
    for incoming in remote.spaces {
      guard let i = result.spaces.firstIndex(where: { $0.id == incoming.id }) else {
        result.spaces.append(incoming)
        continue
      }
      var revisions = result.spaces[i].revisions
      for r in incoming.revisions {
        if let old = revisions.first(where: { $0.id == r.id }) {
          try require(
            old == r, "El archivo altera una revisión existente; no se importó ningún cambio")
        } else {
          revisions.append(r)
        }
      }
      result.spaces[i].revisions = revisions
      result.spaces[i].heads = heads(revisions)
    }
    try validate(result)
    return result
  }
}

extension Rules {
  /// One event, no other scope: same counts as the full index, without walking every person.
  private static func eventTotal(_ space: Space, _ eventId: String) -> Participation {
    guard let event = space.events.first(where: { $0.id == eventId }) else { return Participation() }
    var known = Set<String>()
    known.reserveCapacity(space.people.count)
    for person in space.people { known.insert(person.id) }
    var status: [String: AttendanceStatus] = [:]
    for record in space.attendance where record.eventId == eventId {
      status[record.personId] = record.status
    }
    var total = Participation()
    let counted = event.canRecord && event.countsForAttendance
    for id in event.participantIds where known.contains(id) {
      if !counted {
        total.excluded += 1
        continue
      }
      switch status[id] ?? .pending {
      case .present: total.present += 1
      case .absent: total.absent += 1
      case .excused: total.excused += 1
      case .pending: total.pending += 1
      }
    }
    return total
  }
  /// Aggregate records, not an average of per-person percentages.
  static func aggregate(_ space: Space, filter: ReportFilter = .init()) throws -> Participation {
    if !filter.eventId.isEmpty && filter.periodId.isEmpty && filter.groupId.isEmpty
      && filter.componentId.isEmpty && filter.categoryId.isEmpty && !filter.uncategorized
    {
      return eventTotal(space, filter.eventId)
    }
    var total = Participation()
    for r in try report(space, filter: filter).values {
      total.present += r.present
      total.absent += r.absent
      total.pending += r.pending
      total.excused += r.excused
      total.excluded += r.excluded
    }
    return total
  }
}

/// Immutable read index. The event roster remains the source of eligibility; missing records
/// are pending, and membership is evaluated at the event date, never at today's date.
struct ParticipationIndex {
  private let space: Space
  private let people: Set<String>
  private let events: [String: [Activity]]
  private let records: [String: [String: AttendanceStatus]]
  private let memberships: [String: [Membership]]
  init(_ space: Space) {
    self.space = space
    people = Set(space.people.map(\.id))
    var events: [String: [Activity]] = [:]
    for event in space.events {
      for person in event.participantIds { events[person, default: []].append(event) }
    }
    self.events = events
    var records: [String: [String: AttendanceStatus]] = [:]
    for record in space.attendance { records[record.personId, default: [:]][record.eventId] = record.status }
    self.records = records
    memberships = Dictionary(grouping: space.memberships, by: \.personId)
  }
  func participation(person: String, filter f: ReportFilter = .init()) throws -> Participation {
    try require(people.contains(person), "Persona inexistente")
    let period = space.periods.first { $0.id == f.periodId }
    try require(f.periodId.isEmpty || period != nil, "Período inexistente")
    try require(f.groupId.isEmpty || space.groups.contains { $0.id == f.groupId }, "Grupo inexistente")
    var result = Participation()
    for event in events[person] ?? [] {
      if let period, event.date < period.start || event.date > period.end { continue }
      if !f.groupId.isEmpty && !(memberships[person] ?? []).contains(where: {
        $0.groupId == f.groupId && $0.start <= event.date && ($0.end == nil || $0.end! >= event.date)
      }) { continue }
      if !f.componentId.isEmpty && event.componentId != f.componentId { continue }
      if !f.categoryId.isEmpty && event.categoryId != f.categoryId { continue }
      if !f.eventId.isEmpty && event.id != f.eventId { continue }
      if f.uncategorized && event.categoryId != nil { continue }
      if !event.canRecord || !event.countsForAttendance { result.excluded += 1; continue }
      switch records[person]?[event.id] ?? .pending {
      case .present: result.present += 1
      case .absent: result.absent += 1
      case .excused: result.excused += 1
      case .pending: result.pending += 1
      }
    }
    return result
  }
}

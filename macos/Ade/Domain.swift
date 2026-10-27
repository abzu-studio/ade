import Foundation

func newID() -> String { UUID().uuidString.lowercased() }
struct RuleError: LocalizedError {
  let message: String
  var errorDescription: String? { message }
  init(_ message: String) { self.message = message }
}
func require(_ condition: Bool, _ message: String) throws {
  if !condition { throw RuleError(message) }
}
protocol Entity: Codable, Equatable, Identifiable where ID == String {}
struct Person: Entity {
  var id = newID()
  var name = ""
  var email = ""
  var active = true
  var notes = ""
}
struct Named: Entity {
  var id = newID()
  var name = ""
}
struct Membership: Entity {
  var id = newID()
  var personId = ""
  var groupId = ""
  var start = Day.today
  var end: String?
}
struct Period: Entity {
  var id = newID()
  var name = ""
  var start = Day.today
  var end = Day.today
}
struct Category: Entity {
  var id = newID()
  var name = ""
  var componentId = ""
}
enum EventStatus: String, Codable, CaseIterable {
  case draft, scheduled, completed, cancelled
  var next: [Self] {
    switch self {
    case .draft: [.scheduled, .cancelled]
    case .scheduled: [.completed, .cancelled, .draft]
    case .completed: [.scheduled, .cancelled]
    case .cancelled: [.scheduled]
    }
  }
}
enum AttendanceStatus: String, Codable, CaseIterable { case present, absent, excused, pending }
enum VolunteerStatus: String, Codable, CaseIterable {
  case interested, selected, completed, declined, absent
  var occupiesSeat: Bool { [.selected, .completed, .absent].contains(self) }
  var next: [Self] {
    switch self {
    case .interested: [.selected, .declined]
    case .selected: [.completed, .declined, .absent]
    case .declined: [.interested]
    case .completed, .absent: []
    }
  }
}
struct Activity: Entity {
  var id = newID()
  var name = ""
  var date = Day.today
  var time = "09:00"
  var componentId = ""
  var categoryId: String?
  var status: EventStatus = .draft
  var capacity = 30
  var volunteerCapacity = 5
  var countsForAttendance = true
  var participantIds: [String] = []
  var notes = ""
  var canRecord: Bool { status == .scheduled || status == .completed }
}
struct Attendance: Entity {
  var id = newID()
  var eventId: String
  var personId: String
  var status: AttendanceStatus = .pending
  var notes = ""
}
struct Volunteer: Entity {
  var id = newID()
  var eventId: String
  var personId: String
  var status: VolunteerStatus = .interested
  var notes = ""
}
enum BlockKind: String, Codable, CaseIterable { case text, columns, image, participants, pageBreak }
struct TemplateBlock: Entity {
  var id = newID()
  var type: BlockKind = .text
  var text: String?
  var size: Double?
  var left: String?
  var right: String?
  var data: String?
  var width: Double?
  static func make(_ kind: BlockKind) -> Self {
    switch kind {
    case .text: Self(type: kind, text: "{{event.name}}", size: 18)
    case .columns: Self(type: kind, left: "{{space.name}}", right: "{{event.date}}")
    case .image: Self(type: kind, data: "", width: 240)
    default: Self(type: kind)
    }
  }
}
struct DocumentTemplate: Entity {
  var id = newID()
  var name = ""
  var marginTop: Double = 48
  var marginBottom: Double = 48
  var backgroundPDF: String?
  var blocks: [TemplateBlock] = [.make(.text), .make(.participants)]
  enum CodingKeys: String, CodingKey {
    case id, name, marginTop, marginBottom, backgroundPDF, blocks
  }
  init() {}
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    name = try c.decode(String.self, forKey: .name)
    marginTop = try c.decodeIfPresent(Double.self, forKey: .marginTop) ?? 48
    marginBottom = try c.decodeIfPresent(Double.self, forKey: .marginBottom) ?? 48
    backgroundPDF = try c.decodeIfPresent(String.self, forKey: .backgroundPDF)
    blocks = try c.decode([TemplateBlock].self, forKey: .blocks)
  }
}
struct Space: Entity {
  var id = newID()
  var name: String
  var timeZone = "America/Puerto_Rico"
  var people: [Person] = []
  var groups: [Named] = []
  var memberships: [Membership] = []
  var periods: [Period] = []
  var components: [Named] = []
  var categories: [Category] = []
  var events: [Activity] = []
  var attendance: [Attendance] = []
  var volunteers: [Volunteer] = []
  var templates: [DocumentTemplate] = []
  func person(_ id: String) -> Person? { people.first { $0.id == id } }
  func event(_ id: String) -> Activity? { events.first { $0.id == id } }
  func record(_ event: String, _ person: String) -> Attendance? {
    attendance.first { $0.eventId == event && $0.personId == person }
  }
  func member(_ person: String, group: String, on day: String) -> Bool {
    memberships.contains {
      $0.personId == person && $0.groupId == group && $0.start <= day
        && ($0.end == nil || $0.end! >= day)
    }
  }
}
struct Revision: Entity {
  var id = newID()
  var parents: [String]
  var timestamp = ISO8601DateFormatter().string(from: Date())
  var author: String
  var label: String
  var data: Space
}
struct Branch: Entity {
  var id: String
  var revisions: [Revision]
  var heads: [String]
  var visible: Revision? { revisions.first { $0.id == heads.first } }
  var conflicted: Bool { heads.count != 1 }
  func current() throws -> Space {
    try require(!conflicted, "Resuelve el conflicto en Historial antes de editar.")
    guard let data = visible?.data else { throw RuleError("Espacio sin revisión") }
    return data
  }
}
struct Database: Codable, Equatable {
  var schemaVersion = 1
  var spaces: [Branch] = []
}
enum Day {
  private static let lock = NSLock()
  private static let utc: DateFormatter = {
    let format = DateFormatter()
    format.locale = Locale(identifier: "en_US_POSIX")
    format.timeZone = TimeZone(secondsFromGMT: 0)
    format.dateFormat = "yyyy-MM-dd"
    format.isLenient = false
    return format
  }()
  private static let local: DateFormatter = {
    let format = DateFormatter()
    format.locale = Locale(identifier: "en_US_POSIX")
    format.dateFormat = "yyyy-MM-dd"
    format.isLenient = false
    return format
  }()
  static var today: String {
    lock.lock()
    defer { lock.unlock() }
    return local.string(from: Date())
  }
  static func string(_ date: Date) -> String {
    lock.lock()
    defer { lock.unlock() }
    return utc.string(from: date)
  }
  static func date(_ text: String) -> Date? {
    guard text.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
      return nil
    }
    lock.lock()
    let parsed = utc.date(from: text)
    let round = parsed.map { utc.string(from: $0) }
    lock.unlock()
    guard let parsed, round == text else { return nil }
    return parsed
  }
}

/// Accepts `9:00`, `09:00`, and `9:5`. Stored events stay `HH:mm`.
func canonicalClock(_ raw: String) -> String? {
  let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
  let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
  guard parts.count == 2,
    (1...2).contains(parts[0].count), (1...2).contains(parts[1].count),
    parts[0].allSatisfy(\.isNumber), parts[1].allSatisfy(\.isNumber),
    let hour = Int(parts[0]), let minute = Int(parts[1]),
    (0...23).contains(hour), (0...59).contains(minute)
  else { return nil }
  return String(format: "%02d:%02d", hour, minute)
}

/// Domain failures are written in Spanish. English screens translate the known sentences.
enum RuleCopy {
  static func explain(_ message: String, english: Bool) -> String {
    guard english else { return message }
    if let exact = englishExact[message] { return exact }
    let date = "Fecha inválida: "
    if message.hasPrefix(date) { return "Invalid date: " + message.dropFirst(date.count) }
    let variable = "Variable desconocida: "
    if message.hasPrefix(variable) { return "Unknown variable: " + message.dropFirst(variable.count) }
    return message
  }

  private static let englishExact = [
    "El texto supera 20 000 caracteres.": "The text is longer than 20,000 characters.",
    "Identificador inválido": "Invalid identifier.",
    "El nombre es obligatorio (máximo 240 caracteres).": "A name is required (240 characters at most).",
    "Zona horaria inválida": "Invalid time zone.",
    "Identificadores duplicados en el espacio": "Duplicate identifiers in the space.",
    "Correo electrónico inválido": "Invalid email.",
    "Componente de categoría inexistente": "That category's component does not exist.",
    "El período termina antes de comenzar": "The period ends before it starts.",
    "Fechas de membresía inválidas": "Invalid membership dates.",
    "Miembro o grupo inexistente": "That membership's person or group does not exist.",
    "Las membresías de una persona en el mismo grupo no pueden solaparse":
      "A person's memberships in the same group cannot overlap.",
    "Hora inválida": "Invalid time. Use HH:mm, for example 09:00.",
    "Todo evento necesita un componente válido": "Every event needs a component.",
    "La categoría no pertenece al componente": "That category does not belong to the component.",
    "Participante duplicado": "Duplicate participant.",
    "Participante inexistente o de otro espacio": "A participant does not exist in this space.",
    "Capacidad inválida": "Invalid capacity.",
    "Se excedió la capacidad del evento": "The event is over capacity.",
    "La capacidad de voluntarios supera la del evento":
      "Volunteer capacity is higher than the event capacity.",
    "Se excedió la capacidad de voluntarios": "Volunteer capacity is full.",
    "Asistencia duplicada": "Duplicate attendance.",
    "Solo se registra asistencia para personas en la lista del evento":
      "Attendance is only recorded for people on the event roster.",
    "Voluntariado duplicado": "Duplicate volunteering.",
    "Voluntario o evento inexistente": "That volunteer or event does not exist.",
    "Los voluntarios seleccionados deben estar en la lista del evento":
      "Selected volunteers must be on the event roster.",
    "Márgenes inválidos": "Invalid margins.",
    "La plantilla necesita entre 1 y 200 bloques": "A template needs between 1 and 200 blocks.",
    "Bloque duplicado": "Duplicate block.",
    "PDF de fondo inválido": "Invalid background PDF.",
    "Bloque de texto inválido": "Invalid text block.",
    "Columnas incompletas": "Incomplete columns.",
    "Ancho de imagen inválido": "Invalid image width.",
    "Imagen incompleta": "Incomplete image.",
    "Imagen inválida": "Invalid image.",
    "Campos de bloque inválidos": "Invalid block fields.",
    "Versión de datos no compatible": "Incompatible data version.",
    "Historial vacío": "Empty history.",
    "Fecha de revisión inválida": "Invalid revision date.",
    "Revisión de otro espacio": "Revision from another space.",
    "Ciclo en el historial": "Cycle in the history.",
    "Cabeceras de historial inválidas": "Invalid history heads.",
    "Reabre el evento antes de editarlo": "Reopen the event before editing it.",
    "Usa la acción de estado para programar, completar o cancelar":
      "Use the status action to schedule, complete, or cancel.",
    "No se pueden añadir personas inactivas": "Inactive people cannot be added.",
    "No se puede quitar a una persona con asistencia o notas registradas":
      "A person with recorded attendance or notes cannot be removed.",
    "Evento inexistente": "Event not found.",
    "Identificador ya utilizado": "That identifier is already used.",
    "Cambio de estado no permitido": "That status change is not allowed.",
    "El evento tiene participación; no puede volver a borrador":
      "The event has participation and cannot return to draft.",
    "Registra asistencia en un evento programado o completado":
      "Record attendance on a scheduled or completed event.",
    "La persona no está en la lista del evento": "That person is not on the event roster.",
    "Identificador de asistencia incorrecto": "Wrong attendance identifier.",
    "No se puede reasignar una asistencia": "An attendance record cannot be reassigned.",
    "Evento o persona inexistente": "Event or person not found.",
    "Evento cancelado": "The event is cancelled.",
    "Identificador de voluntariado incorrecto": "Wrong volunteering identifier.",
    "No se puede reasignar un voluntariado": "A volunteer record cannot be reassigned.",
    "Transición de voluntariado no permitida": "That volunteer transition is not allowed.",
    "No se pueden inscribir o seleccionar personas inactivas":
      "Inactive people cannot be marked interested or selected.",
    "Reabre el evento antes de inscribir o seleccionar":
      "Reopen the event before marking interest or selecting.",
    "Registro inexistente": "Record not found.",
    "Solo se eliminan borradores; cancela los demás eventos":
      "Only drafts can be deleted. Cancel the other events.",
    "La persona sigue en uso.": "This person is still in use.",
    "El grupo sigue en uso.": "This group is still in use.",
    "El componente sigue en uso.": "This component is still in use.",
    "La categoría sigue en uso.": "This category is still in use.",
    "Espacio inexistente": "Space not found.",
    "Datos de otro espacio": "Data from another space.",
    "Revisión inexistente": "Revision not found.",
    "El archivo altera una revisión existente; no se importó ningún cambio":
      "The file changes an existing revision. Nothing was imported.",
    "El archivo contiene campos desconocidos; se conserva sin modificar.":
      "The file contains unknown fields. It was left unchanged.",
    "El archivo supera 100 MB.": "The file is larger than 100 MB.",
    "El archivo supera el tamaño permitido": "The file is larger than the allowed size.",
    "Resuelve el conflicto en Historial antes de editar.":
      "Resolve the conflict in History before editing.",
    "Espacio sin revisión": "Space with no revision.",
    "No hay copia anterior": "There is no previous backup.",
    "Selecciona un evento": "Select an event.",
    "Período inexistente": "Period not found.",
    "Grupo inexistente": "Group not found.",
    "Persona inexistente": "Person not found.",
    "No se pudo leer la imagen": "The image could not be read.",
    "PDF de fondo inválido o protegido": "The background PDF is invalid or protected.",
    "PDF inválido o protegido": "The PDF is invalid or protected.",
    "No se pudo crear el PDF": "The PDF could not be created.",
  ]
}

/// JSON remains compatible with Adê v1 exports, including explicit nullable fields.
enum WorkspaceCodec {
  static func object<T: Encodable>(_ value: T) throws -> Any {
    let raw = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
    func normalize(_ node: Any) -> Any {
      if let list = node as? [Any] { return list.map(normalize) }
      guard var dict = node as? [String: Any] else { return node }
      if dict["participantIds"] != nil { dict["categoryId"] = dict["categoryId"] ?? NSNull() }
      if dict["groupId"] != nil && dict["start"] != nil { dict["end"] = dict["end"] ?? NSNull() }
      if dict["blocks"] != nil { dict["backgroundPDF"] = dict["backgroundPDF"] ?? NSNull() }
      return dict.mapValues(normalize)
    }
    return normalize(raw)
  }
  static func encode<T: Encodable>(_ value: T) throws -> Data {
    try JSONSerialization.data(
      withJSONObject: object(value),
      options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
  }
  static func decode(_ data: Data) throws -> Database {
    try require(data.count <= 100_000_000, "El archivo supera 100 MB.")
    let db = try JSONDecoder().decode(Database.self, from: data)
    let raw = try JSONSerialization.jsonObject(with: data)
    // Reject unknown fields rather than silently dropping data from a newer format.
    func known(_ source: Any, _ target: Any) throws {
      if let a = source as? [String: Any], let b = target as? [String: Any] {
        try require(
          Set(a.keys).isSubset(of: Set(b.keys)),
          "El archivo contiene campos desconocidos; se conserva sin modificar.")
        for (k, v) in a { if let t = b[k] { try known(v, t) } }
      } else if let a = source as? [Any], let b = target as? [Any] {
        for (x, y) in zip(a, b) { try known(x, y) }
      }
    }
    try known(raw, object(db))
    try Rules.validate(db)
    return db
  }
}

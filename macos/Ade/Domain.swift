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
  static var today: String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: Date())
  }
  static func string(_ date: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(secondsFromGMT: 0)
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: date)
  }
  static func date(_ text: String) -> Date? {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(secondsFromGMT: 0)
    f.dateFormat = "yyyy-MM-dd"
    f.isLenient = false
    guard text.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
      let d = f.date(from: text), string(d) == text
    else { return nil }
    return d
  }
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

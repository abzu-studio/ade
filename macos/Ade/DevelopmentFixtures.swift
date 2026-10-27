#if DEBUG
import Foundation

// Synthetic fixtures for local development and UI tests; absent from Release.

extension AppModel {
  func loadDemo() async {
    guard !busy && pending == nil && !unreadable else { return }
    do {
      var next = try Rules.create(database, name: "Espacio de ejemplo", author: author)
      let id = next.spaces.last!.id
      let space = DemoData.space(id: id)
      next = try Rules.append(
        next, space: id, data: space, label: "Cargar demo · datos ficticios", author: author)
      if await commit(next) { openSpace(id) }
    } catch { self.error = explain(error) }
  }
}
enum DemoData {
  static func space(id: String) -> Space {
    var s = Space(id: id, name: "Espacio de ejemplo")
    let names = [
      "Persona 01", "Persona 02", "Persona 03", "Persona 04", "Persona 05",
      "Persona 06", "Persona 07", "Persona 08", "Persona 09",
    ]
    s.people = names.enumerated().map {
      Person(id: "person-\($0.offset)", name: $0.element, notes: "Datos ficticios de demostración")
    }
    s.groups = (0..<3).map { Named(id: "group-\($0)", name: "Grupo " + ["A", "B", "C"][$0]) }
    s.memberships = s.people.enumerated().map {
      Membership(
        id: "member-\($0.offset)", personId: $0.element.id, groupId: "group-\($0.offset/3)",
        start: "2026-08-01", end: "2026-12-31")
    }
    s.periods = [
      Period(
        id: "period-demo", name: "Período ago–dic 2026", start: "2026-08-01", end: "2026-12-31")
    ]
    s.components = [
      Named(id: "laboratory", name: "Laboratorio"), Named(id: "seminar", name: "Seminario"),
      Named(id: "volunteering", name: "Voluntariado"),
    ]
    s.categories = [
      Category(id: "practice", name: "Práctica", componentId: "laboratory"),
      Category(id: "guest", name: "Invitado", componentId: "seminar"),
      Category(id: "community", name: "Comunidad", componentId: "volunteering"),
    ]
    let titles = [
      "Lab 4 · PCR", "Charla · Bioética", "Lab 5 · Electroforesis", "Limpieza costera",
      "Lab 3 · Microscopía", "Lab 2 · Pipeteo", "Cine-foro", "Lab 1 · Seguridad", "Orientación",
    ]
    let dates = [
      "2026-10-27", "2026-10-29", "2026-11-03", "2026-11-07", "2026-10-20", "2026-10-13",
      "2026-10-09", "2026-10-06", "2026-10-01",
    ]
    let states: [EventStatus] = [
      .scheduled, .scheduled, .draft, .scheduled, .completed, .completed, .cancelled, .completed,
      .completed,
    ]
    for i in titles.indices {
      let component =
        i == 1 || i == 6 || i == 8 ? "seminar" : i == 3 ? "volunteering" : "laboratory"
      var e = Activity(
        id: "event-\(i)", name: titles[i], date: dates[i],
        time: i == 1 ? "18:00" : i == 3 ? "08:00" : "13:00", componentId: component,
        categoryId: component == "seminar"
          ? "guest" : component == "volunteering" ? "community" : "practice", status: states[i],
        capacity: i == 1 ? 40 : 24, volunteerCapacity: 3,
        notes: "Datos ficticios de demostración. No representan asistencia real.")
      if i == 0 { e.participantIds = s.people.map(\.id) }
      s.events.append(e)
    }
    let attendance: [AttendanceStatus] = [
      .present, .present, .absent, .present, .excused, .present, .pending, .present, .present,
    ]
    s.attendance = attendance.enumerated().map {
      Attendance(
        id: "attendance-\($0.offset)", eventId: "event-0", personId: "person-\($0.offset)",
        status: $0.element)
    }
    s.templates = [NativePDF.defaultTemplate()]
    return s
  }
}

#endif

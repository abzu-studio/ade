import Foundation
@main struct Bench {
 static func main() throws {
  var s = Space(id: "bench", name: "Benchmark")
  s.components = [Named(id: "c", name: "Component")]
  s.people = (0..<200).map { Person(id: "p\($0)", name: "Person \($0)") }
  for i in 0..<80 {
   var e = Activity(id: "e\(i)", name: "Event \(i)", date: "2026-10-25", componentId: "c")
   e.status = .completed; e.participantIds = s.people.map(\.id)
   s.events.append(e)
   for p in s.people { s.attendance.append(Attendance(eventId: e.id, personId: p.id, status: i % 4 == 0 ? .absent : .present)) }
  }
  let start = ContinuousClock.now
  let total = try Rules.aggregate(s)
  print("200 people / 80 events / 16,000 attendance records: \(start.duration(to: .now)); result \(total.formatted)")
 }
}

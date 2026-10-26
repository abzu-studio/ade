import AppKit
import Foundation
import PDFKit

@main struct NativeTests {
  static var count = 0
  static func check(_ condition: @autoclosure () throws -> Bool, _ name: String) throws {
    guard try condition() else { throw RuleError("FAIL: \(name)") }
    count += 1
    print("PASS \(name)")
  }
  static func rejects(_ name: String, _ operation: () throws -> Void) throws {
    do { try operation() } catch {
      count += 1
      print("PASS \(name)")
      return
    }
    throw RuleError("FAIL accepted: \(name)")
  }
  static func fixture() throws -> Space {
    var s = Space(id: "space", name: "Prueba Adê")
    s.people = [
      Person(id: "ana", name: "Ana Pérez"), Person(id: "bea", name: "Beatriz"),
      Person(id: "car", name: "Carla"),
    ]
    s.components = [Named(id: "service", name: "Servicio")]
    s.categories = [Category(id: "health", name: "Salud", componentId: "service")]
    s.groups = [Named(id: "group", name: "Equipo")]
    s.memberships = [
      Membership(
        id: "member", personId: "ana", groupId: "group", start: "2026-01-01", end: "2026-06-30")
    ]
    s.periods = [Period(id: "period", name: "Semestre", start: "2026-01-01", end: "2026-12-31")]
    var e = Activity(
      id: "event", name: "Feria de salud", date: "2026-03-10", componentId: "service",
      categoryId: "health", capacity: 3, volunteerCapacity: 1)
    e.participantIds = ["ana", "bea"]
    s.events = [e]
    try Rules.validate(s)
    return s
  }
  static func testIndividualBreakdown() throws {
    var s = try fixture()
    s.components.append(Named(id: "learning", name: "Formación"))
    s.components.append(Named(id: "empty-component", name: "Sin eventos"))
    s.categories.append(Category(id: "education", name: "Educación", componentId: "service"))
    s.categories.append(
      Category(id: "empty-category", name: "Sin registros", componentId: "service"))
    s.periods.append(
      Period(id: "spring", name: "Primera mitad", start: "2026-01-01", end: "2026-06-30"))
    s.events = []
    s.attendance = []
    for i in 0..<10 {
      var e = Activity(
        id: "breakdown-\(i)", name: "Evento \(i)",
        date: i < 2 ? "2026-03-10" : "2026-08-10",
        componentId: i < 3 || i > 4 ? "service" : "learning")
      e.categoryId = i == 0 ? "health" : i == 1 ? "education" : nil
      e.status = i == 7 ? .cancelled : i == 8 ? .draft : .completed
      e.countsForAttendance = i != 9
      e.participantIds = ["ana"]
      s.events.append(e)
      if i != 8 {
        s.attendance.append(
          Attendance(
            eventId: e.id, personId: "ana",
            status: i == 1 || i == 2 ? .absent : i == 5 ? .excused : i == 6 ? .pending : .present))
      }
    }
    var unlisted = s.events[0]
    unlisted.id = "not-listed"
    unlisted.participantIds = []
    s.events.append(unlisted)
    try Rules.validate(s)
    let rows = try Rules.participationBreakdown(s, person: "ana")
    func r(_ id: String) -> Participation { rows.first { $0.id == id }!.result }
    try check(
      r("overall").percentage == 60,
      "individual total uses weighted records, not average of components")
    try check(
      r("component-service").present == 1 && r("component-service").absent == 2,
      "component independent numerator and denominator")
    try check(r("component-learning").percentage == 100, "second component percentage")
    try check(
      r("category-health").percentage == 100 && r("category-education").percentage == 0,
      "categories have independent attendance percentages")
    try check(r("uncategorized-service").absent == 1, "uncategorized attendance is retained")
    try check(
      r("category-empty-category").percentage == nil
        && r("component-empty-component").percentage == nil,
      "no denominator is not zero percent")
    try check(
      r("overall").excused == 1 && r("overall").pending == 1 && r("overall").excluded == 3,
      "breakdown excludes excused pending cancelled draft and noncounting")
    let components = rows.filter { $0.kind == .component }.reduce(0) { $0 + $1.result.denominator }
    let categories = rows.filter { $0.kind == .category || $0.kind == .uncategorized }
      .reduce(0) { $0 + $1.result.denominator }
    try check(
      components == 5 && categories == 5,
      "component and category partitions match overall denominator")
    let spring = try Rules.participationBreakdown(s, person: "ana", period: "spring")
    try check(spring[0].result.percentage == 50, "individual breakdown respects period")
    let membership = try Rules.participationBreakdown(s, person: "ana", group: "group")
    try check(
      membership[0].result.percentage == 50, "individual breakdown respects historical membership")
    s.people[0].active = false
    try check(
      try Rules.participationBreakdown(s, person: "ana")[0].result.percentage == 60,
      "inactive person retains individual breakdown")
    try check(
      try Rules.participationBreakdown(s, person: "car")[0].result.denominator == 0,
      "unlisted person never receives an absence in breakdown")
  }
  static func main() async throws {
    try testIndividualBreakdown()
    var s = try fixture()
    try rejects("attendance on draft") {
      _ = try Rules.apply(
        .attendance(Attendance(eventId: "event", personId: "ana", status: .present)), to: s)
    }
    s = try Rules.apply(.eventStatus("event", .scheduled), to: s)
    let a = Attendance(
      id: "attendance", eventId: "event", personId: "ana", status: .present, notes: "Verificado")
    s = try Rules.apply(.attendance(a), to: s)
    try check(try Rules.participation(s, person: "ana").percentage == 100, "present denominator")
    try check(try Rules.participation(s, person: "bea").percentage == nil, "pending no denominator")
    try check(
      try Rules.participation(s, person: "car").pending == 0, "unlisted never automatic absence")
    try rejects("unlisted attendance") {
      _ = try Rules.apply(
        .attendance(Attendance(eventId: "event", personId: "car", status: .absent)), to: s)
    }
    var second = s.events[0]
    second.id = "second"
    second.name = "Segundo"
    second.date = "2026-08-01"
    s.events.append(second)
    s = try Rules.apply(
      .attendance(Attendance(eventId: "second", personId: "ana", status: .absent)), to: s)
    try check(
      try Rules.participation(s, person: "ana").percentage == 50,
      "strict present over present plus absent")
    try check(
      try Rules.participation(s, person: "ana", filter: ReportFilter(groupId: "group")).percentage
        == 100, "historical membership filter")
    var excluded = s
    excluded.events[1].countsForAttendance = false
    try check(
      try Rules.participation(excluded, person: "ana").percentage == 100, "noncounting excluded")
    excluded = s
    excluded.events[1].status = .cancelled
    try check(
      try Rules.participation(excluded, person: "ana").percentage == 100, "cancelled excluded")
    excluded = s
    excluded.attendance[1].status = .excused
    try check(
      try Rules.participation(excluded, person: "ana").percentage == 100, "excused excluded")
    excluded = s
    excluded.people[0].active = false
    try check(
      try Rules.participation(excluded, person: "ana").percentage == 50, "inactive retains history")
    try rejects("overlapping membership inclusive") {
      _ = try Rules.apply(
        .membership(Membership(personId: "ana", groupId: "group", start: "2026-06-30", end: nil)),
        to: s)
    }
    try check(
      s.member("ana", group: "group", on: "2026-06-30")
        && !s.member("ana", group: "group", on: "2026-07-01"), "membership boundaries")
    try rejects("invalid leap date") { try Rules.day("2025-02-29") }
    try rejects("cross-space reference") {
      var bad = s
      bad.events[0].participantIds.append("other-space")
      try Rules.validate(bad)
    }
    try rejects("category wrong component") {
      var bad = s
      bad.categories[0].componentId = "other"
      try Rules.validate(bad)
    }
    try rejects("removing recorded participant") {
      var e = s.events[0]
      e.participantIds = []
      _ = try Rules.apply(.event(e), to: s)
    }
    try rejects("draft transition with attendance") {
      _ = try Rules.apply(.eventStatus("event", .draft), to: s)
    }
    try rejects("delete referenced person") { _ = try Rules.apply(.delete(.people, "ana"), to: s) }
    var v = Volunteer(id: "vol", eventId: "event", personId: "ana")
    s = try Rules.apply(.volunteer(v), to: s)
    v.status = .selected
    s = try Rules.apply(.volunteer(v), to: s)
    var other = Volunteer(id: "vol2", eventId: "event", personId: "car")
    s = try Rules.apply(.volunteer(other), to: s)
    other.status = .selected
    try rejects("volunteer overcapacity atomic") { _ = try Rules.apply(.volunteer(other), to: s) }
    try check(
      !s.events[0].participantIds.contains("car"), "failed selection does not modify roster")
    v.status = .completed
    s = try Rules.apply(.volunteer(v), to: s)
    try check(s.record("event", "ana")?.status == .present, "volunteer does not change attendance")
    try rejects("terminal volunteer transition") {
      v.status = .interested
      _ = try Rules.apply(.volunteer(v), to: s)
    }
    var interest = Volunteer(eventId: "second", personId: "ana")
    s = try Rules.apply(.volunteer(interest), to: s)
    let suggestions = Rules.suggestions(s, event: s.events[1])
    try check(
      suggestions.first?.score == 4 && suggestions.first?.completed == 1
        && suggestions.first?.present == 1, "transparent prior-only score")
    try check(
      s.volunteers.first { $0.id == interest.id }?.status == .interested, "suggestions never select"
    )
    interest.status = .selected
    s = try Rules.apply(.volunteer(interest), to: s)
    interest.status = .declined
    s = try Rules.apply(.volunteer(interest), to: s)
    try check(s.events[1].participantIds.contains("ana"), "decline retains roster")
    let copy = try Rules.apply(.duplicate("event", "copy", "2026-10-25"), to: s)
    try check(
      copy.event("copy")?.participantIds.isEmpty == true && copy.event("copy")?.status == .draft,
      "duplicate clears roster and status")
    try rejects("inactive selection") {
      var inactive = s
      inactive.people[2].active = false
      _ = try Rules.apply(.volunteer(other), to: inactive)
    }
    var db = try Rules.create(Database(), name: "Historial", author: "Test")
    let id = db.spaces[0].id
    let root = db.spaces[0].heads[0]
    let left = try Rules.execute(
      db, space: id, edit: .person(Person(name: "Left")), label: "Left", author: "A")
    let right = try Rules.execute(
      db, space: id, edit: .person(Person(name: "Right")), label: "Right", author: "B")
    db = try Rules.merge(left, right)
    try check(db.spaces[0].heads.count == 2, "merge keeps divergent versions")
    try rejects("conflicted branch blocks edits") {
      _ = try Rules.execute(db, space: id, edit: .group(Named(name: "X")), label: "X", author: "A")
    }
    let resolved = try Rules.restore(db, space: id, revision: left.spaces[0].heads[0], author: "A")
    try check(
      resolved.spaces[0].heads.count == 1 && resolved.spaces[0].revisions.count == 4,
      "manual conflict resolution retains both")
    let restored = try Rules.restore(resolved, space: id, revision: root, author: "A")
    try check(
      restored.spaces[0].visible?.data.people.isEmpty == true
        && restored.spaces[0].revisions.count == 5, "recover without erasing history")
    try rejects("altered immutable revision") {
      var altered = left
      altered.spaces[0].revisions[0].label = "Tampered"
      _ = try Rules.merge(left, altered)
    }
    try rejects("cyclic history") {
      var altered = left
      altered.spaces[0].revisions[0].parents = altered.spaces[0].heads
      try Rules.validate(altered)
    }
    let encoded = try WorkspaceCodec.encode(restored)
    try check(try WorkspaceCodec.decode(encoded) == restored, "export import roundtrip")
    try rejects("unknown field cannot be lost") {
      var raw = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
      raw["newField"] = 1
      _ = try WorkspaceCodec.decode(JSONSerialization.data(withJSONObject: raw))
    }
    var template = NativePDF.defaultTemplate()
    template.name = "Informe nativo"
    s.templates = [template]
    let r = Revision(parents: [], author: "Test", label: "Fixture", data: s)
    let fixtureDB = Database(spaces: [Branch(id: s.id, revisions: [r], heads: [r.id])])
    let fixtureData = try WorkspaceCodec.encode(fixtureDB)
    try check(
      try WorkspaceCodec.decode(fixtureData) == fixtureDB, "nullable schema v1 compatibility")
    let options = DocumentOptions(eventId: "event", personId: "ana", revisionId: r.id)
    let pdf = try NativePDF.generate(space: s, template: template, options: options)
    let doc = PDFDocument(data: pdf)!
    try check(
      doc.pageCount >= 1 && doc.string?.contains("Ana Pérez") == true
        && doc.string?.contains(r.id) == true, "native PDF real data and provenance")
    let personalPDF = PDFDocument(data: try NativePDF.generate(
      space: s, template: NativePDF.defaultTemplate(), options: options))!
    try check(personalPDF.string?.contains("Beatriz") == false,
              "individual PDF excludes other participants")
    template.blocks = [
      TemplateBlock(
        type: .columns,
        left: String(repeating: "Texto largo áéíóú y palabras sin pérdida.\n", count: 180),
        right: String(repeating: "Columna derecha.\n", count: 220)), .make(.pageBreak),
      TemplateBlock(type: .text, text: "FINAL ÚNICO", size: 18),
    ]
    let multi = try NativePDF.generate(space: s, template: template, options: options)
    let multiDoc = PDFDocument(data: multi)!
    try check(
      multiDoc.pageCount > 4 && multiDoc.string?.contains("FINAL ÚNICO") == true,
      "multipage columns and explicit break")
    template = NativePDF.defaultTemplate()
    template.backgroundPDF = multi.base64EncodedString()
    let background = try NativePDF.generate(space: s, template: template, options: options)
    try check(
      PDFDocument(data: background)!.pageCount >= multiDoc.pageCount,
      "preserve all background PDF pages")
    try rejects("unknown template variable") {
      _ = try NativePDF.interpolate("{{unknown.value}}", values: [:])
    }
    let png = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
      .representation(using: .png, properties: [:])!
    template = NativePDF.defaultTemplate()
    template.blocks.insert(
      TemplateBlock(
        type: .image, data: "data:image/png;base64," + png.base64EncodedString(), width: 200), at: 0
    )
    try check(
      PDFDocument(data: try NativePDF.generate(space: s, template: template, options: options))
        != nil, "embedded image rendering")
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "AdeNativeTests-\(UUID())")
    let store = LocalStore(directory: directory)
    let (initial, version) = try await store.load()
    try check(initial == nil && version == "empty", "empty store")
    let savedToken = try await store.save(
      String(decoding: fixtureData, as: UTF8.self), expected: version)
    let (reloaded, reloadedToken) = try await LocalStore(directory: directory).load()
    try check(
      reloadedToken == savedToken && reloaded == String(decoding: fixtureData, as: UTF8.self),
      "atomic persistence reopen")
    do {
      _ = try await store.save("{}", expected: "stale")
      throw RuleError("stale accepted")
    } catch StoreError.conflict {
      count += 1
      print("PASS stale writes rejected")
    }
    let next = try WorkspaceCodec.encode(
      try Rules.execute(
        fixtureDB, space: s.id, edit: .group(Named(name: "Nuevo")), label: "Guardar", author: "Test"
      ))
    let nextToken = try await store.save(
      String(decoding: next, as: UTF8.self), expected: savedToken)
    let backup = try await store.backup()
    try check(backup == reloaded, "recoverable previous copy")
    let beforeNative = try Data(
      contentsOf: directory.appendingPathComponent("workspace.before-native.json"))
    try check(beforeNative == fixtureData, "immutable migration backup")
    let successes = await withTaskGroup(of: Bool.self) { group in
      for index in 0..<2 {
        group.addTask {
          do {
            let changed = try Rules.execute(
              fixtureDB, space: s.id, edit: .group(Named(name: "Writer \(index)")),
              label: "Concurrent", author: "Test")
            _ = try await LocalStore(directory: directory).save(
              String(decoding: WorkspaceCodec.encode(changed), as: UTF8.self), expected: nextToken)
            return true
          } catch { return false }
        }
      }
      var result = 0
      for await ok in group { if ok { result += 1 } }
      return result
    }
    try check(successes == 1, "cross-process store lock plus CAS")
    let damaged = Data([0xff, 0xfe, 0x7b])
    try damaged.write(to: directory.appendingPathComponent("workspace.json"), options: .atomic)
    let (rawDamaged, damagedToken) = try await store.readData()
    try check(rawDamaged == damaged, "raw corrupted bytes retained for recovery")
    let (recovered, _) = try await store.recoverPrevious(expected: damagedToken)
    try check(
      try WorkspaceCodec.decode(Data(recovered.utf8)).spaces.count == 1,
      "restore validated backup after corruption")
    let archives = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil
    ).filter { $0.lastPathComponent.hasPrefix("workspace.recovered-") }
    try check(
      archives.count == 1 && (try Data(contentsOf: archives[0])) == damaged,
      "recovery preserves damaged original exactly")
    let out = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(
      "verification")
    try fixtureData.write(to: out.appendingPathComponent("native-fixture.json"))
    try pdf.write(to: out.appendingPathComponent("native-report.pdf"))
    try multi.write(to: out.appendingPathComponent("native-multipage.pdf"))
    let totals = try Rules.aggregate(s)
    try check(
      totals.present == 1 && totals.absent == 1 && totals.percentage == 50,
      "aggregate counts records without averaging percentages")
    try await modelFlow()
    try await transactionFailures()
    try await transactionConflicts()
    try reportParity()
    print("ALL \(count) NATIVE CHECKS PASSED")
  }
  @MainActor static func modelFlow() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "AdeModelTests-" + UUID().uuidString)
    let preferenceSuite = "AdeCoreTests-" + UUID().uuidString
    let preferences = UserDefaults(suiteName: preferenceSuite)!
    defer {
      preferences.removePersistentDomain(forName: preferenceSuite)
      try? FileManager.default.removeItem(at: directory)
    }
    let model = AppModel(directory: directory, preferences: preferences)
    await model.load()
    try check(model.database.spaces.isEmpty && model.showSpaces, "fresh install has no preloaded records")
    try check(model.author == "Local", "fresh install uses a neutral author")
    let created = await model.createSpace(name: "Native state", zone: "America/Puerto_Rico")
    try check(created && model.space?.name == "Native state", "native model creates space")
    let saved = await model.edit(.person(Person(name: "Undo test")), label: "Add person")
    try check(
      saved && model.canUndo && model.space?.people.count == 1, "saved command enables undo")
    await model.undo()
    try check(
      model.space?.people.isEmpty == true && model.canRedo, "undo restores previous snapshot")
    await model.redo()
    try check(model.space?.people.count == 1 && !model.canRedo, "redo restores next snapshot")
    try check(model.branch?.revisions.count == 4, "undo and redo preserve all revisions")
    let reopened = AppModel(directory: directory, preferences: preferences)
    await reopened.load()
    try check(
      reopened.space?.people.count == 1 && reopened.branch?.revisions.count == 4,
      "undo redo persisted end to end")
  }

  static func reportParity() throws {
    var space = try fixture()
    space.events = []
    space.attendance = []
    for i in 0..<48 {
      var event = Activity(id: "indexed-\(i)", name: "Event \(i)",
                           date: i % 2 == 0 ? "2026-03-10" : "2026-09-10",
                           componentId: "service", categoryId: i % 3 == 0 ? "health" : nil)
      event.status = i % 5 == 0 ? .draft : i % 7 == 0 ? .cancelled : .completed
      event.countsForAttendance = i % 11 != 0
      event.participantIds = i % 2 == 0 ? ["ana", "bea"] : ["ana", "car"]
      space.events.append(event)
      if event.canRecord {
        for (j, id) in event.participantIds.enumerated() where i % 9 != 0 {
          space.attendance.append(Attendance(eventId: event.id, personId: id,
            status: AttendanceStatus.allCases[(i + j) % 4]))
        }
      }
    }
    try Rules.validate(space)
    let filters = [ReportFilter(), ReportFilter(periodId: "period"), ReportFilter(groupId: "group"),
                   ReportFilter(componentId: "service"), ReportFilter(categoryId: "health"),
                   ReportFilter(eventId: "indexed-3"), ReportFilter(uncategorized: true)]
    // Independent direct traversal retains the original rule as an oracle.
    for filter in filters {
      let results = try Rules.report(space, filter: filter)
      for person in space.people {
        var expected = Participation()
        for event in space.events where event.participantIds.contains(person.id) {
          if let period = space.periods.first(where: { $0.id == filter.periodId }),
            event.date < period.start || event.date > period.end { continue }
          if !filter.groupId.isEmpty && !space.member(person.id, group: filter.groupId, on: event.date) { continue }
          if !filter.componentId.isEmpty && event.componentId != filter.componentId { continue }
          if !filter.categoryId.isEmpty && event.categoryId != filter.categoryId { continue }
          if !filter.eventId.isEmpty && event.id != filter.eventId { continue }
          if filter.uncategorized && event.categoryId != nil { continue }
          if !event.canRecord || !event.countsForAttendance { expected.excluded += 1; continue }
          switch space.record(event.id, person.id)?.status ?? .pending {
          case .present: expected.present += 1
          case .absent: expected.absent += 1
          case .excused: expected.excused += 1
          case .pending: expected.pending += 1
          }
        }
        let actual = results[person.id]!
        try check([actual.present, actual.absent, actual.excused, actual.pending, actual.excluded] ==
                  [expected.present, expected.absent, expected.excused, expected.pending, expected.excluded],
                  "indexed report parity \(person.id) / \(filter)")
      }
    }
  }
  static func transactionConflicts() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AdeTransactions-" + UUID().uuidString)
    let store = LocalStore(directory: directory)
    let base = try Rules.create(Database(), name: "Concurrent", author: "Tests")
    let receipt = try await store.commit(base, expected: "empty")
    let id = base.spaces[0].id
    let a = try Rules.execute(base, space: id, edit: .person(Person(name: "First")), label: "First", author: "A")
    let b = try Rules.execute(base, space: id, edit: .person(Person(name: "Second")), label: "Second", author: "B")
    async let one = store.commit(a, expected: receipt.token)
    async let two = LocalStore(directory: directory).commit(b, expected: receipt.token)
    _ = try await (one, two)
    let final = try await store.snapshot().database.get()
    try check(final.spaces[0].heads.count == 2 && final.spaces[0].revisions.count == 3,
              "transactional merge retains both concurrent branches")
    try check(Set(final.spaces[0].revisions.flatMap { $0.data.people.map(\.name) }) == ["First", "Second"],
              "transactional merge loses neither writer")
    let original = try Data(contentsOf: directory.appendingPathComponent("workspace.json"))
    var invalid = final
    invalid.schemaVersion = 999
    do { _ = try await store.commit(invalid, expected: "stale"); throw RuleError("Invalid commit accepted") }
    catch { try check(try Data(contentsOf: directory.appendingPathComponent("workspace.json")) == original,
                      "invalid transaction leaves disk bytes unchanged") }
  }
  @MainActor static func transactionFailures() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AdeFailure-" + UUID().uuidString)
    let preferenceSuite = "AdeCoreTests-" + UUID().uuidString
    let preferences = UserDefaults(suiteName: preferenceSuite)!
    defer {
      preferences.removePersistentDomain(forName: preferenceSuite)
      try? FileManager.default.removeItem(at: directory)
    }
    let model = AppModel(directory: directory, preferences: preferences)
    await model.load()
    _ = await model.createSpace(name: "Failure recovery", zone: "America/Puerto_Rico")
    let prior = model.database
    let moved = directory.appendingPathExtension("preserved")
    try FileManager.default.moveItem(at: directory, to: moved)
    try Data("blocked".utf8).write(to: directory)
    let saved = await model.edit(.person(Person(name: "Retained")), label: "Retain failed write")
    try check(!saved && model.database == prior && model.pending != nil && !model.busy,
              "failed transaction preserves visible state and recoverable proposal")
    try FileManager.default.removeItem(at: directory)
    try FileManager.default.moveItem(at: moved, to: directory)
    let retry = await model.commit(model.pending!)
    try check(retry && model.pending == nil && model.space?.people.first?.name == "Retained",
              "retry saves the exact pending proposal")
    try check(model.canUndo, "retry registers undo for the recovered edit")
    await model.undo()
    try check(model.space?.people.isEmpty == true && model.canRedo,
              "undo after retry restores the exact prior snapshot")
    await model.redo()
    try check(model.space?.people.first?.name == "Retained", "redo after retry restores recovered edit")
    try FileManager.default.moveItem(at: directory, to: moved)
    try Data("blocked".utf8).write(to: directory)
    await model.undo()
    try check(model.pending != nil && model.space?.people.count == 1,
              "failed undo does not change visible data")
    try FileManager.default.removeItem(at: directory)
    try FileManager.default.moveItem(at: moved, to: directory)
    let retriedUndo = await model.commit(model.pending!)
    try check(retriedUndo && model.space?.people.isEmpty == true && model.canRedo && !model.canUndo,
              "retry completes undo history exactly once")
    await model.redo()
    try check(model.space?.people.count == 1 && model.canUndo && !model.canRedo,
              "redo after retried undo restores data exactly once")
    try Data([0xff]).write(to: directory.appendingPathComponent("workspace.json"), options: .atomic)
    await model.load()
    try check(model.unreadable, "unreadable load retains recovery token")
    await model.repairFromBackup()
    try check(!model.unreadable && model.space != nil, "model can recover a malformed workspace after actor decode failure")
    try check(!model.canUndo && !model.canRedo, "backup recovery clears obsolete session undo history")
    let longName = String(repeating: "a", count: 240)
    let longLabelSaved = await model.edit(.person(Person(name: longName)), label: "Asistencia: " + longName)
    try check(longLabelSaved && model.branch?.visible?.label.count == 240,
              "valid maximum length name does not overflow generated revision label")
  }

}

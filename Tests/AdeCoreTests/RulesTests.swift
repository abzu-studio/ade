import XCTest
@testable import AdeCore

final class RulesTests: XCTestCase {
    func testAttendanceFormulaExcludesExcusedPendingAndUncounted() {
        let app = Harness()
        app.act(.loadDemo)
        let space = app.db.spaces[0]
        let period = app.db.periods[0]
        let ada = app.db.people.first { $0.name == "Ada" }!
        let ben = app.db.people.first { $0.name == "Ben" }!
        let cia = app.db.people.first { $0.name == "Cia" }!
        let adaStats = computeAttendance(app.db, AttendanceQuery(spaceId: space.id, periodId: period.id, personId: ada.id))
        XCTAssertEqual(adaStats.formula, "present / (present + absent)")
        XCTAssertEqual(adaStats.present, 3)
        XCTAssertEqual(adaStats.absent, 0)
        XCTAssertEqual(adaStats.percentage, 1)
        XCTAssertEqual(adaStats.excused, 0)
        XCTAssertEqual(adaStats.excludedCancelled, 1)
        XCTAssertEqual(adaStats.excludedNotCounting, 1)

        let benStats = computeAttendance(app.db, AttendanceQuery(spaceId: space.id, periodId: period.id, personId: ben.id))
        XCTAssertEqual(benStats.present, 0)
        XCTAssertEqual(benStats.absent, 1)
        XCTAssertEqual(benStats.pending, 1)
        XCTAssertEqual(benStats.percentage, 0)

        let ciaStats = computeAttendance(app.db, AttendanceQuery(spaceId: space.id, periodId: period.id, personId: cia.id))
        XCTAssertEqual(ciaStats.present, 1)
        XCTAssertEqual(ciaStats.excused, 1)
        XCTAssertEqual(ciaStats.denominator, 1)
        XCTAssertEqual(ciaStats.percentage, 1)
    }

    func testDoesNotInventAbsence() {
        let app = Harness()
        app.act(.createSpace(name: "Hall"))
        let spaceId = app.db.spaces[0].id
        app.act(.createPerson(spaceId: spaceId, name: "Ada", email: "", notes: "", status: .active))
        app.act(.createPerson(spaceId: spaceId, name: "Bea", email: "", notes: "", status: .active))
        let ada = app.db.people.first { $0.name == "Ada" }!
        let bea = app.db.people.first { $0.name == "Bea" }!
        app.act(.createComponent(spaceId: spaceId, name: "Work", description: ""))
        let componentId = app.db.components[0].id
        app.act(.createEvent(spaceId: spaceId, title: "Shift", description: "", date: "2026-02-02", componentId: componentId, categoryId: nil, capacity: nil, volunteerCapacity: nil, countsForAttendance: true, participantIds: [ada.id]))
        let eventId = app.db.events[0].id
        app.act(.setEventStatus(spaceId: spaceId, eventId: eventId, status: .scheduled))
        let open = computeAttendance(app.db, AttendanceQuery(spaceId: spaceId, personId: ada.id, eventId: eventId))
        XCTAssertEqual(open.unrecorded, 1)
        XCTAssertEqual(open.absent, 0)
        XCTAssertNil(open.percentage)

        var stray = app.db
        stray.attendance.append(AttendanceRecord(id: "stray", spaceId: spaceId, eventId: eventId, personId: bea.id, state: .present, note: "", history: [], createdAt: app.ctx.now, updatedAt: app.ctx.now))
        app.db = stray
        let ignored = computeAttendance(app.db, AttendanceQuery(spaceId: spaceId, eventId: eventId))
        XCTAssertEqual(ignored.present, 0)
        XCTAssertTrue(ignored.lines.contains { $0.personId == bea.id && $0.reason == .notParticipant })
    }

    func testPooledPercentageIsNotAnAverage() {
        let app = Harness()
        app.act(.createSpace(name: "Hall"))
        let spaceId = app.db.spaces[0].id
        app.act(.createPerson(spaceId: spaceId, name: "A", email: "", notes: "", status: .active))
        app.act(.createPerson(spaceId: spaceId, name: "B", email: "", notes: "", status: .active))
        let a = app.db.people[0]
        let b = app.db.people[1]
        app.act(.createComponent(spaceId: spaceId, name: "Work", description: ""))
        let componentId = app.db.components[0].id
        let dates = ["2026-01-01", "2026-01-02", "2026-01-03", "2026-01-04"]
        var ids: [String] = []
        for (index, date) in dates.enumerated() {
            app.act(.createEvent(spaceId: spaceId, title: "E\(index)", description: "", date: date, componentId: componentId, categoryId: nil, capacity: nil, volunteerCapacity: nil, countsForAttendance: true, participantIds: index == 0 ? [a.id] : [b.id]))
            let eventId = app.db.events.first { $0.title == "E\(index)" }!.id
            app.act(.setEventStatus(spaceId: spaceId, eventId: eventId, status: .scheduled))
            ids.append(eventId)
        }
        app.act(.setAttendance(spaceId: spaceId, eventId: ids[0], personId: a.id, state: .present, note: ""))
        for eventId in ids.dropFirst() {
            app.act(.setAttendance(spaceId: spaceId, eventId: eventId, personId: b.id, state: .absent, note: ""))
        }
        let pooled = computeAttendance(app.db, AttendanceQuery(spaceId: spaceId))
        XCTAssertEqual(pooled.present, 1)
        XCTAssertEqual(pooled.absent, 3)
        XCTAssertEqual(pooled.percentage, 0.25)
        let rows = attendanceByPerson(app.db, AttendanceQuery(spaceId: spaceId))
        XCTAssertEqual(rows.map { $0.breakdown.percentage }, [1, 0])
    }

    func testGroupMembershipOnTheEventDate() {
        let app = Harness()
        app.act(.loadDemo)
        let space = app.db.spaces[0]
        let period = app.db.periods[0]
        let group = app.db.groups[0]
        let cia = app.db.people.first { $0.name == "Cia" }!
        let stats = computeAttendance(app.db, AttendanceQuery(spaceId: space.id, periodId: period.id, groupId: group.id, personId: cia.id))
        XCTAssertEqual(stats.excludedNotMember, 1)
        XCTAssertEqual(stats.present, 1)
        XCTAssertEqual(stats.percentage, 1)
        XCTAssertEqual(membersAt(app.db, groupId: group.id, date: "2026-02-01").map(\.name), ["Ada", "Ben"])
        XCTAssertEqual(membersAt(app.db, groupId: group.id, date: "2026-05-01").map(\.name), ["Ada", "Cia"])
    }

    func testOverlappingMembershipAndDateRange() {
        let app = Harness()
        app.act(.createSpace(name: "Hall"))
        let spaceId = app.db.spaces[0].id
        app.act(.createPerson(spaceId: spaceId, name: "Ada", email: "", notes: "", status: .active))
        app.act(.createGroup(spaceId: spaceId, name: "Team", description: ""))
        let personId = app.db.people[0].id
        let groupId = app.db.groups[0].id
        app.act(.addMembership(spaceId: spaceId, groupId: groupId, personId: personId, startDate: "2026-01-01", endDate: "2026-01-31"))
        XCTAssertEqual(app.fail(.addMembership(spaceId: spaceId, groupId: groupId, personId: personId, startDate: "2026-01-31", endDate: nil)).code, .OVERLAPPING_MEMBERSHIP)
        XCTAssertEqual(app.fail(.addMembership(spaceId: spaceId, groupId: groupId, personId: personId, startDate: "2026-03-02", endDate: "2026-03-01")).code, .INVALID_DATE_RANGE)
        XCTAssertEqual(daysBetween("2026-02-01", "2026-06-01"), 120)
    }

    func testDuplicateUndoAndRedo() {
        let app = Harness()
        app.act(.createSpace(name: "Hall"))
        let spaceId = app.db.spaces[0].id
        app.act(.createPerson(spaceId: spaceId, name: "Ada", email: "", notes: "", status: .active))
        app.act(.createComponent(spaceId: spaceId, name: "Work", description: ""))
        let personId = app.db.people[0].id
        let componentId = app.db.components[0].id
        app.act(.createEvent(spaceId: spaceId, title: "Shift", description: "", date: "2026-02-02", componentId: componentId, categoryId: nil, capacity: 1, volunteerCapacity: 1, countsForAttendance: true, participantIds: [personId]))
        let eventId = app.db.events[0].id
        app.act(.setEventStatus(spaceId: spaceId, eventId: eventId, status: .scheduled))
        app.act(.setAttendance(spaceId: spaceId, eventId: eventId, personId: personId, state: .present, note: "on time"))
        app.act(.setAttendance(spaceId: spaceId, eventId: eventId, personId: personId, state: .present, note: "late"))
        XCTAssertEqual(app.db.attendance[0].history.count, 2)
        app.act(.duplicateEvent(spaceId: spaceId, eventId: eventId, titleSuffix: " (copy)"))
        let copy = app.db.events.first { $0.title == "Shift (copy)" }!
        XCTAssertEqual(copy.status, .draft)
        XCTAssertEqual(copy.participantIds, [personId])
        XCTAssertEqual(copy.duplicatedFromId, eventId)
        XCTAssertTrue(app.db.attendance.allSatisfy { $0.eventId != copy.id })
        XCTAssertEqual(app.fail(.setAttendance(spaceId: spaceId, eventId: copy.id, personId: personId, state: .absent, note: "")).code, .ATTENDANCE_NOT_ALLOWED)
        XCTAssertEqual(app.fail(.setEventParticipants(spaceId: spaceId, eventId: eventId, participantIds: [personId, personId])).code, .DUPLICATE_PARTICIPANT)
        app.act(.renameSpace(spaceId: spaceId, name: "Renamed"))
        app.act(.undo(spaceId: spaceId))
        XCTAssertEqual(app.db.spaces[0].name, "Hall")
        app.act(.redo(spaceId: spaceId))
        XCTAssertEqual(app.db.spaces[0].name, "Renamed")
        app.act(.undo(spaceId: spaceId))
        app.act(.renameSpace(spaceId: spaceId, name: "Other"))
        XCTAssertEqual(app.fail(.redo(spaceId: spaceId)).code, .NOTHING_TO_REDO)
        XCTAssertEqual(app.db.spaces[0].name, "Other")
    }

    func testUndoFirstRevisionRemovesTheSpace() {
        let app = Harness()
        app.act(.createSpace(name: "Hall"))
        let spaceId = app.db.spaces[0].id
        app.act(.undo(spaceId: spaceId))
        XCTAssertTrue(app.db.spaces.isEmpty)
        app.act(.redo(spaceId: spaceId))
        XCTAssertEqual(app.db.spaces.map(\.name), ["Hall"])
    }

    func testVolunteerScoresNeverSelectAutomatically() {
        let app = Harness()
        app.act(.loadDemo)
        let event = app.db.events.first { $0.title == "June service" }!
        let before = app.db.volunteering.count
        let ranked = suggestVolunteers(app.db, eventId: event.id)
        XCTAssertEqual(app.db.volunteering.count, before)
        XCTAssertEqual(ranked.map(\.name), ["Ada", "Cia", "Ben"])
        XCTAssertNil(ranked.first { $0.name == "Dio" })
        let ada = ranked[0]
        XCTAssertEqual(ada.score, VolunteerWeights.completed + VolunteerWeights.recentCompleted + VolunteerWeights.sameComponentCompleted + VolunteerWeights.attendancePresent * 2)
        XCTAssertEqual(ada.factors.map(\.code), [.completed, .recentCompleted, .sameComponentCompleted, .attendancePresent])
        XCTAssertEqual(ranked.first { $0.name == "Cia" }?.factors[0].code, .noHistory)
        XCTAssertEqual(ranked.first { $0.name == "Ben" }?.score, VolunteerWeights.declined)
        let spaceId = event.spaceId
        let cia = app.db.people.first { $0.name == "Cia" }!
        let ben = app.db.people.first { $0.name == "Ben" }!
        let adaPerson = app.db.people.first { $0.name == "Ada" }!
        app.act(.setVolunteerState(spaceId: spaceId, eventId: event.id, personId: cia.id, state: .selected, note: ""))
        app.act(.setVolunteerState(spaceId: spaceId, eventId: event.id, personId: ben.id, state: .selected, note: ""))
        app.act(.setVolunteerState(spaceId: spaceId, eventId: event.id, personId: adaPerson.id, state: .interested, note: ""))
        XCTAssertEqual(app.fail(.setVolunteerState(spaceId: spaceId, eventId: event.id, personId: adaPerson.id, state: .selected, note: "")).code, .CAPACITY_EXCEEDED)
        app.act(.setVolunteerState(spaceId: spaceId, eventId: event.id, personId: ben.id, state: .completed, note: ""))
        XCTAssertEqual(app.fail(.setVolunteerState(spaceId: spaceId, eventId: event.id, personId: ben.id, state: .declined, note: "")).code, .INVALID_TRANSITION)
    }

    func testConflictsKeepBothVersions() throws {
        let app = Harness()
        app.act(.createSpace(name: "Hall"))
        let spaceId = app.db.spaces[0].id
        app.act(.createPerson(spaceId: spaceId, name: "Ada", email: "", notes: "", status: .active))
        app.act(.createComponent(spaceId: spaceId, name: "Work", description: ""))
        let person = app.db.people[0]
        let componentId = app.db.components[0].id
        app.act(.createEvent(spaceId: spaceId, title: "Shift", description: "", date: "2026-02-02", componentId: componentId, categoryId: nil, capacity: nil, volunteerCapacity: nil, countsForAttendance: true, participantIds: [person.id]))
        let eventId = app.db.events[0].id
        app.act(.setEventStatus(spaceId: spaceId, eventId: eventId, status: .scheduled))
        app.act(.setAttendance(spaceId: spaceId, eventId: eventId, personId: person.id, state: .present, note: ""))
        var remote = app.db
        let remoteSerial = Counter()
        let remoteCtx = ReduceContext(now: "2026-07-01T00:00:00.000Z", actorId: "actor-2") { remoteSerial.value += 1; return "remote-\(remoteSerial.value)" }
        func remoteDispatch(_ action: Action) {
            let result = dispatch(remote, action, remoteCtx)
            if case .err(let error) = result { XCTFail(error.code.rawValue) }
            if case .ok(let value) = result { remote = value }
        }
        remoteDispatch(.updatePerson(spaceId: spaceId, personId: person.id, name: "Ana", email: "", notes: "", status: .active))
        remoteDispatch(.setAttendance(spaceId: spaceId, eventId: eventId, personId: person.id, state: .absent, note: "remote"))
        remoteDispatch(.createPerson(spaceId: spaceId, name: "New", email: "", notes: "", status: .active))
        app.act(.updatePerson(spaceId: spaceId, personId: person.id, name: "Adela", email: "", notes: "", status: .active))
        let bundle = toSyncBundle(remote, spaceId: spaceId, exportedAt: remoteCtx.now)
        let json = try JSONValue.fromEncodable(try XCTUnwrap(bundle.value))
        app.act(.importSync(json))
        XCTAssertEqual(app.db.people.first { $0.id == person.id }?.name, "Adela")
        XCTAssertTrue(app.db.people.contains { $0.name == "New" })
        XCTAssertEqual(app.db.attendance.count, 1)
        XCTAssertEqual(app.db.attendance[0].state, .present)
        let personConflict = app.db.conflicts.first { $0.entityType == .person }!
        let attendanceConflict = app.db.conflicts.first { $0.entityType == .attendance }!
        XCTAssertEqual(personConflict.resolution, .pending)
        XCTAssertEqual(field(personConflict.remote, "name"), "Ana")
        XCTAssertEqual(field(personConflict.local, "name"), "Adela")
        XCTAssertEqual(field(attendanceConflict.remote, "state"), "absent")
        XCTAssertEqual(field(attendanceConflict.local, "state"), "present")
        app.act(.resolveConflict(spaceId: spaceId, conflictId: personConflict.id, resolution: .keptBoth))
        XCTAssertTrue(app.db.people.contains { $0.name == "Ana (conflict)" })
        XCTAssertEqual(app.db.people.first { $0.id == person.id }?.name, "Adela")
        app.act(.resolveConflict(spaceId: spaceId, conflictId: attendanceConflict.id, resolution: .keptBoth))
        XCTAssertEqual(app.db.attendance.count, 1)
        XCTAssertEqual(app.db.conflicts.first { $0.id == attendanceConflict.id }?.resolution, .keptBoth)
        app.act(.importSync(json))
        XCTAssertEqual(app.db.conflicts.filter { $0.entityType == .person && $0.resolution == .pending }.count, 1)
    }

    func testTombstonesAndChangedDeletes() throws {
        let app = Harness()
        app.act(.createSpace(name: "Hall"))
        let spaceId = app.db.spaces[0].id
        app.act(.createPerson(spaceId: spaceId, name: "Ada", email: "", notes: "", status: .active))
        app.act(.createPerson(spaceId: spaceId, name: "Bea", email: "", notes: "", status: .active))
        let ada = app.db.people.first { $0.name == "Ada" }!
        let bea = app.db.people.first { $0.name == "Bea" }!
        var remote = app.db
        let remoteCtx = ReduceContext(now: "2026-07-01T00:00:00.000Z", actorId: "actor-2") { "remote-tomb" }
        let deleted = dispatch(remote, .deletePerson(spaceId: spaceId, personId: bea.id), remoteCtx)
        remote = try XCTUnwrap(deleted.value)
        let bundle = try JSONValue.fromEncodable(try XCTUnwrap(toSyncBundle(remote, spaceId: spaceId, exportedAt: remoteCtx.now).value))
        app.act(.updatePerson(spaceId: spaceId, personId: ada.id, name: "Ada P", email: "", notes: "", status: .active))
        var remoteAda = remote
        let removed = dispatch(remoteAda, .deletePerson(spaceId: spaceId, personId: ada.id), ReduceContext(now: "2026-07-02T00:00:00.000Z", actorId: "actor-2") { "remote-ada" })
        remoteAda = try XCTUnwrap(removed.value)
        app.act(.importSync(bundle))
        XCTAssertFalse(app.db.people.contains { $0.id == bea.id })
        XCTAssertTrue(app.db.tombstones.contains { $0.entityId == bea.id })
        let adaBundle = try JSONValue.fromEncodable(try XCTUnwrap(toSyncBundle(remoteAda, spaceId: spaceId, exportedAt: "2026-07-02T00:00:00.000Z").value))
        app.act(.importSync(adaBundle))
        XCTAssertTrue(app.db.people.contains { $0.id == ada.id })
        XCTAssertTrue(app.db.conflicts.contains { $0.entityType == .person && $0.remoteDeleted && $0.resolution == .pending })
    }

    func testDocumentPlanAndBackup() throws {
        let app = Harness()
        app.act(.loadDemo)
        let spaceId = app.db.spaces[0].id
        let periodId = app.db.periods[0].id
        app.act(.createTemplate(
            spaceId: spaceId, name: "Summary", description: "", pageSize: .letter, backgroundAssetId: nil,
            elements: [
                .text(TextElementDraft(x: 40, y: 40, width: 200, height: 20, text: "", binding: .spaceName, fontSize: 12, align: .left)),
                .columns(ColumnsElementDraft(x: 40, y: 80, width: 200, height: 30, columns: 1, gap: 0, binding: .periodParticipation, fontSize: 12)),
            ]
        ))
        let template = app.db.templates[0]
        let planned = planDocument(app.db, template, TemplateDataContext(spaceId: spaceId, periodId: periodId, eventId: nil, groupId: nil, generatedAt: "2026-06-15T15:00:00.000Z"))
        let pages = try XCTUnwrap(planned.value)
        XCTAssertGreaterThan(pages.count, 1)
        XCTAssertTrue(pages[0].items.contains { item in
            if case .text(let text) = item { return text.text == "Demo" }
            return false
        })
        let lines = pages.flatMap { page in
            page.items.compactMap { item -> String? in
                if case .text(let text) = item { return text.text }
                return nil
            }
        }
        XCTAssertTrue(lines.contains { $0.hasPrefix("Ada - 100.0% (3/3)") })
        XCTAssertTrue(lines.contains { $0.hasPrefix("Ben - 0.0% (0/1)") })
        let backup = toBackup(app.db, exportedAt: app.ctx.now)
        let restored = sanitizeDatabase(try JSONValue.fromEncodable(backup.database))
        XCTAssertTrue(restored.isOk)
        let bad = try JSONValue.parse(Data(#"{"format":"nope"}"#.utf8))
        XCTAssertFalse(dispatch(app.db, .importBackup(bad), app.ctx).isOk)
    }

    func testCategoryMustBelongToTheComponent() {
        let app = Harness()
        app.act(.createSpace(name: "Hall"))
        let spaceId = app.db.spaces[0].id
        app.act(.createComponent(spaceId: spaceId, name: "A", description: ""))
        app.act(.createComponent(spaceId: spaceId, name: "B", description: ""))
        let a = app.db.components[0]
        let b = app.db.components[1]
        app.act(.createCategory(spaceId: spaceId, componentId: a.id, name: "Kitchen", description: ""))
        let categoryId = app.db.categories[0].id
        XCTAssertEqual(app.fail(.createEvent(spaceId: spaceId, title: "Shift", description: "", date: "2026-02-02", componentId: b.id, categoryId: categoryId, capacity: nil, volunteerCapacity: nil, countsForAttendance: true, participantIds: [])).code, .CATEGORY_COMPONENT_MISMATCH)
    }
}

private final class Counter {
    var value = 0
}

private final class Harness {
    let ctx: ReduceContext
    var db: Database
    init(now: String = "2026-06-15T15:00:00.000Z") {
        let serial = Counter()
        ctx = ReduceContext(now: now, actorId: "actor-1") { serial.value += 1; return "id-\(serial.value)" }
        db = createEmptyDatabase(actorId: ctx.actorId, now: ctx.now)
    }
    func act(_ action: Action) {
        let result = dispatch(db, action, ctx)
        if case .err(let error) = result {
            XCTFail("\(action) \(error.code.rawValue)")
        }
        if case .ok(let value) = result { db = value }
    }
    func fail(_ action: Action) -> CoreError {
        let result = dispatch(db, action, ctx)
        if case .ok = result { XCTFail("\(action) should have failed") }
        return result.error!
    }
}

private func field(_ value: JSONValue, _ key: String) -> String? {
    guard case .object(let fields) = value, case .string(let text) = fields[key] ?? .null else { return nil }
    return text
}

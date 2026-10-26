import Foundation

public func formatPercent(_ percentage: Double?) -> String {
    guard let percentage else { return "—" }
    return String(format: "%.1f%%", locale: Foundation.Locale(identifier: "en_US_POSIX"), percentage * 100)
}

private func byName(_ lhs: Person, _ rhs: Person) -> Bool {
    let name = compareText(lhs.name, rhs.name)
    if name != .orderedSame { return name == .orderedAscending }
    return isBefore(lhs.id, rhs.id)
}

private func byDate(_ lhs: AdeEvent, _ rhs: AdeEvent) -> Bool {
    let date = compareText(lhs.date, rhs.date)
    if date != .orderedSame { return date == .orderedAscending }
    return isBefore(lhs.id, rhs.id)
}

private func eventsFor(_ db: Database, _ query: AttendanceQuery) -> [AdeEvent] {
    db.events.filter { event in
        if event.spaceId != query.spaceId { return false }
        if let eventId = query.eventId, event.id != eventId { return false }
        if let componentId = query.componentId, event.componentId != componentId { return false }
        if let categoryId = query.categoryId, event.categoryId != categoryId { return false }
        if let periodId = query.periodId {
            guard let period = db.periods.first(where: { $0.id == periodId }) else { return false }
            if !dateInRange(event.date, start: period.startDate, end: period.endDate) { return false }
        }
        return true
    }.sorted(by: byDate)
}

private func peopleFor(_ db: Database, _ query: AttendanceQuery) -> [Person] {
    let people = db.people.filter { $0.spaceId == query.spaceId }
    if let personId = query.personId {
        return people.filter { $0.id == personId }.sorted(by: byName)
    }
    guard let groupId = query.groupId else { return people.sorted(by: byName) }
    var windowStart = "0000-01-01"
    var windowEnd: String? = nil
    if let periodId = query.periodId {
        guard let period = db.periods.first(where: { $0.id == periodId }) else { return [] }
        windowStart = period.startDate
        windowEnd = period.endDate
    } else if let eventId = query.eventId {
        guard let event = db.events.first(where: { $0.id == eventId }) else { return [] }
        windowStart = event.date
        windowEnd = event.date
    }
    let memberIds = Set(db.memberships.filter { membership in
        membership.spaceId == query.spaceId && membership.groupId == groupId && rangesOverlap(
            aStart: membership.startDate,
            aEnd: membership.endDate,
            bStart: windowStart,
            bEnd: windowEnd
        )
    }.map(\.personId))
    return people.filter { memberIds.contains($0.id) }.sorted(by: byName)
}

private func latestRecord(_ records: [AttendanceRecord], eventId: String, personId: String) -> AttendanceRecord? {
    records.filter { $0.eventId == eventId && $0.personId == personId }.max { $0.updatedAt < $1.updatedAt }
}

public func attendanceLines(_ db: Database, _ query: AttendanceQuery) -> [AttendanceLine] {
    let events = eventsFor(db, query)
    let people = peopleFor(db, query)
    var lines: [AttendanceLine] = []
    for person in people {
        for event in events {
            lines.append(lineFor(db, query, event, person.id))
        }
    }
    return lines
}

private func lineFor(_ db: Database, _ query: AttendanceQuery, _ event: AdeEvent, _ personId: String) -> AttendanceLine {
    if !event.participantIds.contains(personId) {
        return AttendanceLine(eventId: event.id, personId: personId, outcome: "excluded", reason: .notParticipant, state: nil)
    }
    if let groupId = query.groupId, !isMemberOnDate(db, groupId: groupId, personId: personId, date: event.date) {
        return AttendanceLine(eventId: event.id, personId: personId, outcome: "excluded", reason: .notMemberOnDate, state: nil)
    }
    if event.status == .cancelled {
        return AttendanceLine(eventId: event.id, personId: personId, outcome: "excluded", reason: .cancelled, state: nil)
    }
    if !event.countsForAttendance {
        return AttendanceLine(eventId: event.id, personId: personId, outcome: "excluded", reason: .notCounting, state: nil)
    }
    guard let record = latestRecord(db.attendance, eventId: event.id, personId: personId) else {
        return AttendanceLine(eventId: event.id, personId: personId, outcome: "excluded", reason: .unrecorded, state: nil)
    }
    if record.state == .pending || record.state == .excused {
        return AttendanceLine(eventId: event.id, personId: personId, outcome: "excluded", reason: record.state == .pending ? .pending : .excused, state: record.state)
    }
    return AttendanceLine(eventId: event.id, personId: personId, outcome: record.state.rawValue, reason: nil, state: record.state)
}

public func summarizeAttendance(_ lines: [AttendanceLine]) -> AttendanceBreakdown {
    var breakdown = AttendanceBreakdown(
        present: 0, absent: 0, excused: 0, pending: 0, unrecorded: 0,
        excludedCancelled: 0, excludedNotCounting: 0, excludedNotParticipant: 0, excludedNotMember: 0,
        denominator: 0, percentage: nil, formula: attendanceFormula, lines: lines
    )
    for line in lines {
        if line.outcome == "present" { breakdown.present += 1 }
        else if line.outcome == "absent" { breakdown.absent += 1 }
        else if line.reason == .excused { breakdown.excused += 1 }
        else if line.reason == .pending { breakdown.pending += 1 }
        else if line.reason == .unrecorded { breakdown.unrecorded += 1 }
        else if line.reason == .cancelled { breakdown.excludedCancelled += 1 }
        else if line.reason == .notCounting { breakdown.excludedNotCounting += 1 }
        else if line.reason == .notParticipant { breakdown.excludedNotParticipant += 1 }
        else if line.reason == .notMemberOnDate { breakdown.excludedNotMember += 1 }
    }
    breakdown.denominator = breakdown.present + breakdown.absent
    breakdown.percentage = breakdown.denominator == 0 ? nil : Double(breakdown.present) / Double(breakdown.denominator)
    return breakdown
}

public func computeAttendance(_ db: Database, _ query: AttendanceQuery) -> AttendanceBreakdown {
    summarizeAttendance(attendanceLines(db, query))
}

public func attendanceByPerson(_ db: Database, _ query: AttendanceQuery) -> [(person: Person, breakdown: AttendanceBreakdown)] {
    peopleFor(db, query).map { person in
        var next = query
        next.personId = person.id
        return (person, computeAttendance(db, next))
    }
}

public func isMemberOnDate(_ db: Database, groupId: String, personId: String, date: String) -> Bool {
    db.memberships.contains { membership in
        membership.groupId == groupId && membership.personId == personId && dateInRange(date, start: membership.startDate, end: membership.endDate)
    }
}

public func membersAt(_ db: Database, groupId: String, date: String) -> [Person] {
    let ids = Set(db.memberships.filter { $0.groupId == groupId && dateInRange(date, start: $0.startDate, end: $0.endDate) }.map(\.personId))
    return db.people.filter { ids.contains($0.id) }.sorted(by: byName)
}

func findMembershipOverlap(_ memberships: [GroupMembership], groupId: String, personId: String, startDate: String, endDate: String?, ignoreId: String? = nil) -> GroupMembership? {
    memberships.first { membership in
        membership.id != ignoreId && membership.groupId == groupId && membership.personId == personId && rangesOverlap(
            aStart: membership.startDate, aEnd: membership.endDate, bStart: startDate, bEnd: endDate
        )
    }
}

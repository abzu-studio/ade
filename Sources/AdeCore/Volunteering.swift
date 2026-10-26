import Foundation

public func canTransitionVolunteer(from: VolunteerState?, to: VolunteerState) -> Bool {
    if from == to { return true }
    if from == nil { return to == .interested || to == .selected }
    return volunteerTransitions[from!]!.contains(to)
}

public func consumingVolunteerCount(_ db: Database, eventId: String, ignorePersonId: String? = nil) -> Int {
    db.volunteering.filter { record in
        record.eventId == eventId && record.personId != ignorePersonId && consumesVolunteerCapacity(record.state)
    }.count
}

public func suggestVolunteers(_ db: Database, eventId: String) -> [VolunteerSuggestion] {
    guard let event = db.events.first(where: { $0.id == eventId }) else { return [] }
    var suggestions = db.people.filter { $0.spaceId == event.spaceId && $0.status == .active }.map { person in
        scorePerson(db, eventId: event.id, personId: person.id, name: person.name)
    }
    suggestions.sort { lhs, rhs in
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.completedCount != rhs.completedCount { return lhs.completedCount > rhs.completedCount }
        let name = compareText(lhs.name, rhs.name)
        if name != .orderedSame { return name == .orderedAscending }
        return isBefore(lhs.personId, rhs.personId)
    }
    return suggestions
}

private func scorePerson(_ db: Database, eventId: String, personId: String, name: String) -> VolunteerSuggestion {
    let event = db.events.first { $0.id == eventId }!
    let current = db.volunteering.first { $0.eventId == eventId && $0.personId == personId }
    var completedCount = 0
    var recentCompleted = 0
    var sameComponentCompleted = 0
    var selected = 0
    var priorInterested = 0
    var declined = 0
    var absent = 0
    for record in db.volunteering {
        if record.personId != personId || record.eventId == eventId { continue }
        guard let other = db.events.first(where: { $0.id == record.eventId }), other.spaceId == event.spaceId, other.date < event.date else { continue }
        switch record.state {
        case .completed:
            completedCount += 1
            let days = daysBetween(other.date, event.date)
            if days > 0 && days <= VolunteerWeights.recentDays { recentCompleted += 1 }
            if other.componentId == event.componentId { sameComponentCompleted += 1 }
        case .selected: selected += 1
        case .interested: priorInterested += 1
        case .declined: declined += 1
        case .absent: absent += 1
        }
    }
    var presentCount = 0
    for record in db.attendance where record.personId == personId && record.state == .present {
        guard let other = db.events.first(where: { $0.id == record.eventId }),
              other.spaceId == event.spaceId, other.date < event.date,
              other.status != .cancelled, other.countsForAttendance,
              other.participantIds.contains(personId) else { continue }
        presentCount += 1
    }
    var factors: [ScoreFactor] = []
    func push(_ code: ScoreFactorCode, _ count: Int, _ pointsEach: Int, cap: Int? = nil) {
        if count <= 0 { return }
        let used = min(count, cap ?? count)
        factors.append(ScoreFactor(code: code, count: count, points: used * pointsEach))
    }
    push(.completed, completedCount, VolunteerWeights.completed)
    push(.recentCompleted, recentCompleted, VolunteerWeights.recentCompleted)
    push(.sameComponentCompleted, sameComponentCompleted, VolunteerWeights.sameComponentCompleted)
    push(.selected, selected, VolunteerWeights.selected)
    push(.priorInterested, priorInterested, VolunteerWeights.priorInterested)
    push(.declined, declined, VolunteerWeights.declined)
    push(.absent, absent, VolunteerWeights.absent)
    push(.attendancePresent, presentCount, VolunteerWeights.attendancePresent, cap: VolunteerWeights.attendancePresentCap)
    if current?.state == .interested {
        factors.append(ScoreFactor(code: .interestedNow, count: 1, points: VolunteerWeights.interestedNow))
    }
    if factors.isEmpty {
        factors.append(ScoreFactor(code: .noHistory, count: 0, points: 0))
    }
    let score = factors.reduce(0) { $0 + $1.points }
    return VolunteerSuggestion(
        personId: personId,
        name: name,
        score: score,
        completedCount: completedCount,
        eligible: current == nil || current?.state == .interested,
        factors: factors
    )
}

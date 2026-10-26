import Foundation

private func object(_ value: JSONValue) -> [String: JSONValue]? {
    if case .object(let fields) = value { return fields }
    return nil
}

private func string(_ value: JSONValue?) -> String? {
    if case .string(let text)? = value { return text }
    return nil
}

private func flag(_ value: JSONValue?) -> Bool? {
    if case .bool(let value)? = value { return value }
    return nil
}

private func number(_ value: JSONValue?) -> Double? {
    switch value {
    case .int(let value)?: return Double(value)
    case .double(let value)? where value.isFinite: return value
    default: return nil
    }
}

private func whole(_ value: JSONValue?) -> Int? {
    switch value {
    case .int(let value)?: return value
    case .double(let value)? where value.isFinite && value.rounded() == value && abs(value) <= Double(Int.max):
        return Int(value)
    default: return nil
    }
}

private func stringOrNull(_ fields: [String: JSONValue], _ key: String) -> String?? {
    guard let value = fields[key] else { return nil }
    if case .null = value { return .some(nil) }
    if case .string(let text) = value { return .some(text) }
    return nil
}

private func intOrNull(_ fields: [String: JSONValue], _ key: String) -> Int?? {
    guard let value = fields[key] else { return nil }
    if case .null = value { return .some(nil) }
    guard let number = whole(value) else { return nil }
    return .some(number)
}

private func readArray<T>(_ value: JSONValue?, _ read: (JSONValue) -> T?) -> [T]? {
    guard case .array(let items)? = value else { return nil }
    var parsed: [T] = []
    for item in items {
        guard let value = read(item) else { return nil }
        parsed.append(value)
    }
    return parsed
}

private func stamp(_ fields: [String: JSONValue]) -> (createdAt: String, updatedAt: String)? {
    guard let createdAt = string(fields["createdAt"]), let updatedAt = string(fields["updatedAt"]),
          isIsoDateTime(createdAt), isIsoDateTime(updatedAt) else { return nil }
    return (createdAt, updatedAt)
}

private func readSpace(_ value: JSONValue) -> Space? {
    guard let fields = object(value), let id = string(fields["id"]), let name = string(fields["name"]),
          !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let times = stamp(fields) else { return nil }
    return Space(id: id, name: name, createdAt: times.createdAt, updatedAt: times.updatedAt)
}

private func readPerson(_ value: JSONValue) -> Person? {
    guard let fields = object(value), let id = string(fields["id"]), let spaceId = string(fields["spaceId"]),
          let name = string(fields["name"]), !name.isEmpty, let email = string(fields["email"]), let notes = string(fields["notes"]),
          let status = string(fields["status"]).flatMap(PersonStatus.init), let times = stamp(fields) else { return nil }
    return Person(id: id, spaceId: spaceId, name: name, email: email, notes: notes, status: status, createdAt: times.createdAt, updatedAt: times.updatedAt)
}

private func readGroup(_ value: JSONValue) -> Group? {
    guard let fields = object(value), let id = string(fields["id"]), let spaceId = string(fields["spaceId"]),
          let name = string(fields["name"]), let description = string(fields["description"]), let times = stamp(fields) else { return nil }
    return Group(id: id, spaceId: spaceId, name: name, description: description, createdAt: times.createdAt, updatedAt: times.updatedAt)
}

private func readMembership(_ value: JSONValue) -> GroupMembership? {
    guard let fields = object(value), let id = string(fields["id"]), let spaceId = string(fields["spaceId"]),
          let groupId = string(fields["groupId"]), let personId = string(fields["personId"]),
          let startDate = string(fields["startDate"]), let endDate = stringOrNull(fields, "endDate"),
          let times = stamp(fields), isIsoDate(startDate), endDate == nil || isIsoDate(endDate!) else { return nil }
    return GroupMembership(id: id, spaceId: spaceId, groupId: groupId, personId: personId, startDate: startDate, endDate: endDate, createdAt: times.createdAt, updatedAt: times.updatedAt)
}

private func readPeriod(_ value: JSONValue) -> Period? {
    guard let fields = object(value), let id = string(fields["id"]), let spaceId = string(fields["spaceId"]),
          let name = string(fields["name"]), let startDate = string(fields["startDate"]), let endDate = string(fields["endDate"]),
          let times = stamp(fields), isIsoDate(startDate), isIsoDate(endDate) else { return nil }
    return Period(id: id, spaceId: spaceId, name: name, startDate: startDate, endDate: endDate, createdAt: times.createdAt, updatedAt: times.updatedAt)
}

private func readComponent(_ value: JSONValue) -> ActivityComponent? {
    guard let fields = object(value), let id = string(fields["id"]), let spaceId = string(fields["spaceId"]),
          let name = string(fields["name"]), let description = string(fields["description"]), let times = stamp(fields) else { return nil }
    return ActivityComponent(id: id, spaceId: spaceId, name: name, description: description, createdAt: times.createdAt, updatedAt: times.updatedAt)
}

private func readCategory(_ value: JSONValue) -> Category? {
    guard let fields = object(value), let id = string(fields["id"]), let spaceId = string(fields["spaceId"]),
          let componentId = string(fields["componentId"]), let name = string(fields["name"]),
          let description = string(fields["description"]), let times = stamp(fields) else { return nil }
    return Category(id: id, spaceId: spaceId, componentId: componentId, name: name, description: description, createdAt: times.createdAt, updatedAt: times.updatedAt)
}

private func readEvent(_ value: JSONValue) -> AdeEvent? {
    guard let fields = object(value), let id = string(fields["id"]), let spaceId = string(fields["spaceId"]),
          let title = string(fields["title"]), let description = string(fields["description"]),
          let date = string(fields["date"]), let componentId = string(fields["componentId"]),
          let categoryId = stringOrNull(fields, "categoryId"),
          let participantIds = readArray(fields["participantIds"], { string($0) }),
          let capacity = intOrNull(fields, "capacity"),
          let counts = flag(fields["countsForAttendance"]),
          let status = string(fields["status"]).flatMap(EventStatus.init),
          let volunteerCapacity = intOrNull(fields, "volunteerCapacity"),
          let duplicatedFromId = stringOrNull(fields, "duplicatedFromId"),
          let times = stamp(fields), isIsoDate(date) else { return nil }
    return AdeEvent(id: id, spaceId: spaceId, title: title, description: description, date: date, componentId: componentId, categoryId: categoryId, participantIds: participantIds, capacity: capacity, countsForAttendance: counts, status: status, volunteerCapacity: volunteerCapacity, duplicatedFromId: duplicatedFromId, createdAt: times.createdAt, updatedAt: times.updatedAt)
}

private func readAttendanceHistory(_ value: JSONValue) -> AttendanceHistoryEntry? {
    guard let fields = object(value), let at = string(fields["at"]), let actorId = string(fields["actorId"]),
          let previous = stringOrNull(fields, "previousState"), let next = string(fields["nextState"]).flatMap(AttendanceState.init),
          previous == nil || AttendanceState(rawValue: previous!) != nil,
          let previousNote = string(fields["previousNote"]), let nextNote = string(fields["nextNote"]) else { return nil }
    return AttendanceHistoryEntry(at: at, actorId: actorId, previousState: previous.flatMap(AttendanceState.init), nextState: next, previousNote: previousNote, nextNote: nextNote)
}

private func readAttendance(_ value: JSONValue) -> AttendanceRecord? {
    guard let fields = object(value), let id = string(fields["id"]), let spaceId = string(fields["spaceId"]),
          let eventId = string(fields["eventId"]), let personId = string(fields["personId"]),
          let state = string(fields["state"]).flatMap(AttendanceState.init), let note = string(fields["note"]),
          let history = readArray(fields["history"], readAttendanceHistory), let times = stamp(fields) else { return nil }
    return AttendanceRecord(id: id, spaceId: spaceId, eventId: eventId, personId: personId, state: state, note: note, history: history, createdAt: times.createdAt, updatedAt: times.updatedAt)
}

private func readVolunteerHistory(_ value: JSONValue) -> VolunteerHistoryEntry? {
    guard let fields = object(value), let at = string(fields["at"]), let actorId = string(fields["actorId"]),
          let previous = stringOrNull(fields, "previousState"), let next = string(fields["nextState"]).flatMap(VolunteerState.init),
          previous == nil || VolunteerState(rawValue: previous!) != nil,
          let previousNote = string(fields["previousNote"]), let nextNote = string(fields["nextNote"]) else { return nil }
    return VolunteerHistoryEntry(at: at, actorId: actorId, previousState: previous.flatMap(VolunteerState.init), nextState: next, previousNote: previousNote, nextNote: nextNote)
}

private func readVolunteer(_ value: JSONValue) -> VolunteerRecord? {
    guard let fields = object(value), let id = string(fields["id"]), let spaceId = string(fields["spaceId"]),
          let eventId = string(fields["eventId"]), let personId = string(fields["personId"]),
          let state = string(fields["state"]).flatMap(VolunteerState.init), let note = string(fields["note"]),
          let history = readArray(fields["history"], readVolunteerHistory), let times = stamp(fields) else { return nil }
    return VolunteerRecord(id: id, spaceId: spaceId, eventId: eventId, personId: personId, state: state, note: note, history: history, createdAt: times.createdAt, updatedAt: times.updatedAt)
}

private func readElement(_ value: JSONValue) -> TemplateElement? {
    guard let fields = object(value), let id = string(fields["id"]), let type = string(fields["type"]),
          let x = number(fields["x"]), let y = number(fields["y"]), let width = number(fields["width"]), let height = number(fields["height"]) else { return nil }
    switch type {
    case "text":
        guard let text = string(fields["text"]), let binding = stringOrNull(fields, "binding"),
              binding == nil || TextBinding(rawValue: binding!) != nil,
              let fontSize = number(fields["fontSize"]), let align = string(fields["align"]).flatMap(TextAlign.init) else { return nil }
        return .text(TemplateTextElement(id: id, x: x, y: y, width: width, height: height, text: text, binding: binding.flatMap(TextBinding.init), fontSize: fontSize, align: align))
    case "image":
        guard let assetId = string(fields["assetId"]) else { return nil }
        return .image(TemplateImageElement(id: id, x: x, y: y, width: width, height: height, assetId: assetId))
    case "columns":
        guard let columns = whole(fields["columns"]), let gap = number(fields["gap"]),
              let binding = string(fields["binding"]).flatMap(ListBinding.init), let fontSize = number(fields["fontSize"]) else { return nil }
        return .columns(TemplateColumnsElement(id: id, x: x, y: y, width: width, height: height, columns: columns, gap: gap, binding: binding, fontSize: fontSize))
    default:
        return nil
    }
}

private func readTemplate(_ value: JSONValue) -> DocumentTemplate? {
    guard let fields = object(value), let id = string(fields["id"]), let spaceId = string(fields["spaceId"]),
          let name = string(fields["name"]), let description = string(fields["description"]),
          let pageSize = string(fields["pageSize"]).flatMap(PageSize.init),
          let background = stringOrNull(fields, "backgroundAssetId"),
          let elements = readArray(fields["elements"], readElement), let times = stamp(fields) else { return nil }
    return DocumentTemplate(id: id, spaceId: spaceId, name: name, description: description, pageSize: pageSize, backgroundAssetId: background, elements: elements, createdAt: times.createdAt, updatedAt: times.updatedAt)
}

private func readAsset(_ value: JSONValue) -> Asset? {
    guard let fields = object(value), let id = string(fields["id"]), let spaceId = string(fields["spaceId"]),
          let name = string(fields["name"]), let mime = string(fields["mime"]).flatMap(AssetMime.init),
          let data = string(fields["dataBase64"]), let createdAt = string(fields["createdAt"]), isIsoDateTime(createdAt),
          let deletedAt = stringOrNull(fields, "deletedAt"), deletedAt == nil || isIsoDateTime(deletedAt!) else { return nil }
    return Asset(id: id, spaceId: spaceId, name: name, mime: mime, dataBase64: data, createdAt: createdAt, deletedAt: deletedAt)
}

private func readTombstone(_ value: JSONValue) -> Tombstone? {
    guard let fields = object(value), let id = string(fields["id"]), let spaceId = string(fields["spaceId"]),
          let entityType = string(fields["entityType"]).flatMap(EntityType.init), let entityId = string(fields["entityId"]),
          let naturalKey = string(fields["naturalKey"]), let deletedAt = string(fields["deletedAt"]),
          let deletedBy = string(fields["deletedBy"]), fields["payload"] != nil else { return nil }
    return Tombstone(id: id, spaceId: spaceId, entityType: entityType, entityId: entityId, naturalKey: naturalKey, deletedAt: deletedAt, deletedBy: deletedBy, payload: fields["payload"]!)
}

private func readConflict(_ value: JSONValue) -> ConflictRecord? {
    guard let fields = object(value), let id = string(fields["id"]), let spaceId = string(fields["spaceId"]),
          let entityType = string(fields["entityType"]).flatMap(EntityType.init), let key = string(fields["key"]),
          let localId = stringOrNull(fields, "localEntityId"), let remoteId = stringOrNull(fields, "remoteEntityId"),
          let remoteDeleted = flag(fields["remoteDeleted"]), let createdAt = string(fields["createdAt"]),
          let resolvedAt = stringOrNull(fields, "resolvedAt"),
          let resolution = string(fields["resolution"]).flatMap(ConflictResolution.init),
          let materializedId = stringOrNull(fields, "materializedId") else { return nil }
    return ConflictRecord(
        id: id, spaceId: spaceId, entityType: entityType, key: key,
        localEntityId: localId, remoteEntityId: remoteId,
        local: fields["local"] ?? .null, remote: fields["remote"] ?? .null,
        remoteDeleted: remoteDeleted, createdAt: createdAt, resolvedAt: resolvedAt,
        resolution: resolution, materializedId: materializedId
    )
}

private func readSnapshot(_ value: JSONValue) -> SpaceSnapshot? {
    guard let fields = object(value), let space = fields["space"].flatMap(readSpace),
          let people = readArray(fields["people"], readPerson),
          let groups = readArray(fields["groups"], readGroup),
          let memberships = readArray(fields["memberships"], readMembership),
          let periods = readArray(fields["periods"], readPeriod),
          let components = readArray(fields["components"], readComponent),
          let categories = readArray(fields["categories"], readCategory),
          let events = readArray(fields["events"], readEvent),
          let attendance = readArray(fields["attendance"], readAttendance),
          let volunteering = readArray(fields["volunteering"], readVolunteer),
          let templates = readArray(fields["templates"], readTemplate),
          let assets = readArray(fields["assets"], readAsset),
          let conflicts = readArray(fields["conflicts"], readConflict),
          let tombstones = readArray(fields["tombstones"], readTombstone) else { return nil }
    return SpaceSnapshot(space: space, people: people, groups: groups, memberships: memberships, periods: periods, components: components, categories: categories, events: events, attendance: attendance, volunteering: volunteering, templates: templates, assets: assets, conflicts: conflicts, tombstones: tombstones)
}

private func readRevision(_ value: JSONValue) -> Revision? {
    guard let fields = object(value), let id = string(fields["id"]), let spaceId = string(fields["spaceId"]),
          let at = string(fields["at"]), let actorId = string(fields["actorId"]), let action = string(fields["action"]),
          let params = stringMap(fields["params"]), let snapshot = fields["snapshot"].flatMap(readSnapshot) else { return nil }
    return Revision(id: id, spaceId: spaceId, at: at, actorId: actorId, action: action, params: params, snapshot: snapshot)
}

private func stringMap(_ value: JSONValue?) -> [String: String]? {
    guard let fields = value.flatMap(object) else { return nil }
    var out: [String: String] = [:]
    for (key, entry) in fields {
        guard let text = string(entry) else { return nil }
        out[key] = text
    }
    return out
}

private func readHistory(_ value: JSONValue) -> SpaceHistory? {
    guard let fields = object(value), let spaceId = string(fields["spaceId"]),
          let revisionIds = readArray(fields["revisionIds"], { string($0) }),
          let cursor = whole(fields["cursor"]), cursor >= -1, cursor < revisionIds.count else { return nil }
    return SpaceHistory(spaceId: spaceId, revisionIds: revisionIds, cursor: cursor)
}

public func sanitizeDatabase(_ value: JSONValue) -> CoreResult<Database> {
    guard let fields = object(value), string(fields["format"]) == databaseFormat,
          let actor = fields["actor"].flatMap(object), let actorId = string(actor["id"]), let actorName = string(actor["name"]),
          let locale = string(fields["locale"]).flatMap(AdeLocale.init),
          let spaces = readArray(fields["spaces"], readSpace),
          let people = readArray(fields["people"], readPerson),
          let groups = readArray(fields["groups"], readGroup),
          let memberships = readArray(fields["memberships"], readMembership),
          let periods = readArray(fields["periods"], readPeriod),
          let components = readArray(fields["components"], readComponent),
          let categories = readArray(fields["categories"], readCategory),
          let events = readArray(fields["events"], readEvent),
          let attendance = readArray(fields["attendance"], readAttendance),
          let volunteering = readArray(fields["volunteering"], readVolunteer),
          let templates = readArray(fields["templates"], readTemplate),
          let assets = readArray(fields["assets"], readAsset),
          let conflicts = readArray(fields["conflicts"], readConflict),
          let tombstones = readArray(fields["tombstones"], readTombstone),
          let revisions = readArray(fields["revisions"], readRevision),
          let histories = readArray(fields["histories"], readHistory) else { return err(.INVALID_IMPORT) }
    let revisionIds = Set(revisions.map(\.id))
    let clean = histories.map { history in
        SpaceHistory(spaceId: history.spaceId, revisionIds: history.revisionIds.filter { revisionIds.contains($0) }, cursor: history.cursor)
    }
    if clean.contains(where: { $0.cursor >= $0.revisionIds.count }) { return err(.INVALID_IMPORT) }
    return ok(Database(
        format: databaseFormat, actor: Actor(id: actorId, name: actorName), locale: locale,
        spaces: spaces, people: people, groups: groups, memberships: memberships, periods: periods,
        components: components, categories: categories, events: events, attendance: attendance,
        volunteering: volunteering, templates: templates, assets: assets, conflicts: conflicts,
        tombstones: tombstones, revisions: revisions, histories: clean
    ))
}

public func sanitizeSyncBundle(_ value: JSONValue) -> CoreResult<SyncBundle> {
    guard let fields = object(value), string(fields["format"]) == syncFormat,
          let exportedAt = string(fields["exportedAt"]), let actor = fields["actor"].flatMap(object),
          let actorId = string(actor["id"]), let actorName = string(actor["name"]),
          let snapshot = fields["snapshot"].flatMap(readSnapshot),
          let tombstones = readArray(fields["tombstones"], readTombstone) else { return err(.INVALID_IMPORT) }
    return ok(SyncBundle(format: syncFormat, exportedAt: exportedAt, actor: Actor(id: actorId, name: actorName), snapshot: snapshot, tombstones: tombstones))
}

public func sanitizeBackup(_ value: JSONValue) -> CoreResult<BackupFile> {
    guard let fields = object(value), string(fields["format"]) == backupFormat, let exportedAt = string(fields["exportedAt"]),
          let database = fields["database"], case .ok(let parsed) = sanitizeDatabase(database) else { return err(.INVALID_IMPORT) }
    return ok(BackupFile(format: backupFormat, exportedAt: exportedAt, database: parsed))
}

func jsonValue<T: Encodable>(of value: T) -> JSONValue {
    (try? JSONValue.fromEncodable(value)) ?? .null
}

func decodeModel<T: Decodable>(_ value: JSONValue, as type: T.Type) -> T? {
    guard let data = try? encodeJSON(value, pretty: false) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
}

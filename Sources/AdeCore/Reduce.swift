import Foundation

private func cleanName(_ value: String) -> CoreResult<String> {
    let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if name.isEmpty { return err(.NAME_REQUIRED) }
    return ok(name)
}

private func cleanDate(_ value: String) -> CoreResult<String> {
    isIsoDate(value) ? ok(value) : err(.INVALID_DATE)
}

private func cleanRange(_ start: String, _ end: String?) -> CoreResult<(start: String, end: String?)> {
    if !isIsoDate(start) || (end != nil && !isIsoDate(end!)) { return err(.INVALID_DATE) }
    if let end, end < start { return err(.INVALID_DATE_RANGE) }
    return ok((start, end))
}

private func cleanCapacity(_ value: Int?) -> CoreResult<Int?> {
    if let value, value < 0 { return err(.INVALID_CAPACITY) }
    return ok(value)
}

private func failure<T, U>(_ result: CoreResult<T>) -> CoreResult<U>? {
    if case .err(let error) = result { return .err(error) }
    return nil
}

private func commit(_ db: Database, _ spaceId: String, _ action: String, _ params: [String: String], _ ctx: ReduceContext) -> Database {
    let revision = Revision(
        id: ctx.newId(), spaceId: spaceId, at: ctx.now, actorId: ctx.actorId,
        action: action, params: params, snapshot: takeSnapshot(db, spaceId)
    )
    let history = db.histories.first { $0.spaceId == spaceId } ?? SpaceHistory(spaceId: spaceId, revisionIds: [], cursor: -1)
    let kept = Array(history.revisionIds.prefix(history.cursor + 1))
    let dropped = Set(history.revisionIds.dropFirst(history.cursor + 1))
    var next = db
    next.revisions = db.revisions.filter { !dropped.contains($0.id) } + [revision]
    next.histories = db.histories.filter { $0.spaceId != spaceId } + [SpaceHistory(spaceId: spaceId, revisionIds: kept + [revision.id], cursor: kept.count)]
    return next
}

private func setCursor(_ db: Database, _ spaceId: String, _ cursor: Int) -> Database {
    var next = db
    next.histories = db.histories.map { history in
        guard history.spaceId == spaceId else { return history }
        return SpaceHistory(spaceId: spaceId, revisionIds: history.revisionIds, cursor: cursor)
    }
    return next
}

private func tombstone<T: Encodable>(_ db: Database, _ entityType: EntityType, _ entity: T, _ spaceId: String, _ entityId: String, _ naturalKey: String, _ ctx: ReduceContext) -> Database {
    let stone = Tombstone(
        id: ctx.newId(), spaceId: spaceId, entityType: entityType, entityId: entityId,
        naturalKey: naturalKey, deletedAt: ctx.now, deletedBy: ctx.actorId, payload: jsonValue(of: entity)
    )
    var next = db
    next.tombstones = db.tombstones + [stone]
    return next
}

private func requireSpace(_ db: Database, _ spaceId: String) -> CoreResult<Bool> {
    db.spaces.contains { $0.id == spaceId } ? ok(true) : err(.NOT_FOUND, ["entity": "space"])
}

private func categoryOk(_ db: Database, _ spaceId: String, _ componentId: String, _ categoryId: String?) -> CoreResult<Bool> {
    guard let component = db.components.first(where: { $0.id == componentId }), component.spaceId == spaceId else {
        return err(.NOT_FOUND, ["entity": "component"])
    }
    guard let categoryId else { return ok(true) }
    guard let category = db.categories.first(where: { $0.id == categoryId }), category.spaceId == spaceId else {
        return err(.NOT_FOUND, ["entity": "category"])
    }
    if category.componentId != componentId { return err(.CATEGORY_COMPONENT_MISMATCH) }
    return ok(true)
}

private func withIds(_ elements: [ElementDraft], _ ctx: ReduceContext) -> [TemplateElement] {
    elements.map { draft in
        switch draft {
        case .text(let text):
            return .text(TemplateTextElement(id: text.id ?? ctx.newId(), x: text.x, y: text.y, width: text.width, height: text.height, text: text.text, binding: text.binding, fontSize: text.fontSize, align: text.align))
        case .image(let image):
            return .image(TemplateImageElement(id: image.id ?? ctx.newId(), x: image.x, y: image.y, width: image.width, height: image.height, assetId: image.assetId))
        case .columns(let columns):
            return .columns(TemplateColumnsElement(id: columns.id ?? ctx.newId(), x: columns.x, y: columns.y, width: columns.width, height: columns.height, columns: columns.columns, gap: columns.gap, binding: columns.binding, fontSize: columns.fontSize))
        }
    }
}

private func participantsOk(_ db: Database, _ spaceId: String, _ participantIds: [String], _ capacity: Int?) -> CoreResult<[String]> {
    if Set(participantIds).count != participantIds.count { return err(.DUPLICATE_PARTICIPANT) }
    for personId in participantIds {
        guard let person = db.people.first(where: { $0.id == personId }), person.spaceId == spaceId else {
            return err(.NOT_FOUND, ["entity": "person"])
        }
    }
    if let capacity, participantIds.count > capacity {
        return err(.CAPACITY_EXCEEDED, ["capacity": String(capacity), "used": String(participantIds.count)])
    }
    return ok(participantIds)
}

private func upsert<T: Identifiable>(_ list: [T], _ item: T) -> [T] where T.ID == String {
    list.contains { $0.id == item.id } ? list.map { $0.id == item.id ? item : $0 } : list + [item]
}

private func applyRemote(_ db: Database, _ conflict: ConflictRecord, _ ctx: ReduceContext) -> CoreResult<Database> {
    if conflict.remoteDeleted { return deleteByConflict(db, conflict, ctx) }
    guard case .object(let fields) = conflict.remote else { return err(.INVALID_IMPORT) }
    let remoteId: String? = {
        if case .string(let id) = fields["id"] ?? .null, !id.isEmpty { return id }
        return nil
    }()
    let remoteSpaceId: String? = {
        if case .string(let id) = fields["spaceId"] ?? .null { return id }
        return nil
    }()
    guard remoteId != nil, remoteSpaceId == conflict.spaceId else { return err(.INVALID_IMPORT) }
    switch conflict.entityType {
    case .space:
        guard let space = decodeModel(conflict.remote, as: Space.self) else { return err(.INVALID_IMPORT) }
        var next = db
        next.spaces = db.spaces.map { $0.id == space.id ? space : $0 }
        return ok(next)
    case .person:
        guard let person = decodeModel(conflict.remote, as: Person.self) else { return err(.INVALID_IMPORT) }
        var next = db
        next.people = upsert(db.people, person)
        return ok(next)
    case .group:
        guard let group = decodeModel(conflict.remote, as: Group.self) else { return err(.INVALID_IMPORT) }
        var next = db
        next.groups = upsert(db.groups, group)
        return ok(next)
    case .membership:
        guard let membership = decodeModel(conflict.remote, as: GroupMembership.self) else { return err(.INVALID_IMPORT) }
        var next = db
        next.memberships = upsert(db.memberships, membership)
        return ok(next)
    case .period:
        guard let period = decodeModel(conflict.remote, as: Period.self) else { return err(.INVALID_IMPORT) }
        var next = db
        next.periods = upsert(db.periods, period)
        return ok(next)
    case .component:
        guard let component = decodeModel(conflict.remote, as: ActivityComponent.self) else { return err(.INVALID_IMPORT) }
        var next = db
        next.components = upsert(db.components, component)
        return ok(next)
    case .category:
        guard let category = decodeModel(conflict.remote, as: Category.self) else { return err(.INVALID_IMPORT) }
        var next = db
        next.categories = upsert(db.categories, category)
        return ok(next)
    case .event:
        guard let event = decodeModel(conflict.remote, as: AdeEvent.self) else { return err(.INVALID_IMPORT) }
        var next = db
        next.events = upsert(db.events, event)
        return ok(next)
    case .attendance:
        guard let record = decodeModel(conflict.remote, as: AttendanceRecord.self) else { return err(.INVALID_IMPORT) }
        var next = db
        next.attendance = db.attendance.filter { !($0.spaceId == record.spaceId && $0.eventId == record.eventId && $0.personId == record.personId) } + [record]
        return ok(next)
    case .volunteering:
        guard let record = decodeModel(conflict.remote, as: VolunteerRecord.self) else { return err(.INVALID_IMPORT) }
        var next = db
        next.volunteering = db.volunteering.filter { !($0.spaceId == record.spaceId && $0.eventId == record.eventId && $0.personId == record.personId) } + [record]
        return ok(next)
    case .template:
        guard let template = decodeModel(conflict.remote, as: DocumentTemplate.self) else { return err(.INVALID_IMPORT) }
        var next = db
        next.templates = upsert(db.templates, template)
        return ok(next)
    case .asset:
        guard let asset = decodeModel(conflict.remote, as: Asset.self) else { return err(.INVALID_IMPORT) }
        var next = db
        next.assets = upsert(db.assets, asset)
        return ok(next)
    }
}

private func deleteByConflict(_ db: Database, _ conflict: ConflictRecord, _ ctx: ReduceContext) -> CoreResult<Database> {
    guard let id = conflict.localEntityId else { return ok(db) }
    switch conflict.entityType {
    case .person:
        guard let person = db.people.first(where: { $0.id == id }) else { return ok(db) }
        var next = db
        next.people.removeAll { $0.id == id }
        return ok(tombstone(next, .person, person, person.spaceId, person.id, person.id, ctx))
    case .attendance:
        guard let record = db.attendance.first(where: { $0.id == id }) else { return ok(db) }
        var next = db
        next.attendance.removeAll { $0.id == id }
        return ok(tombstone(next, .attendance, record, record.spaceId, record.id, "\(record.eventId):\(record.personId)", ctx))
    default:
        return ok(removeGeneric(db, conflict.entityType, id, ctx))
    }
}

private func removeGeneric(_ db: Database, _ entityType: EntityType, _ id: String, _ ctx: ReduceContext) -> Database {
    switch entityType {
    case .group:
        guard let entity = db.groups.first(where: { $0.id == id }) else { return db }
        var next = db
        next.groups.removeAll { $0.id == id }
        return tombstone(next, .group, entity, entity.spaceId, entity.id, id, ctx)
    case .membership:
        guard let entity = db.memberships.first(where: { $0.id == id }) else { return db }
        var next = db
        next.memberships.removeAll { $0.id == id }
        return tombstone(next, .membership, entity, entity.spaceId, entity.id, id, ctx)
    case .period:
        guard let entity = db.periods.first(where: { $0.id == id }) else { return db }
        var next = db
        next.periods.removeAll { $0.id == id }
        return tombstone(next, .period, entity, entity.spaceId, entity.id, id, ctx)
    case .component:
        guard let entity = db.components.first(where: { $0.id == id }) else { return db }
        var next = db
        next.components.removeAll { $0.id == id }
        return tombstone(next, .component, entity, entity.spaceId, entity.id, id, ctx)
    case .category:
        guard let entity = db.categories.first(where: { $0.id == id }) else { return db }
        var next = db
        next.categories.removeAll { $0.id == id }
        return tombstone(next, .category, entity, entity.spaceId, entity.id, id, ctx)
    case .event:
        guard let entity = db.events.first(where: { $0.id == id }) else { return db }
        var next = db
        next.events.removeAll { $0.id == id }
        return tombstone(next, .event, entity, entity.spaceId, entity.id, id, ctx)
    case .volunteering:
        guard let entity = db.volunteering.first(where: { $0.id == id }) else { return db }
        var next = db
        next.volunteering.removeAll { $0.id == id }
        return tombstone(next, .volunteering, entity, entity.spaceId, entity.id, "\(entity.eventId):\(entity.personId)", ctx)
    case .template:
        guard let entity = db.templates.first(where: { $0.id == id }) else { return db }
        var next = db
        next.templates.removeAll { $0.id == id }
        return tombstone(next, .template, entity, entity.spaceId, entity.id, id, ctx)
    case .asset:
        guard let entity = db.assets.first(where: { $0.id == id }) else { return db }
        var next = db
        next.assets.removeAll { $0.id == id }
        return tombstone(next, .asset, entity, entity.spaceId, entity.id, id, ctx)
    default:
        return db
    }
}

private func materialize(_ db: Database, _ conflict: ConflictRecord, _ ctx: ReduceContext) -> (db: Database, materializedId: String?) {
    if conflict.remoteDeleted || conflict.remote == .null || conflict.entityType == .attendance || conflict.entityType == .volunteering || conflict.entityType == .space {
        return (db, nil)
    }
    let id = ctx.newId()
    switch conflict.entityType {
    case .person:
        guard var person = decodeModel(conflict.remote, as: Person.self) else { return (db, nil) }
        person.id = id
        person.createdAt = ctx.now
        person.updatedAt = ctx.now
        person.name += " (conflict)"
        var next = db
        next.people.append(person)
        return (next, id)
    case .group:
        guard var group = decodeModel(conflict.remote, as: Group.self) else { return (db, nil) }
        group.id = id
        group.createdAt = ctx.now
        group.updatedAt = ctx.now
        group.name += " (conflict)"
        var next = db
        next.groups.append(group)
        return (next, id)
    case .membership:
        guard var membership = decodeModel(conflict.remote, as: GroupMembership.self) else { return (db, nil) }
        membership.id = id
        membership.createdAt = ctx.now
        membership.updatedAt = ctx.now
        if findMembershipOverlap(db.memberships, groupId: membership.groupId, personId: membership.personId, startDate: membership.startDate, endDate: membership.endDate) != nil {
            return (db, nil)
        }
        var next = db
        next.memberships.append(membership)
        return (next, id)
    case .period:
        guard var period = decodeModel(conflict.remote, as: Period.self) else { return (db, nil) }
        period.id = id
        period.createdAt = ctx.now
        period.updatedAt = ctx.now
        period.name += " (conflict)"
        var next = db
        next.periods.append(period)
        return (next, id)
    case .component:
        guard var component = decodeModel(conflict.remote, as: ActivityComponent.self) else { return (db, nil) }
        component.id = id
        component.createdAt = ctx.now
        component.updatedAt = ctx.now
        component.name += " (conflict)"
        var next = db
        next.components.append(component)
        return (next, id)
    case .category:
        guard var category = decodeModel(conflict.remote, as: Category.self) else { return (db, nil) }
        category.id = id
        category.createdAt = ctx.now
        category.updatedAt = ctx.now
        category.name += " (conflict)"
        var next = db
        next.categories.append(category)
        return (next, id)
    case .event:
        guard var event = decodeModel(conflict.remote, as: AdeEvent.self) else { return (db, nil) }
        let original = event.id
        event.id = id
        event.createdAt = ctx.now
        event.updatedAt = ctx.now
        event.title += " (conflict)"
        event.duplicatedFromId = original
        var next = db
        next.events.append(event)
        return (next, id)
    case .template:
        guard var template = decodeModel(conflict.remote, as: DocumentTemplate.self) else { return (db, nil) }
        template.id = id
        template.createdAt = ctx.now
        template.updatedAt = ctx.now
        template.name += " (conflict)"
        var next = db
        next.templates.append(template)
        return (next, id)
    case .asset:
        guard var asset = decodeModel(conflict.remote, as: Asset.self) else { return (db, nil) }
        asset.id = id
        asset.createdAt = ctx.now
        asset.name += " (conflict)"
        var next = db
        next.assets.append(asset)
        return (next, id)
    default:
        return (db, nil)
    }
}

private func finishConflict(_ db: Database, _ conflict: ConflictRecord, _ resolution: ConflictResolution, _ materializedId: String?, _ ctx: ReduceContext) -> Database {
    var nextConflict = conflict
    nextConflict.resolution = resolution
    nextConflict.resolvedAt = ctx.now
    nextConflict.materializedId = materializedId
    var next = db
    next.conflicts = db.conflicts.map { $0.id == conflict.id ? nextConflict : $0 }
    return next
}

public func dispatch(_ db: Database, _ action: Action, _ ctx: ReduceContext) -> CoreResult<Database> {
    switch action {
    case .setLocale(let locale):
        return db.locale == locale ? ok(db) : ok(updated(db) { $0.locale = locale })
    case .setActorName(let raw):
        let name = cleanName(raw)
        if let failed: CoreResult<Database> = failure(name) { return failed }
        return ok(updated(db) { $0.actor.name = name.value! })
    case .createSpace(let raw):
        let name = cleanName(raw)
        if let failed: CoreResult<Database> = failure(name) { return failed }
        let space = Space(id: ctx.newId(), name: name.value!, createdAt: ctx.now, updatedAt: ctx.now)
        return ok(commit(updated(db) { $0.spaces.append(space) }, space.id, "createSpace", ["name": space.name], ctx))
    case .loadDemo:
        return applyDemo(db, ctx)
    case .importBackup(let value):
        let backup = sanitizeBackup(value)
        if let failed: CoreResult<Database> = failure(backup) { return failed }
        return ok(backup.value!.database)
    case .importSync(let value):
        let bundle = sanitizeSyncBundle(value)
        if let failed: CoreResult<Database> = failure(bundle) { return failed }
        let parsed = bundle.value!
        let spaceId = parsed.snapshot.space.id
        let existed = db.spaces.contains { $0.id == spaceId }
        let merged = mergeSyncBundle(db, parsed, ctx)
        if let failed: CoreResult<Database> = failure(merged) { return failed }
        if existed && canonical(takeSnapshot(db, spaceId)) == canonical(takeSnapshot(merged.value!, spaceId)) {
            return ok(db)
        }
        return ok(commit(merged.value!, spaceId, "importSync", ["name": parsed.snapshot.space.name], ctx))
    case .undo(let spaceId):
        guard let history = db.histories.first(where: { $0.spaceId == spaceId }), history.cursor >= 0 else { return err(.NOTHING_TO_UNDO) }
        let cursor = history.cursor - 1
        if cursor < 0 { return ok(setCursor(stripSpace(db, spaceId), spaceId, -1)) }
        guard let revision = db.revisions.first(where: { $0.id == history.revisionIds[cursor] }) else { return err(.NOT_FOUND, ["entity": "revision"]) }
        return ok(setCursor(replaceSpace(db, revision.snapshot), spaceId, cursor))
    case .redo(let spaceId):
        guard let history = db.histories.first(where: { $0.spaceId == spaceId }), history.cursor < history.revisionIds.count - 1 else { return err(.NOTHING_TO_REDO) }
        let cursor = history.cursor + 1
        guard let revision = db.revisions.first(where: { $0.id == history.revisionIds[cursor] }) else { return err(.NOT_FOUND, ["entity": "revision"]) }
        return ok(setCursor(replaceSpace(db, revision.snapshot), spaceId, cursor))
    case .restoreRevision(let spaceId, let revisionId):
        guard let history = db.histories.first(where: { $0.spaceId == spaceId }), let cursor = history.revisionIds.firstIndex(of: revisionId),
              let revision = db.revisions.first(where: { $0.id == revisionId }) else { return err(.NOT_FOUND, ["entity": "revision"]) }
        return ok(setCursor(replaceSpace(db, revision.snapshot), spaceId, cursor))
    default:
        break
    }

    let spaceId = actionSpaceId(action)!
    let space = requireSpace(db, spaceId)
    if let failed: CoreResult<Database> = failure(space) { return failed }

    switch action {
    case .renameSpace(_, let raw):
        let name = cleanName(raw)
        if let failed: CoreResult<Database> = failure(name) { return failed }
        var next = db
        next.spaces = db.spaces.map { item in
            guard item.id == spaceId else { return item }
            var copy = item
            copy.name = name.value!
            copy.updatedAt = ctx.now
            return copy
        }
        return ok(commit(next, spaceId, "renameSpace", ["name": name.value!], ctx))
    case .createPerson(_, let raw, let email, let notes, let status):
        let name = cleanName(raw)
        if let failed: CoreResult<Database> = failure(name) { return failed }
        let person = Person(id: ctx.newId(), spaceId: spaceId, name: name.value!, email: email.trimmingCharacters(in: .whitespacesAndNewlines), notes: notes.trimmingCharacters(in: .whitespacesAndNewlines), status: status, createdAt: ctx.now, updatedAt: ctx.now)
        return ok(commit(updated(db) { $0.people.append(person) }, spaceId, "createPerson", ["name": person.name], ctx))
    case .updatePerson(_, let personId, let raw, let email, let notes, let status):
        let name = cleanName(raw)
        if let failed: CoreResult<Database> = failure(name) { return failed }
        guard var person = db.people.first(where: { $0.id == personId && $0.spaceId == spaceId }) else { return err(.NOT_FOUND, ["entity": "person"]) }
        person.name = name.value!
        person.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        person.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        person.status = status
        person.updatedAt = ctx.now
        var next = db
        next.people = db.people.map { $0.id == person.id ? person : $0 }
        return ok(commit(next, spaceId, "updatePerson", ["name": person.name], ctx))
    case .deletePerson(_, let personId):
        guard let person = db.people.first(where: { $0.id == personId && $0.spaceId == spaceId }) else { return err(.NOT_FOUND, ["entity": "person"]) }
        if db.memberships.contains(where: { $0.personId == person.id }) { return err(.IN_USE, ["entity": "person", "reason": "memberships"]) }
        if db.events.contains(where: { $0.participantIds.contains(person.id) }) { return err(.IN_USE, ["entity": "person", "reason": "events"]) }
        if db.attendance.contains(where: { $0.personId == person.id }) { return err(.IN_USE, ["entity": "person", "reason": "attendance"]) }
        if db.volunteering.contains(where: { $0.personId == person.id }) { return err(.IN_USE, ["entity": "person", "reason": "volunteering"]) }
        var next = db
        next.people.removeAll { $0.id == person.id }
        return ok(commit(tombstone(next, .person, person, person.spaceId, person.id, person.id, ctx), spaceId, "deletePerson", ["name": person.name], ctx))
    case .createGroup(_, let raw, let description):
        let name = cleanName(raw)
        if let failed: CoreResult<Database> = failure(name) { return failed }
        let group = Group(id: ctx.newId(), spaceId: spaceId, name: name.value!, description: description.trimmingCharacters(in: .whitespacesAndNewlines), createdAt: ctx.now, updatedAt: ctx.now)
        return ok(commit(updated(db) { $0.groups.append(group) }, spaceId, "createGroup", ["name": group.name], ctx))
    case .updateGroup(_, let groupId, let raw, let description):
        let name = cleanName(raw)
        if let failed: CoreResult<Database> = failure(name) { return failed }
        guard var group = db.groups.first(where: { $0.id == groupId && $0.spaceId == spaceId }) else { return err(.NOT_FOUND, ["entity": "group"]) }
        group.name = name.value!
        group.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        group.updatedAt = ctx.now
        var next = db
        next.groups = db.groups.map { $0.id == group.id ? group : $0 }
        return ok(commit(next, spaceId, "updateGroup", ["name": group.name], ctx))
    case .deleteGroup(_, let groupId):
        guard let group = db.groups.first(where: { $0.id == groupId && $0.spaceId == spaceId }) else { return err(.NOT_FOUND, ["entity": "group"]) }
        if db.memberships.contains(where: { $0.groupId == group.id }) { return err(.IN_USE, ["entity": "group", "reason": "memberships"]) }
        var next = db
        next.groups.removeAll { $0.id == group.id }
        return ok(commit(tombstone(next, .group, group, group.spaceId, group.id, group.id, ctx), spaceId, "deleteGroup", ["name": group.name], ctx))
    case .addMembership(_, let groupId, let personId, let start, let end):
        let range = cleanRange(start, end)
        if let failed: CoreResult<Database> = failure(range) { return failed }
        guard let group = db.groups.first(where: { $0.id == groupId && $0.spaceId == spaceId }) else { return err(.NOT_FOUND, ["entity": "group"]) }
        guard let person = db.people.first(where: { $0.id == personId && $0.spaceId == spaceId }) else { return err(.NOT_FOUND, ["entity": "person"]) }
        if findMembershipOverlap(db.memberships, groupId: group.id, personId: person.id, startDate: range.value!.start, endDate: range.value!.end) != nil {
            return err(.OVERLAPPING_MEMBERSHIP)
        }
        let membership = GroupMembership(id: ctx.newId(), spaceId: spaceId, groupId: group.id, personId: person.id, startDate: range.value!.start, endDate: range.value!.end, createdAt: ctx.now, updatedAt: ctx.now)
        return ok(commit(updated(db) { $0.memberships.append(membership) }, spaceId, "addMembership", ["name": person.name, "group": group.name], ctx))
    case .updateMembership(_, let membershipId, let start, let end):
        let range = cleanRange(start, end)
        if let failed: CoreResult<Database> = failure(range) { return failed }
        guard var membership = db.memberships.first(where: { $0.id == membershipId && $0.spaceId == spaceId }) else { return err(.NOT_FOUND, ["entity": "membership"]) }
        if findMembershipOverlap(db.memberships, groupId: membership.groupId, personId: membership.personId, startDate: range.value!.start, endDate: range.value!.end, ignoreId: membership.id) != nil {
            return err(.OVERLAPPING_MEMBERSHIP)
        }
        membership.startDate = range.value!.start
        membership.endDate = range.value!.end
        membership.updatedAt = ctx.now
        var next = db
        next.memberships = db.memberships.map { $0.id == membership.id ? membership : $0 }
        let personName = db.people.first { $0.id == membership.personId }?.name ?? ""
        return ok(commit(next, spaceId, "updateMembership", ["name": personName], ctx))
    case .deleteMembership(_, let membershipId):
        guard let membership = db.memberships.first(where: { $0.id == membershipId && $0.spaceId == spaceId }) else { return err(.NOT_FOUND, ["entity": "membership"]) }
        var next = db
        next.memberships.removeAll { $0.id == membership.id }
        return ok(commit(tombstone(next, .membership, membership, membership.spaceId, membership.id, membership.id, ctx), spaceId, "deleteMembership", [:], ctx))
    case .createPeriod(_, let raw, let start, let end):
        let name = cleanName(raw)
        if let failed: CoreResult<Database> = failure(name) { return failed }
        let range = cleanRange(start, end)
        if let failed: CoreResult<Database> = failure(range) { return failed }
        let period = Period(id: ctx.newId(), spaceId: spaceId, name: name.value!, startDate: range.value!.start, endDate: range.value!.end!, createdAt: ctx.now, updatedAt: ctx.now)
        return ok(commit(updated(db) { $0.periods.append(period) }, spaceId, "createPeriod", ["name": period.name], ctx))
    case .updatePeriod(_, let periodId, let raw, let start, let end):
        let name = cleanName(raw)
        if let failed: CoreResult<Database> = failure(name) { return failed }
        let range = cleanRange(start, end)
        if let failed: CoreResult<Database> = failure(range) { return failed }
        guard var period = db.periods.first(where: { $0.id == periodId && $0.spaceId == spaceId }) else { return err(.NOT_FOUND, ["entity": "period"]) }
        period.name = name.value!
        period.startDate = range.value!.start
        period.endDate = range.value!.end!
        period.updatedAt = ctx.now
        var next = db
        next.periods = db.periods.map { $0.id == period.id ? period : $0 }
        return ok(commit(next, spaceId, "updatePeriod", ["name": period.name], ctx))
    case .deletePeriod(_, let periodId):
        guard let period = db.periods.first(where: { $0.id == periodId && $0.spaceId == spaceId }) else { return err(.NOT_FOUND, ["entity": "period"]) }
        var next = db
        next.periods.removeAll { $0.id == period.id }
        return ok(commit(tombstone(next, .period, period, period.spaceId, period.id, period.id, ctx), spaceId, "deletePeriod", ["name": period.name], ctx))
    case .createComponent(_, let raw, let description):
        let name = cleanName(raw)
        if let failed: CoreResult<Database> = failure(name) { return failed }
        let component = ActivityComponent(id: ctx.newId(), spaceId: spaceId, name: name.value!, description: description.trimmingCharacters(in: .whitespacesAndNewlines), createdAt: ctx.now, updatedAt: ctx.now)
        return ok(commit(updated(db) { $0.components.append(component) }, spaceId, "createComponent", ["name": component.name], ctx))
    case .updateComponent(_, let componentId, let raw, let description):
        let name = cleanName(raw)
        if let failed: CoreResult<Database> = failure(name) { return failed }
        guard var component = db.components.first(where: { $0.id == componentId && $0.spaceId == spaceId }) else { return err(.NOT_FOUND, ["entity": "component"]) }
        component.name = name.value!
        component.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        component.updatedAt = ctx.now
        var next = db
        next.components = db.components.map { $0.id == component.id ? component : $0 }
        return ok(commit(next, spaceId, "updateComponent", ["name": component.name], ctx))
    case .deleteComponent(_, let componentId):
        guard let component = db.components.first(where: { $0.id == componentId && $0.spaceId == spaceId }) else { return err(.NOT_FOUND, ["entity": "component"]) }
        if db.categories.contains(where: { $0.componentId == component.id }) { return err(.IN_USE, ["entity": "component", "reason": "categories"]) }
        if db.events.contains(where: { $0.componentId == component.id }) { return err(.IN_USE, ["entity": "component", "reason": "events"]) }
        var next = db
        next.components.removeAll { $0.id == component.id }
        return ok(commit(tombstone(next, .component, component, component.spaceId, component.id, component.id, ctx), spaceId, "deleteComponent", ["name": component.name], ctx))
    case .createCategory(_, let componentId, let raw, let description):
        let name = cleanName(raw)
        if let failed: CoreResult<Database> = failure(name) { return failed }
        let linked = categoryOk(db, spaceId, componentId, nil)
        if let failed: CoreResult<Database> = failure(linked) { return failed }
        let category = Category(id: ctx.newId(), spaceId: spaceId, componentId: componentId, name: name.value!, description: description.trimmingCharacters(in: .whitespacesAndNewlines), createdAt: ctx.now, updatedAt: ctx.now)
        return ok(commit(updated(db) { $0.categories.append(category) }, spaceId, "createCategory", ["name": category.name], ctx))
    case .updateCategory(_, let categoryId, let raw, let description):
        let name = cleanName(raw)
        if let failed: CoreResult<Database> = failure(name) { return failed }
        guard var category = db.categories.first(where: { $0.id == categoryId && $0.spaceId == spaceId }) else { return err(.NOT_FOUND, ["entity": "category"]) }
        category.name = name.value!
        category.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        category.updatedAt = ctx.now
        var next = db
        next.categories = db.categories.map { $0.id == category.id ? category : $0 }
        return ok(commit(next, spaceId, "updateCategory", ["name": category.name], ctx))
    case .deleteCategory(_, let categoryId):
        guard let category = db.categories.first(where: { $0.id == categoryId && $0.spaceId == spaceId }) else { return err(.NOT_FOUND, ["entity": "category"]) }
        if db.events.contains(where: { $0.categoryId == category.id }) { return err(.IN_USE, ["entity": "category", "reason": "events"]) }
        var next = db
        next.categories.removeAll { $0.id == category.id }
        return ok(commit(tombstone(next, .category, category, category.spaceId, category.id, category.id, ctx), spaceId, "deleteCategory", ["name": category.name], ctx))
    case .createEvent(_, let raw, let description, let dateRaw, let componentId, let categoryId, let capacityRaw, let volunteerRaw, let counts, let participantIds):
        let title = cleanName(raw)
        if let failed: CoreResult<Database> = failure(title) { return failed }
        let date = cleanDate(dateRaw)
        if let failed: CoreResult<Database> = failure(date) { return failed }
        let capacity = cleanCapacity(capacityRaw)
        if let failed: CoreResult<Database> = failure(capacity) { return failed }
        let volunteerCapacity = cleanCapacity(volunteerRaw)
        if let failed: CoreResult<Database> = failure(volunteerCapacity) { return failed }
        let linked = categoryOk(db, spaceId, componentId, categoryId)
        if let failed: CoreResult<Database> = failure(linked) { return failed }
        let participants = participantsOk(db, spaceId, participantIds, capacity.value!)
        if let failed: CoreResult<Database> = failure(participants) { return failed }
        let event = AdeEvent(id: ctx.newId(), spaceId: spaceId, title: title.value!, description: description.trimmingCharacters(in: .whitespacesAndNewlines), date: date.value!, componentId: componentId, categoryId: categoryId, participantIds: participants.value!, capacity: capacity.value!, countsForAttendance: counts, status: .draft, volunteerCapacity: volunteerCapacity.value!, duplicatedFromId: nil, createdAt: ctx.now, updatedAt: ctx.now)
        return ok(commit(updated(db) { $0.events.append(event) }, spaceId, "createEvent", ["name": event.title], ctx))
    case .updateEvent(_, let eventId, let raw, let description, let dateRaw, let componentId, let categoryId, let capacityRaw, let volunteerRaw, let counts):
        let title = cleanName(raw)
        if let failed: CoreResult<Database> = failure(title) { return failed }
        let date = cleanDate(dateRaw)
        if let failed: CoreResult<Database> = failure(date) { return failed }
        let capacity = cleanCapacity(capacityRaw)
        if let failed: CoreResult<Database> = failure(capacity) { return failed }
        let volunteerCapacity = cleanCapacity(volunteerRaw)
        if let failed: CoreResult<Database> = failure(volunteerCapacity) { return failed }
        guard var event = db.events.first(where: { $0.id == eventId && $0.spaceId == spaceId }) else { return err(.NOT_FOUND, ["entity": "event"]) }
        let linked = categoryOk(db, spaceId, componentId, categoryId)
        if let failed: CoreResult<Database> = failure(linked) { return failed }
        if let limit = capacity.value ?? nil, event.participantIds.count > limit {
            return err(.CAPACITY_EXCEEDED, ["capacity": String(limit), "used": String(event.participantIds.count)])
        }
        let used = consumingVolunteerCount(db, eventId: event.id)
        if let limit = volunteerCapacity.value ?? nil, used > limit {
            return err(.CAPACITY_EXCEEDED, ["capacity": String(limit), "used": String(used)])
        }
        event.title = title.value!
        event.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        event.date = date.value!
        event.componentId = componentId
        event.categoryId = categoryId
        event.capacity = capacity.value!
        event.volunteerCapacity = volunteerCapacity.value!
        event.countsForAttendance = counts
        event.updatedAt = ctx.now
        var next = db
        next.events = db.events.map { $0.id == event.id ? event : $0 }
        return ok(commit(next, spaceId, "updateEvent", ["name": event.title], ctx))
    case .setEventStatus(_, let eventId, let status):
        guard var event = db.events.first(where: { $0.id == eventId && $0.spaceId == spaceId }) else { return err(.NOT_FOUND, ["entity": "event"]) }
        if event.status == status { return ok(db) }
        if !(eventTransitions[event.status] ?? []).contains(status) {
            return err(.INVALID_TRANSITION, ["from": event.status.rawValue, "to": status.rawValue])
        }
        event.status = status
        event.updatedAt = ctx.now
        var next = db
        next.events = db.events.map { $0.id == event.id ? event : $0 }
        return ok(commit(next, spaceId, "setEventStatus", ["name": event.title, "status": event.status.rawValue], ctx))
    case .setEventParticipants(_, let eventId, let participantIds):
        guard var event = db.events.first(where: { $0.id == eventId && $0.spaceId == spaceId }) else { return err(.NOT_FOUND, ["entity": "event"]) }
        if event.status == .cancelled { return err(.EVENT_LOCKED) }
        let participants = participantsOk(db, spaceId, participantIds, event.capacity)
        if let failed: CoreResult<Database> = failure(participants) { return failed }
        event.participantIds = participants.value!
        event.updatedAt = ctx.now
        var next = db
        next.events = db.events.map { $0.id == event.id ? event : $0 }
        return ok(commit(next, spaceId, "setEventParticipants", ["name": event.title, "count": String(event.participantIds.count)], ctx))
    case .duplicateEvent(_, let eventId, let titleSuffix):
        guard var event = db.events.first(where: { $0.id == eventId && $0.spaceId == spaceId }) else { return err(.NOT_FOUND, ["entity": "event"]) }
        let sourceId = event.id
        event.id = ctx.newId()
        event.title += titleSuffix
        event.status = .draft
        event.duplicatedFromId = sourceId
        event.createdAt = ctx.now
        event.updatedAt = ctx.now
        return ok(commit(updated(db) { $0.events.append(event) }, spaceId, "duplicateEvent", ["name": event.title], ctx))
    case .deleteEvent(_, let eventId):
        guard let event = db.events.first(where: { $0.id == eventId && $0.spaceId == spaceId }) else { return err(.NOT_FOUND, ["entity": "event"]) }
        if event.status != .draft { return err(.IN_USE, ["entity": "event", "reason": "status"]) }
        if db.attendance.contains(where: { $0.eventId == event.id }) { return err(.IN_USE, ["entity": "event", "reason": "attendance"]) }
        if db.volunteering.contains(where: { $0.eventId == event.id }) { return err(.IN_USE, ["entity": "event", "reason": "volunteering"]) }
        var next = db
        next.events.removeAll { $0.id == event.id }
        return ok(commit(tombstone(next, .event, event, event.spaceId, event.id, event.id, ctx), spaceId, "deleteEvent", ["name": event.title], ctx))
    case .setAttendance(_, let eventId, let personId, let state, let noteRaw):
        guard let event = db.events.first(where: { $0.id == eventId && $0.spaceId == spaceId }) else { return err(.NOT_FOUND, ["entity": "event"]) }
        if event.status != .scheduled && event.status != .completed { return err(.ATTENDANCE_NOT_ALLOWED) }
        guard let person = db.people.first(where: { $0.id == personId && $0.spaceId == spaceId }) else { return err(.NOT_FOUND, ["entity": "person"]) }
        if !event.participantIds.contains(person.id) { return err(.PERSON_NOT_PARTICIPANT) }
        let note = noteRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let current = db.attendance.first(where: { $0.eventId == event.id && $0.personId == person.id }), current.state == state, current.note == note {
            return ok(db)
        }
        let record: AttendanceRecord
        if var current = db.attendance.first(where: { $0.eventId == event.id && $0.personId == person.id }) {
            let entry = AttendanceHistoryEntry(at: ctx.now, actorId: ctx.actorId, previousState: current.state, nextState: state, previousNote: current.note, nextNote: note)
            current.state = state
            current.note = note
            current.updatedAt = ctx.now
            current.history.append(entry)
            record = current
        } else {
            record = AttendanceRecord(id: ctx.newId(), spaceId: spaceId, eventId: event.id, personId: person.id, state: state, note: note, history: [AttendanceHistoryEntry(at: ctx.now, actorId: ctx.actorId, previousState: nil, nextState: state, previousNote: "", nextNote: note)], createdAt: ctx.now, updatedAt: ctx.now)
        }
        var next = db
        if db.attendance.contains(where: { $0.id == record.id }) {
            next.attendance = db.attendance.map { $0.id == record.id ? record : $0 }
        } else {
            next.attendance.append(record)
        }
        return ok(commit(next, spaceId, "setAttendance", ["name": person.name, "state": state.rawValue], ctx))
    case .setVolunteerState(_, let eventId, let personId, let state, let noteRaw):
        guard let event = db.events.first(where: { $0.id == eventId && $0.spaceId == spaceId }) else { return err(.NOT_FOUND, ["entity": "event"]) }
        if event.status == .cancelled { return err(.VOLUNTEER_NOT_ALLOWED) }
        guard let person = db.people.first(where: { $0.id == personId && $0.spaceId == spaceId }) else { return err(.NOT_FOUND, ["entity": "person"]) }
        let current = db.volunteering.first { $0.eventId == event.id && $0.personId == person.id }
        let from = current?.state
        if !canTransitionVolunteer(from: from, to: state) {
            return err(.INVALID_TRANSITION, ["from": from?.rawValue ?? "none", "to": state.rawValue])
        }
        let entering = consumesVolunteerCapacity(state) && (from == nil || !consumesVolunteerCapacity(from!))
        if entering, let limit = event.volunteerCapacity {
            let used = consumingVolunteerCount(db, eventId: event.id, ignorePersonId: person.id)
            if used + 1 > limit {
                return err(.CAPACITY_EXCEEDED, ["capacity": String(limit), "used": String(used)])
            }
        }
        let note = noteRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let current, current.state == state, current.note == note { return ok(db) }
        let record: VolunteerRecord
        if var current {
            let entry = VolunteerHistoryEntry(at: ctx.now, actorId: ctx.actorId, previousState: current.state, nextState: state, previousNote: current.note, nextNote: note)
            current.state = state
            current.note = note
            current.updatedAt = ctx.now
            current.history.append(entry)
            record = current
        } else {
            record = VolunteerRecord(id: ctx.newId(), spaceId: spaceId, eventId: event.id, personId: person.id, state: state, note: note, history: [VolunteerHistoryEntry(at: ctx.now, actorId: ctx.actorId, previousState: nil, nextState: state, previousNote: "", nextNote: note)], createdAt: ctx.now, updatedAt: ctx.now)
        }
        var next = db
        if db.volunteering.contains(where: { $0.id == record.id }) {
            next.volunteering = db.volunteering.map { $0.id == record.id ? record : $0 }
        } else {
            next.volunteering.append(record)
        }
        return ok(commit(next, spaceId, "setVolunteerState", ["name": person.name, "state": state.rawValue], ctx))
    case .createTemplate(_, let raw, let description, let pageSize, let background, let drafts):
        let name = cleanName(raw)
        if let failed: CoreResult<Database> = failure(name) { return failed }
        let elements = withIds(drafts, ctx)
        let valid = validateElements(db, spaceId, elements, background)
        if let failed: CoreResult<Database> = failure(valid) { return failed }
        let template = DocumentTemplate(id: ctx.newId(), spaceId: spaceId, name: name.value!, description: description.trimmingCharacters(in: .whitespacesAndNewlines), pageSize: pageSize, backgroundAssetId: background, elements: elements, createdAt: ctx.now, updatedAt: ctx.now)
        return ok(commit(updated(db) { $0.templates.append(template) }, spaceId, "createTemplate", ["name": template.name], ctx))
    case .updateTemplate(_, let templateId, let raw, let description, let pageSize, let background, let drafts):
        let name = cleanName(raw)
        if let failed: CoreResult<Database> = failure(name) { return failed }
        guard var template = db.templates.first(where: { $0.id == templateId && $0.spaceId == spaceId }) else { return err(.NOT_FOUND, ["entity": "template"]) }
        let elements = withIds(drafts, ctx)
        let valid = validateElements(db, spaceId, elements, background)
        if let failed: CoreResult<Database> = failure(valid) { return failed }
        template.name = name.value!
        template.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        template.pageSize = pageSize
        template.backgroundAssetId = background
        template.elements = elements
        template.updatedAt = ctx.now
        var next = db
        next.templates = db.templates.map { $0.id == template.id ? template : $0 }
        return ok(commit(next, spaceId, "updateTemplate", ["name": template.name], ctx))
    case .deleteTemplate(_, let templateId):
        guard let template = db.templates.first(where: { $0.id == templateId && $0.spaceId == spaceId }) else { return err(.NOT_FOUND, ["entity": "template"]) }
        var next = db
        next.templates.removeAll { $0.id == template.id }
        return ok(commit(tombstone(next, .template, template, template.spaceId, template.id, template.id, ctx), spaceId, "deleteTemplate", ["name": template.name], ctx))
    case .addAsset(_, let raw, let mime, let data):
        let name = cleanName(raw)
        if let failed: CoreResult<Database> = failure(name) { return failed }
        if data.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return err(.INVALID_TEMPLATE) }
        let asset = Asset(id: ctx.newId(), spaceId: spaceId, name: name.value!, mime: mime, dataBase64: data.trimmingCharacters(in: .whitespacesAndNewlines), createdAt: ctx.now, deletedAt: nil)
        return ok(commit(updated(db) { $0.assets.append(asset) }, spaceId, "addAsset", ["name": asset.name], ctx))
    case .deleteAsset(_, let assetId):
        guard let asset = db.assets.first(where: { $0.id == assetId && $0.spaceId == spaceId }), asset.deletedAt == nil else { return err(.NOT_FOUND, ["entity": "asset"]) }
        let used = db.templates.contains { template in
            template.spaceId == spaceId && (template.backgroundAssetId == asset.id || template.elements.contains { element in
                if case .image(let image) = element { return image.assetId == asset.id }
                return false
            })
        }
        if used { return err(.ASSET_IN_USE) }
        var next = db
        next.assets = db.assets.map { item in
            guard item.id == asset.id else { return item }
            var copy = item
            copy.deletedAt = ctx.now
            return copy
        }
        return ok(commit(next, spaceId, "deleteAsset", ["name": asset.name], ctx))
    case .resolveConflict(_, let conflictId, let resolution):
        guard resolution != .pending, var conflict = db.conflicts.first(where: { $0.id == conflictId && $0.spaceId == spaceId }), conflict.resolution == .pending else {
            return err(.NOT_FOUND, ["entity": "conflict"])
        }
        if resolution == .keptLocal {
            return ok(commit(finishConflict(db, conflict, .keptLocal, nil, ctx), spaceId, "resolveConflict", ["resolution": resolution.rawValue], ctx))
        }
        if resolution == .keptRemote {
            let applied = applyRemote(db, conflict, ctx)
            if let failed: CoreResult<Database> = failure(applied) { return failed }
            return ok(commit(finishConflict(applied.value!, conflict, .keptRemote, nil, ctx), spaceId, "resolveConflict", ["resolution": resolution.rawValue], ctx))
        }
        let copy = materialize(db, conflict, ctx)
        return ok(commit(finishConflict(copy.db, conflict, .keptBoth, copy.materializedId, ctx), spaceId, "resolveConflict", ["resolution": resolution.rawValue], ctx))
    default:
        return err(.NOT_FOUND)
    }
}

private func updated(_ db: Database, _ change: (inout Database) -> Void) -> Database {
    var copy = db
    change(&copy)
    return copy
}

private func actionSpaceId(_ action: Action) -> String? {
    switch action {
    case .renameSpace(let spaceId, _),
         .createPerson(let spaceId, _, _, _, _),
         .updatePerson(let spaceId, _, _, _, _, _),
         .deletePerson(let spaceId, _),
         .createGroup(let spaceId, _, _),
         .updateGroup(let spaceId, _, _, _),
         .deleteGroup(let spaceId, _),
         .addMembership(let spaceId, _, _, _, _),
         .updateMembership(let spaceId, _, _, _),
         .deleteMembership(let spaceId, _),
         .createPeriod(let spaceId, _, _, _),
         .updatePeriod(let spaceId, _, _, _, _),
         .deletePeriod(let spaceId, _),
         .createComponent(let spaceId, _, _),
         .updateComponent(let spaceId, _, _, _),
         .deleteComponent(let spaceId, _),
         .createCategory(let spaceId, _, _, _),
         .updateCategory(let spaceId, _, _, _),
         .deleteCategory(let spaceId, _),
         .createEvent(let spaceId, _, _, _, _, _, _, _, _, _),
         .updateEvent(let spaceId, _, _, _, _, _, _, _, _, _),
         .setEventStatus(let spaceId, _, _),
         .setEventParticipants(let spaceId, _, _),
         .duplicateEvent(let spaceId, _, _),
         .deleteEvent(let spaceId, _),
         .setAttendance(let spaceId, _, _, _, _),
         .setVolunteerState(let spaceId, _, _, _, _),
         .createTemplate(let spaceId, _, _, _, _, _),
         .updateTemplate(let spaceId, _, _, _, _, _, _),
         .deleteTemplate(let spaceId, _),
         .addAsset(let spaceId, _, _, _),
         .deleteAsset(let spaceId, _),
         .resolveConflict(let spaceId, _, _):
        return spaceId
    default:
        return nil
    }
}

private func applyDemo(_ db: Database, _ ctx: ReduceContext) -> CoreResult<Database> {
    var current = db
    func must(_ result: CoreResult<Database>) {
        switch result {
        case .ok(let value): current = value
        case .err(let error): fatalError(error.code.rawValue)
        }
    }
    let before = Set(current.spaces.map(\.id))
    must(dispatch(current, .createSpace(name: "Demo"), ctx))
    let spaceId = current.spaces.first { !before.contains($0.id) }!.id
    func addPerson(_ name: String) -> Person {
        must(dispatch(current, .createPerson(spaceId: spaceId, name: name, email: "", notes: "", status: .active), ctx))
        return current.people.first { $0.spaceId == spaceId && $0.name == name }!
    }
    let ada = addPerson("Ada")
    let ben = addPerson("Ben")
    let cia = addPerson("Cia")
    let dio = addPerson("Dio")
    must(dispatch(current, .updatePerson(spaceId: spaceId, personId: dio.id, name: "Dio", email: "", notes: "", status: .inactive), ctx))
    must(dispatch(current, .createGroup(spaceId: spaceId, name: "Team", description: ""), ctx))
    let groupId = current.groups.first { $0.spaceId == spaceId && $0.name == "Team" }!.id
    must(dispatch(current, .addMembership(spaceId: spaceId, groupId: groupId, personId: ada.id, startDate: "2026-01-01", endDate: nil), ctx))
    must(dispatch(current, .addMembership(spaceId: spaceId, groupId: groupId, personId: ben.id, startDate: "2026-01-01", endDate: "2026-03-31"), ctx))
    must(dispatch(current, .addMembership(spaceId: spaceId, groupId: groupId, personId: cia.id, startDate: "2026-04-01", endDate: nil), ctx))
    must(dispatch(current, .createPeriod(spaceId: spaceId, name: "Spring", startDate: "2026-01-01", endDate: "2026-06-30"), ctx))
    must(dispatch(current, .createComponent(spaceId: spaceId, name: "Service", description: ""), ctx))
    let componentId = current.components.first { $0.spaceId == spaceId && $0.name == "Service" }!.id
    must(dispatch(current, .createCategory(spaceId: spaceId, componentId: componentId, name: "Kitchen", description: ""), ctx))
    let categoryId = current.categories.first { $0.spaceId == spaceId && $0.name == "Kitchen" }!.id
    func addEvent(_ title: String, _ date: String, _ participantIds: [String], _ volunteerCapacity: Int? = nil) -> AdeEvent {
        must(dispatch(current, .createEvent(spaceId: spaceId, title: title, description: "", date: date, componentId: componentId, categoryId: categoryId, capacity: nil, volunteerCapacity: volunteerCapacity, countsForAttendance: true, participantIds: participantIds), ctx))
        return current.events.first { $0.spaceId == spaceId && $0.title == title }!
    }
    let feb = addEvent("February service", "2026-02-01", [ada.id, ben.id, cia.id])
    let mar = addEvent("March service", "2026-03-01", [ada.id, ben.id])
    let apr = addEvent("April service", "2026-04-01", [ada.id, ben.id])
    let may = addEvent("May social", "2026-05-01", [ada.id])
    let jun = addEvent("June service", "2026-06-01", [ada.id, cia.id], 2)
    for event in [feb, mar, apr, may, jun] {
        must(dispatch(current, .setEventStatus(spaceId: spaceId, eventId: event.id, status: .scheduled), ctx))
    }
    must(dispatch(current, .setEventStatus(spaceId: spaceId, eventId: jun.id, status: .completed), ctx))
    let mayEvent = current.events.first { $0.id == may.id }!
    must(dispatch(current, .updateEvent(spaceId: spaceId, eventId: may.id, title: mayEvent.title, description: mayEvent.description, date: mayEvent.date, componentId: mayEvent.componentId, categoryId: mayEvent.categoryId, capacity: mayEvent.capacity, volunteerCapacity: mayEvent.volunteerCapacity, countsForAttendance: false), ctx))
    func mark(_ eventId: String, _ personId: String, _ state: AttendanceState) {
        must(dispatch(current, .setAttendance(spaceId: spaceId, eventId: eventId, personId: personId, state: state, note: ""), ctx))
    }
    mark(feb.id, ada.id, .present)
    mark(feb.id, ben.id, .absent)
    mark(feb.id, cia.id, .excused)
    mark(mar.id, ada.id, .present)
    mark(mar.id, ben.id, .pending)
    mark(apr.id, ada.id, .absent)
    mark(may.id, ada.id, .absent)
    mark(jun.id, ada.id, .present)
    mark(jun.id, cia.id, .present)
    must(dispatch(current, .setEventStatus(spaceId: spaceId, eventId: apr.id, status: .cancelled), ctx))
    func volunteer(_ personId: String, _ state: VolunteerState) {
        must(dispatch(current, .setVolunteerState(spaceId: spaceId, eventId: feb.id, personId: personId, state: state, note: ""), ctx))
    }
    volunteer(ada.id, .interested)
    volunteer(ada.id, .selected)
    volunteer(ada.id, .completed)
    volunteer(ben.id, .interested)
    volunteer(ben.id, .declined)
    return ok(current)
}

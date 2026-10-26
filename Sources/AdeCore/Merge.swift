import Foundation

private func entityId(_ value: JSONValue) -> String? {
    guard case .object(let fields) = value, case .string(let id) = fields["id"] ?? .null else { return nil }
    return id
}

private func samePending(_ existing: [ConflictRecord], _ entityType: EntityType, _ key: String, _ local: JSONValue, _ remote: JSONValue, _ remoteDeleted: Bool) -> Bool {
    existing.contains { conflict in
        conflict.resolution == .pending && conflict.entityType == entityType && conflict.key == key && conflict.remoteDeleted == remoteDeleted
            && canonical(conflict.local) == canonical(local) && canonical(conflict.remote) == canonical(remote)
    }
}

private func makeConflict(_ ctx: ReduceContext, _ spaceId: String, _ entityType: EntityType, _ key: String, _ local: JSONValue, _ remote: JSONValue, _ remoteDeleted: Bool) -> ConflictRecord {
    ConflictRecord(
        id: ctx.newId(), spaceId: spaceId, entityType: entityType, key: key,
        localEntityId: entityId(local), remoteEntityId: entityId(remote),
        local: local, remote: remote, remoteDeleted: remoteDeleted, createdAt: ctx.now,
        resolvedAt: nil, resolution: .pending, materializedId: nil
    )
}

private func mergeRows<T>(
    entityType: EntityType,
    spaceId: String,
    local: [T],
    remote: [T],
    keyOf: (T) -> String,
    localTombstones: [Tombstone],
    remoteTombstones: [Tombstone],
    canInsert: (T, [T]) -> Bool,
    conflicts: [ConflictRecord],
    ctx: ReduceContext,
    encode: (T) -> JSONValue
) -> (items: [T], tombstones: [Tombstone], conflicts: [ConflictRecord]) {
    var items = local
    var tombstones = localTombstones
    var conflicts = conflicts
    func remember(_ key: String, _ local: JSONValue, _ remote: JSONValue, _ remoteDeleted: Bool) {
        if samePending(conflicts, entityType, key, local, remote, remoteDeleted) { return }
        conflicts.append(makeConflict(ctx, spaceId, entityType, key, local, remote, remoteDeleted))
    }
    for remoteItem in remote {
        let key = keyOf(remoteItem)
        if let localItem = items.first(where: { keyOf($0) == key }) {
            let localJSON = encode(localItem)
            let remoteJSON = encode(remoteItem)
            if canonical(localJSON) != canonical(remoteJSON) {
                remember(key, localJSON, remoteJSON, false)
            }
            continue
        }
        if let deleted = tombstones.first(where: { $0.entityType == entityType && $0.naturalKey == key }) {
            remember(key, deleted.payload, encode(remoteItem), false)
            continue
        }
        if !canInsert(remoteItem, items) {
            remember(key, .null, encode(remoteItem), false)
            continue
        }
        items.append(remoteItem)
    }
    for remoteStone in remoteTombstones where remoteStone.entityType == entityType {
        let known = tombstones.contains { $0.entityType == remoteStone.entityType && $0.naturalKey == remoteStone.naturalKey }
        guard let index = items.firstIndex(where: { keyOf($0) == remoteStone.naturalKey }) else {
            if !known { tombstones.append(remoteStone) }
            continue
        }
        let localItem = items[index]
        if canonical(encode(localItem)) == canonical(remoteStone.payload) {
            items.remove(at: index)
            if !known { tombstones.append(remoteStone) }
            continue
        }
        remember(remoteStone.naturalKey, encode(localItem), remoteStone.payload, true)
    }
    return (items, tombstones, conflicts)
}

private func replaceCollection<T>(_ all: [T], _ spaceId: String, _ next: [T], _ id: (T) -> String) -> [T] {
    all.filter { id($0) != spaceId } + next
}

func mergeSyncBundle(_ db: Database, _ bundle: SyncBundle, _ ctx: ReduceContext) -> CoreResult<Database> {
    let remote = bundle.snapshot
    let spaceId = remote.space.id
    if !db.spaces.contains(where: { $0.id == spaceId }) {
        return ok(replaceSpace(db, remote))
    }
    var conflicts = db.conflicts.filter { $0.spaceId == spaceId }
    let rest = db.conflicts.filter { $0.spaceId != spaceId }
    if let localSpace = db.spaces.first(where: { $0.id == spaceId }), canonical(localSpace) != canonical(remote.space) {
        let localJSON = jsonValue(of: localSpace)
        let remoteJSON = jsonValue(of: remote.space)
        if !samePending(conflicts, .space, spaceId, localJSON, remoteJSON, false) {
            conflicts.append(makeConflict(ctx, spaceId, .space, spaceId, localJSON, remoteJSON, false))
        }
    }
    let people = mergeRows(entityType: .person, spaceId: spaceId, local: db.people.filter { $0.spaceId == spaceId }, remote: remote.people, keyOf: \.id, localTombstones: db.tombstones.filter { $0.spaceId == spaceId }, remoteTombstones: remote.tombstones, canInsert: { _, _ in true }, conflicts: conflicts, ctx: ctx, encode: jsonValue(of:))
    let groups = mergeRows(entityType: .group, spaceId: spaceId, local: db.groups.filter { $0.spaceId == spaceId }, remote: remote.groups, keyOf: \.id, localTombstones: people.tombstones, remoteTombstones: remote.tombstones, canInsert: { _, _ in true }, conflicts: people.conflicts, ctx: ctx, encode: jsonValue(of:))
    let memberships = mergeRows(entityType: .membership, spaceId: spaceId, local: db.memberships.filter { $0.spaceId == spaceId }, remote: remote.memberships, keyOf: \.id, localTombstones: groups.tombstones, remoteTombstones: remote.tombstones, canInsert: { item, current in
        findMembershipOverlap(current, groupId: item.groupId, personId: item.personId, startDate: item.startDate, endDate: item.endDate) == nil
    }, conflicts: groups.conflicts, ctx: ctx, encode: jsonValue(of:))
    let periods = mergeRows(entityType: .period, spaceId: spaceId, local: db.periods.filter { $0.spaceId == spaceId }, remote: remote.periods, keyOf: \.id, localTombstones: memberships.tombstones, remoteTombstones: remote.tombstones, canInsert: { _, _ in true }, conflicts: memberships.conflicts, ctx: ctx, encode: jsonValue(of:))
    let components = mergeRows(entityType: .component, spaceId: spaceId, local: db.components.filter { $0.spaceId == spaceId }, remote: remote.components, keyOf: \.id, localTombstones: periods.tombstones, remoteTombstones: remote.tombstones, canInsert: { _, _ in true }, conflicts: periods.conflicts, ctx: ctx, encode: jsonValue(of:))
    let categories = mergeRows(entityType: .category, spaceId: spaceId, local: db.categories.filter { $0.spaceId == spaceId }, remote: remote.categories, keyOf: \.id, localTombstones: components.tombstones, remoteTombstones: remote.tombstones, canInsert: { _, _ in true }, conflicts: components.conflicts, ctx: ctx, encode: jsonValue(of:))
    let events = mergeRows(entityType: .event, spaceId: spaceId, local: db.events.filter { $0.spaceId == spaceId }, remote: remote.events, keyOf: \.id, localTombstones: categories.tombstones, remoteTombstones: remote.tombstones, canInsert: { _, _ in true }, conflicts: categories.conflicts, ctx: ctx, encode: jsonValue(of:))
    let attendance = mergeRows(entityType: .attendance, spaceId: spaceId, local: db.attendance.filter { $0.spaceId == spaceId }, remote: remote.attendance, keyOf: { "\($0.eventId):\($0.personId)" }, localTombstones: events.tombstones, remoteTombstones: remote.tombstones, canInsert: { item, current in
        !current.contains { $0.eventId == item.eventId && $0.personId == item.personId }
    }, conflicts: events.conflicts, ctx: ctx, encode: jsonValue(of:))
    let volunteering = mergeRows(entityType: .volunteering, spaceId: spaceId, local: db.volunteering.filter { $0.spaceId == spaceId }, remote: remote.volunteering, keyOf: { "\($0.eventId):\($0.personId)" }, localTombstones: attendance.tombstones, remoteTombstones: remote.tombstones, canInsert: { item, current in
        !current.contains { $0.eventId == item.eventId && $0.personId == item.personId }
    }, conflicts: attendance.conflicts, ctx: ctx, encode: jsonValue(of:))
    let templates = mergeRows(entityType: .template, spaceId: spaceId, local: db.templates.filter { $0.spaceId == spaceId }, remote: remote.templates, keyOf: \.id, localTombstones: volunteering.tombstones, remoteTombstones: remote.tombstones, canInsert: { _, _ in true }, conflicts: volunteering.conflicts, ctx: ctx, encode: jsonValue(of:))
    let assets = mergeRows(entityType: .asset, spaceId: spaceId, local: db.assets.filter { $0.spaceId == spaceId }, remote: remote.assets, keyOf: \.id, localTombstones: templates.tombstones, remoteTombstones: remote.tombstones, canInsert: { _, _ in true }, conflicts: templates.conflicts, ctx: ctx, encode: jsonValue(of:))
    var next = db
    next.people = replaceCollection(db.people, spaceId, people.items, \.spaceId)
    next.groups = replaceCollection(db.groups, spaceId, groups.items, \.spaceId)
    next.memberships = replaceCollection(db.memberships, spaceId, memberships.items, \.spaceId)
    next.periods = replaceCollection(db.periods, spaceId, periods.items, \.spaceId)
    next.components = replaceCollection(db.components, spaceId, components.items, \.spaceId)
    next.categories = replaceCollection(db.categories, spaceId, categories.items, \.spaceId)
    next.events = replaceCollection(db.events, spaceId, events.items, \.spaceId)
    next.attendance = replaceCollection(db.attendance, spaceId, attendance.items, \.spaceId)
    next.volunteering = replaceCollection(db.volunteering, spaceId, volunteering.items, \.spaceId)
    next.templates = replaceCollection(db.templates, spaceId, templates.items, \.spaceId)
    next.assets = replaceCollection(db.assets, spaceId, assets.items, \.spaceId)
    next.tombstones = replaceCollection(db.tombstones, spaceId, assets.tombstones, \.spaceId)
    next.conflicts = rest + assets.conflicts
    return ok(next)
}

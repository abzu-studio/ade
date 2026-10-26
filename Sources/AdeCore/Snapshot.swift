import Foundation

func takeSnapshot(_ db: Database, _ spaceId: String) -> SpaceSnapshot {
    let space = db.spaces.first { $0.id == spaceId }!
    func pick<T>(_ list: [T], _ id: (T) -> String) -> [T] { list.filter { id($0) == spaceId } }
    return SpaceSnapshot(
        space: space,
        people: pick(db.people, \.spaceId),
        groups: pick(db.groups, \.spaceId),
        memberships: pick(db.memberships, \.spaceId),
        periods: pick(db.periods, \.spaceId),
        components: pick(db.components, \.spaceId),
        categories: pick(db.categories, \.spaceId),
        events: pick(db.events, \.spaceId),
        attendance: pick(db.attendance, \.spaceId),
        volunteering: pick(db.volunteering, \.spaceId),
        templates: pick(db.templates, \.spaceId),
        assets: pick(db.assets, \.spaceId),
        conflicts: pick(db.conflicts, \.spaceId),
        tombstones: pick(db.tombstones, \.spaceId)
    )
}

func replaceSpace(_ db: Database, _ snapshot: SpaceSnapshot) -> Database {
    let spaceId = snapshot.space.id
    func drop<T>(_ list: [T], _ id: (T) -> String) -> [T] { list.filter { id($0) != spaceId } }
    var next = db
    next.spaces = db.spaces.filter { $0.id != spaceId } + [snapshot.space]
    next.people = drop(db.people, \.spaceId) + snapshot.people
    next.groups = drop(db.groups, \.spaceId) + snapshot.groups
    next.memberships = drop(db.memberships, \.spaceId) + snapshot.memberships
    next.periods = drop(db.periods, \.spaceId) + snapshot.periods
    next.components = drop(db.components, \.spaceId) + snapshot.components
    next.categories = drop(db.categories, \.spaceId) + snapshot.categories
    next.events = drop(db.events, \.spaceId) + snapshot.events
    next.attendance = drop(db.attendance, \.spaceId) + snapshot.attendance
    next.volunteering = drop(db.volunteering, \.spaceId) + snapshot.volunteering
    next.templates = drop(db.templates, \.spaceId) + snapshot.templates
    next.assets = drop(db.assets, \.spaceId) + snapshot.assets
    next.conflicts = drop(db.conflicts, \.spaceId) + snapshot.conflicts
    next.tombstones = drop(db.tombstones, \.spaceId) + snapshot.tombstones
    return next
}

func stripSpace(_ db: Database, _ spaceId: String) -> Database {
    func drop<T>(_ list: [T], _ id: (T) -> String) -> [T] { list.filter { id($0) != spaceId } }
    var next = db
    next.spaces = db.spaces.filter { $0.id != spaceId }
    next.people = drop(db.people, \.spaceId)
    next.groups = drop(db.groups, \.spaceId)
    next.memberships = drop(db.memberships, \.spaceId)
    next.periods = drop(db.periods, \.spaceId)
    next.components = drop(db.components, \.spaceId)
    next.categories = drop(db.categories, \.spaceId)
    next.events = drop(db.events, \.spaceId)
    next.attendance = drop(db.attendance, \.spaceId)
    next.volunteering = drop(db.volunteering, \.spaceId)
    next.templates = drop(db.templates, \.spaceId)
    next.assets = drop(db.assets, \.spaceId)
    next.conflicts = drop(db.conflicts, \.spaceId)
    next.tombstones = drop(db.tombstones, \.spaceId)
    return next
}

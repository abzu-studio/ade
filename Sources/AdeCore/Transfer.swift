import Foundation

public func createEmptyDatabase(actorId: String, now: String, actorName: String = "Local user") -> Database {
    Database(
        format: databaseFormat,
        actor: Actor(id: actorId, name: actorName),
        locale: .en,
        spaces: [], people: [], groups: [], memberships: [], periods: [], components: [], categories: [],
        events: [], attendance: [], volunteering: [], templates: [], assets: [], conflicts: [], tombstones: [],
        revisions: [], histories: []
    )
}

public func toBackup(_ db: Database, exportedAt: String) -> BackupFile {
    BackupFile(format: backupFormat, exportedAt: exportedAt, database: db)
}

public func toSyncBundle(_ db: Database, spaceId: String, exportedAt: String) -> CoreResult<SyncBundle> {
    guard db.spaces.contains(where: { $0.id == spaceId }) else { return err(.NOT_FOUND, ["entity": "space"]) }
    let snapshot = takeSnapshot(db, spaceId)
    return ok(SyncBundle(format: syncFormat, exportedAt: exportedAt, actor: db.actor, snapshot: snapshot, tombstones: snapshot.tombstones))
}

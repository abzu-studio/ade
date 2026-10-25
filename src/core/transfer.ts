import { err, ok, type Result } from "@/core/result";
import { takeSnapshot } from "@/core/snapshot";
import { BACKUP_FORMAT, SYNC_FORMAT, type BackupFile, type Database, type SyncBundle } from "@/core/types";

export function toBackup(db: Database, exportedAt: string): BackupFile {
  return {
    format: BACKUP_FORMAT,
    exportedAt,
    database: structuredClone(db),
  };
}

export function toSyncBundle(
  db: Database,
  spaceId: string,
  exportedAt: string,
): Result<SyncBundle> {
  if (!db.spaces.some((space) => space.id === spaceId)) {
    return err("NOT_FOUND", { entity: "space" });
  }
  const snapshot = takeSnapshot(db, spaceId);
  return ok({
    format: SYNC_FORMAT,
    exportedAt,
    actor: db.actor,
    snapshot,
    tombstones: snapshot.tombstones,
  });
}

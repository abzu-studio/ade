import { canonical } from "@/core/canonical";
import { findMembershipOverlap } from "@/core/groups";
import { ok, type Result } from "@/core/result";
import { replaceSpace } from "@/core/snapshot";
import type {
  ConflictRecord,
  Database,
  EntityType,
  GroupMembership,
  ReduceContext,
  SyncBundle,
  Tombstone,
} from "@/core/types";

interface MergeRow {
  id: string;
  spaceId: string;
}

function entityId(value: unknown): string | null {
  if (!value || typeof value !== "object" || !("id" in value)) return null;
  const id = (value as { id: unknown }).id;
  return typeof id === "string" ? id : null;
}

function samePending(
  existing: ConflictRecord[],
  candidate: {
    entityType: EntityType;
    key: string;
    local: unknown;
    remote: unknown;
    remoteDeleted: boolean;
  },
): boolean {
  return existing.some(
    (conflict) =>
      conflict.resolution === "pending" &&
      conflict.entityType === candidate.entityType &&
      conflict.key === candidate.key &&
      conflict.remoteDeleted === candidate.remoteDeleted &&
      canonical(conflict.local) === canonical(candidate.local) &&
      canonical(conflict.remote) === canonical(candidate.remote),
  );
}

function makeConflict(
  ctx: ReduceContext,
  spaceId: string,
  entityType: EntityType,
  key: string,
  local: unknown | null,
  remote: unknown | null,
  remoteDeleted: boolean,
): ConflictRecord {
  return {
    id: ctx.newId(),
    spaceId,
    entityType,
    key,
    localEntityId: entityId(local),
    remoteEntityId: entityId(remote),
    local,
    remote,
    remoteDeleted,
    createdAt: ctx.now,
    resolvedAt: null,
    resolution: "pending",
    materializedId: null,
  };
}

function mergeRows<T extends MergeRow>(args: {
  entityType: EntityType;
  spaceId: string;
  local: T[];
  remote: T[];
  keyOf: (item: T) => string;
  localTombstones: Tombstone[];
  remoteTombstones: Tombstone[];
  canInsert: (item: T, current: T[]) => boolean;
  conflicts: ConflictRecord[];
  ctx: ReduceContext;
}): { items: T[]; tombstones: Tombstone[]; conflicts: ConflictRecord[] } {
  const items = [...args.local];
  const tombstones = [...args.localTombstones];
  const conflicts = [...args.conflicts];
  const remember = (candidate: {
    entityType: EntityType;
    key: string;
    local: unknown;
    remote: unknown;
    remoteDeleted: boolean;
  }) => {
    if (samePending(conflicts, candidate)) return;
    conflicts.push(
      makeConflict(
        args.ctx,
        args.spaceId,
        candidate.entityType,
        candidate.key,
        candidate.local,
        candidate.remote,
        candidate.remoteDeleted,
      ),
    );
  };

  const keyIndex = () => new Map(items.map((item) => [args.keyOf(item), item]));

  for (const remoteItem of args.remote) {
    const key = args.keyOf(remoteItem);
    const localItem = keyIndex().get(key);
    if (!localItem) {
      const deleted = tombstones.find(
        (stone) =>
          stone.entityType === args.entityType && stone.naturalKey === key,
      );
      if (deleted) {
        remember({
          entityType: args.entityType,
          key,
          local: deleted.payload,
          remote: remoteItem,
          remoteDeleted: false,
        });
        continue;
      }
      if (!args.canInsert(remoteItem, items)) {
        remember({
          entityType: args.entityType,
          key,
          local: null,
          remote: remoteItem,
          remoteDeleted: false,
        });
        continue;
      }
      items.push(structuredClone(remoteItem));
      continue;
    }
    if (canonical(localItem) === canonical(remoteItem)) continue;
    remember({
      entityType: args.entityType,
      key,
      local: localItem,
      remote: remoteItem,
      remoteDeleted: false,
    });
  }

  for (const remoteStone of args.remoteTombstones) {
    if (remoteStone.entityType !== args.entityType) continue;
    const localItem = items.find(
      (item) => args.keyOf(item) === remoteStone.naturalKey,
    );
    const known = tombstones.some(
      (stone) =>
        stone.entityType === remoteStone.entityType &&
        stone.naturalKey === remoteStone.naturalKey,
    );
    if (!localItem) {
      if (!known) tombstones.push(structuredClone(remoteStone));
      continue;
    }
    if (canonical(localItem) === canonical(remoteStone.payload)) {
      const index = items.findIndex(
        (item) => args.keyOf(item) === remoteStone.naturalKey,
      );
      if (index >= 0) items.splice(index, 1);
      if (!known) tombstones.push(structuredClone(remoteStone));
      continue;
    }
    remember({
      entityType: args.entityType,
      key: remoteStone.naturalKey,
      local: localItem,
      remote: remoteStone.payload,
      remoteDeleted: true,
    });
  }

  return { items, tombstones, conflicts };
}

function replaceCollection<T extends { spaceId: string }>(
  all: T[],
  spaceId: string,
  next: T[],
): T[] {
  return [...all.filter((item) => item.spaceId !== spaceId), ...next];
}

/**
 * Merge a remote space into the local database.
 * Matching records that both changed are kept as a conflict: the local record
 * stays active, and both payloads are stored. Nothing from either side is dropped.
 * Attendance and volunteering stay unique per person and event so the percentage
 * formula keeps a single active mark until someone resolves the conflict.
 */
export function mergeSyncBundle(
  db: Database,
  bundle: SyncBundle,
  ctx: ReduceContext,
): Result<Database> {
  const remote = bundle.snapshot;
  const spaceId = remote.space.id;
  if (!db.spaces.some((space) => space.id === spaceId)) {
    return ok(replaceSpace(db, remote));
  }

  const localTombstones = db.tombstones.filter((stone) => stone.spaceId === spaceId);
  const remoteTombstones = remote.tombstones;
  let conflicts = db.conflicts.filter((conflict) => conflict.spaceId === spaceId);
  const restConflicts = db.conflicts.filter((conflict) => conflict.spaceId !== spaceId);

  if (canonical(db.spaces.find((space) => space.id === spaceId)) !== canonical(remote.space)) {
    const candidate = {
      entityType: "space" as const,
      key: spaceId,
      local: db.spaces.find((space) => space.id === spaceId) ?? null,
      remote: remote.space,
      remoteDeleted: false,
    };
    if (!samePending(conflicts, candidate)) {
      conflicts.push(
        makeConflict(ctx, spaceId, "space", spaceId, candidate.local, candidate.remote, false),
      );
    }
  }

  const people = mergeRows({
    entityType: "person",
    spaceId,
    local: db.people.filter((item) => item.spaceId === spaceId),
    remote: remote.people,
    keyOf: (item) => item.id,
    localTombstones,
    remoteTombstones,
    canInsert: () => true,
    conflicts,
    ctx,
  });
  conflicts = people.conflicts;

  const groups = mergeRows({
    entityType: "group",
    spaceId,
    local: db.groups.filter((item) => item.spaceId === spaceId),
    remote: remote.groups,
    keyOf: (item) => item.id,
    localTombstones: people.tombstones,
    remoteTombstones,
    canInsert: () => true,
    conflicts,
    ctx,
  });
  conflicts = groups.conflicts;

  const memberships = mergeRows({
    entityType: "membership",
    spaceId,
    local: db.memberships.filter((item) => item.spaceId === spaceId),
    remote: remote.memberships,
    keyOf: (item) => item.id,
    localTombstones: groups.tombstones,
    remoteTombstones,
    canInsert: (item, current) => !findMembershipOverlap(current, item),
    conflicts,
    ctx,
  });
  conflicts = memberships.conflicts;

  const periods = mergeRows({
    entityType: "period",
    spaceId,
    local: db.periods.filter((item) => item.spaceId === spaceId),
    remote: remote.periods,
    keyOf: (item) => item.id,
    localTombstones: memberships.tombstones,
    remoteTombstones,
    canInsert: () => true,
    conflicts,
    ctx,
  });
  conflicts = periods.conflicts;

  const components = mergeRows({
    entityType: "component",
    spaceId,
    local: db.components.filter((item) => item.spaceId === spaceId),
    remote: remote.components,
    keyOf: (item) => item.id,
    localTombstones: periods.tombstones,
    remoteTombstones,
    canInsert: () => true,
    conflicts,
    ctx,
  });
  conflicts = components.conflicts;

  const categories = mergeRows({
    entityType: "category",
    spaceId,
    local: db.categories.filter((item) => item.spaceId === spaceId),
    remote: remote.categories,
    keyOf: (item) => item.id,
    localTombstones: components.tombstones,
    remoteTombstones,
    canInsert: () => true,
    conflicts,
    ctx,
  });
  conflicts = categories.conflicts;

  const events = mergeRows({
    entityType: "event",
    spaceId,
    local: db.events.filter((item) => item.spaceId === spaceId),
    remote: remote.events,
    keyOf: (item) => item.id,
    localTombstones: categories.tombstones,
    remoteTombstones,
    canInsert: () => true,
    conflicts,
    ctx,
  });
  conflicts = events.conflicts;

  const attendance = mergeRows({
    entityType: "attendance",
    spaceId,
    local: db.attendance.filter((item) => item.spaceId === spaceId),
    remote: remote.attendance,
    keyOf: (item) => `${item.eventId}:${item.personId}`,
    localTombstones: events.tombstones,
    remoteTombstones,
    canInsert: (item, current) =>
      !current.some(
        (record) =>
          record.eventId === item.eventId && record.personId === item.personId,
      ),
    conflicts,
    ctx,
  });
  conflicts = attendance.conflicts;

  const volunteering = mergeRows({
    entityType: "volunteering",
    spaceId,
    local: db.volunteering.filter((item) => item.spaceId === spaceId),
    remote: remote.volunteering,
    keyOf: (item) => `${item.eventId}:${item.personId}`,
    localTombstones: attendance.tombstones,
    remoteTombstones,
    canInsert: (item, current) =>
      !current.some(
        (record) =>
          record.eventId === item.eventId && record.personId === item.personId,
      ),
    conflicts,
    ctx,
  });
  conflicts = volunteering.conflicts;

  const templates = mergeRows({
    entityType: "template",
    spaceId,
    local: db.templates.filter((item) => item.spaceId === spaceId),
    remote: remote.templates,
    keyOf: (item) => item.id,
    localTombstones: volunteering.tombstones,
    remoteTombstones,
    canInsert: () => true,
    conflicts,
    ctx,
  });
  conflicts = templates.conflicts;

  const assets = mergeRows({
    entityType: "asset",
    spaceId,
    local: db.assets.filter((item) => item.spaceId === spaceId),
    remote: remote.assets,
    keyOf: (item) => item.id,
    localTombstones: templates.tombstones,
    remoteTombstones,
    canInsert: () => true,
    conflicts,
    ctx,
  });

  const membershipItems = memberships.items as GroupMembership[];
  return ok({
    ...db,
    people: replaceCollection(db.people, spaceId, people.items),
    groups: replaceCollection(db.groups, spaceId, groups.items),
    memberships: replaceCollection(db.memberships, spaceId, membershipItems),
    periods: replaceCollection(db.periods, spaceId, periods.items),
    components: replaceCollection(db.components, spaceId, components.items),
    categories: replaceCollection(db.categories, spaceId, categories.items),
    events: replaceCollection(db.events, spaceId, events.items),
    attendance: replaceCollection(db.attendance, spaceId, attendance.items),
    volunteering: replaceCollection(db.volunteering, spaceId, volunteering.items),
    templates: replaceCollection(db.templates, spaceId, templates.items),
    assets: replaceCollection(db.assets, spaceId, assets.items),
    tombstones: replaceCollection(db.tombstones, spaceId, assets.tombstones),
    conflicts: [...restConflicts, ...assets.conflicts],
  });
}

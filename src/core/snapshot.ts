import type { Database, SpaceSnapshot } from "@/core/types";

function pick<T extends { spaceId: string }>(list: T[], spaceId: string): T[] {
  return list.filter((item) => item.spaceId === spaceId);
}

export function takeSnapshot(db: Database, spaceId: string): SpaceSnapshot {
  const space = db.spaces.find((item) => item.id === spaceId);
  if (!space) {
    throw new Error(`Cannot snapshot missing space ${spaceId}`);
  }
  return structuredClone({
    space,
    people: pick(db.people, spaceId),
    groups: pick(db.groups, spaceId),
    memberships: pick(db.memberships, spaceId),
    periods: pick(db.periods, spaceId),
    components: pick(db.components, spaceId),
    categories: pick(db.categories, spaceId),
    events: pick(db.events, spaceId),
    attendance: pick(db.attendance, spaceId),
    volunteering: pick(db.volunteering, spaceId),
    templates: pick(db.templates, spaceId),
    assets: pick(db.assets, spaceId),
    conflicts: pick(db.conflicts, spaceId),
    tombstones: pick(db.tombstones, spaceId),
  });
}

export function replaceSpace(db: Database, snapshot: SpaceSnapshot): Database {
  const spaceId = snapshot.space.id;
  const drop = <T extends { spaceId: string }>(list: T[]) =>
    list.filter((item) => item.spaceId !== spaceId);
  const next = structuredClone(snapshot);
  return {
    ...db,
    spaces: [...db.spaces.filter((item) => item.id !== spaceId), next.space],
    people: [...drop(db.people), ...next.people],
    groups: [...drop(db.groups), ...next.groups],
    memberships: [...drop(db.memberships), ...next.memberships],
    periods: [...drop(db.periods), ...next.periods],
    components: [...drop(db.components), ...next.components],
    categories: [...drop(db.categories), ...next.categories],
    events: [...drop(db.events), ...next.events],
    attendance: [...drop(db.attendance), ...next.attendance],
    volunteering: [...drop(db.volunteering), ...next.volunteering],
    templates: [...drop(db.templates), ...next.templates],
    assets: [...drop(db.assets), ...next.assets],
    conflicts: [...drop(db.conflicts), ...next.conflicts],
    tombstones: [...drop(db.tombstones), ...next.tombstones],
  };
}

export function stripSpace(db: Database, spaceId: string): Database {
  const drop = <T extends { spaceId: string }>(list: T[]) =>
    list.filter((item) => item.spaceId !== spaceId);
  return {
    ...db,
    spaces: db.spaces.filter((item) => item.id !== spaceId),
    people: drop(db.people),
    groups: drop(db.groups),
    memberships: drop(db.memberships),
    periods: drop(db.periods),
    components: drop(db.components),
    categories: drop(db.categories),
    events: drop(db.events),
    attendance: drop(db.attendance),
    volunteering: drop(db.volunteering),
    templates: drop(db.templates),
    assets: drop(db.assets),
    conflicts: drop(db.conflicts),
    tombstones: drop(db.tombstones),
  };
}

"use client";

import { useApp } from "@/state/store";

export function useSpaceData(spaceId: string) {
  const app = useApp();
  const { db } = app;
  const byName = <T extends { name: string; id: string }>(items: T[]) =>
    [...items].sort((a, b) => a.name.localeCompare(b.name) || a.id.localeCompare(b.id));
  return {
    ...app,
    space: db.spaces.find((item) => item.id === spaceId) ?? null,
    people: byName(db.people.filter((item) => item.spaceId === spaceId)),
    groups: byName(db.groups.filter((item) => item.spaceId === spaceId)),
    memberships: db.memberships.filter((item) => item.spaceId === spaceId),
    periods: db.periods
      .filter((item) => item.spaceId === spaceId)
      .sort((a, b) => b.startDate.localeCompare(a.startDate)),
    components: byName(db.components.filter((item) => item.spaceId === spaceId)),
    categories: byName(db.categories.filter((item) => item.spaceId === spaceId)),
    events: db.events
      .filter((item) => item.spaceId === spaceId)
      .sort((a, b) => b.date.localeCompare(a.date) || a.title.localeCompare(b.title)),
    attendance: db.attendance.filter((item) => item.spaceId === spaceId),
    volunteering: db.volunteering.filter((item) => item.spaceId === spaceId),
    templates: byName(db.templates.filter((item) => item.spaceId === spaceId)),
    assets: db.assets.filter((item) => item.spaceId === spaceId && !item.deletedAt),
    conflicts: db.conflicts.filter((item) => item.spaceId === spaceId),
    history: db.histories.find((item) => item.spaceId === spaceId) ?? null,
    revisions: db.revisions.filter((item) => item.spaceId === spaceId),
  };
}

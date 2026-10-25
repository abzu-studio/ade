import { dateInRange, rangesOverlap } from "@/core/dates";
import type { Database, GroupMembership, Person } from "@/core/types";

export function membershipCovers(
  membership: GroupMembership,
  date: string,
): boolean {
  return dateInRange(date, membership.startDate, membership.endDate);
}

export function findMembershipOverlap(
  memberships: GroupMembership[],
  candidate: {
    groupId: string;
    personId: string;
    startDate: string;
    endDate: string | null;
    ignoreId?: string;
  },
): GroupMembership | null {
  return (
    memberships.find(
      (membership) =>
        membership.id !== candidate.ignoreId &&
        membership.groupId === candidate.groupId &&
        membership.personId === candidate.personId &&
        rangesOverlap(
          membership.startDate,
          membership.endDate,
          candidate.startDate,
          candidate.endDate,
        ),
    ) ?? null
  );
}

export function isMemberOnDate(
  db: Database,
  groupId: string,
  personId: string,
  date: string,
): boolean {
  return db.memberships.some(
    (membership) =>
      membership.groupId === groupId &&
      membership.personId === personId &&
      membershipCovers(membership, date),
  );
}

export function membersAt(
  db: Database,
  groupId: string,
  date: string,
): Person[] {
  const ids = new Set(
    db.memberships
      .filter(
        (membership) =>
          membership.groupId === groupId && membershipCovers(membership, date),
      )
      .map((membership) => membership.personId),
  );
  return db.people
    .filter((person) => ids.has(person.id))
    .sort((a, b) => a.name.localeCompare(b.name) || a.id.localeCompare(b.id));
}

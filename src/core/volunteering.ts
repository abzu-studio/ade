import {
  CAPACITY_STATES,
  VOLUNTEER_TRANSITIONS,
  VOLUNTEER_WEIGHTS,
} from "@/core/constants";
import { daysBetween } from "@/core/dates";
import type {
  Database,
  ScoreFactor,
  VolunteerState,
  VolunteerSuggestion,
} from "@/core/types";

export function canTransitionVolunteer(
  from: VolunteerState | null,
  to: VolunteerState,
): boolean {
  if (from === to) return true;
  if (from === null) return to === "interested" || to === "selected";
  return VOLUNTEER_TRANSITIONS[from].includes(to);
}

export function volunteerNaturalKey(eventId: string, personId: string): string {
  return `${eventId}:${personId}`;
}

export function consumingVolunteerCount(
  db: Database,
  eventId: string,
  ignorePersonId?: string,
): number {
  return db.volunteering.filter(
    (record) =>
      record.eventId === eventId &&
      record.personId !== ignorePersonId &&
      CAPACITY_STATES.has(record.state),
  ).length;
}

export function suggestVolunteers(
  db: Database,
  eventId: string,
): VolunteerSuggestion[] {
  const event = db.events.find((item) => item.id === eventId);
  if (!event) return [];
  const suggestions = db.people
    .filter((person) => person.spaceId === event.spaceId && person.status === "active")
    .map((person) => scorePerson(db, event.id, person.id, person.name));
  suggestions.sort((a, b) => {
    if (b.score !== a.score) return b.score - a.score;
    if (b.completedCount !== a.completedCount) {
      return b.completedCount - a.completedCount;
    }
    const name = a.name.localeCompare(b.name);
    if (name !== 0) return name;
    return a.personId.localeCompare(b.personId);
  });
  return suggestions;
}

function scorePerson(
  db: Database,
  eventId: string,
  personId: string,
  name: string,
): VolunteerSuggestion {
  const event = db.events.find((item) => item.id === eventId)!;
  const current = db.volunteering.find(
    (record) => record.eventId === eventId && record.personId === personId,
  );
  const factors: ScoreFactor[] = [];
  let completedCount = 0;
  let recentCompleted = 0;
  let sameComponentCompleted = 0;
  let selected = 0;
  let priorInterested = 0;
  let declined = 0;
  let absent = 0;

  for (const record of db.volunteering) {
    if (record.personId !== personId || record.eventId === eventId) continue;
    const other = db.events.find((item) => item.id === record.eventId);
    if (!other || other.spaceId !== event.spaceId) continue;
    if (other.date >= event.date) continue;
    if (record.state === "completed") {
      completedCount += 1;
      if (
        daysBetween(other.date, event.date) > 0 &&
        daysBetween(other.date, event.date) <= VOLUNTEER_WEIGHTS.recentDays
      ) {
        recentCompleted += 1;
      }
      if (other.componentId === event.componentId) sameComponentCompleted += 1;
    } else if (record.state === "selected") selected += 1;
    else if (record.state === "interested") priorInterested += 1;
    else if (record.state === "declined") declined += 1;
    else if (record.state === "absent") absent += 1;
  }

  let presentCount = 0;
  for (const record of db.attendance) {
    if (record.personId !== personId || record.state !== "present") continue;
    const other = db.events.find((item) => item.id === record.eventId);
    if (!other || other.spaceId !== event.spaceId || other.date >= event.date) {
      continue;
    }
    if (other.status === "cancelled" || !other.countsForAttendance) continue;
    if (!other.participantIds.includes(personId)) continue;
    presentCount += 1;
  }

  const push = (code: ScoreFactor["code"], count: number, pointsEach: number, cap?: number) => {
    if (count <= 0) return;
    const points = Math.min(count, cap ?? count) * pointsEach;
    factors.push({ code, count, points });
  };

  push("completed", completedCount, VOLUNTEER_WEIGHTS.completed);
  push("recentCompleted", recentCompleted, VOLUNTEER_WEIGHTS.recentCompleted);
  push(
    "sameComponentCompleted",
    sameComponentCompleted,
    VOLUNTEER_WEIGHTS.sameComponentCompleted,
  );
  push("selected", selected, VOLUNTEER_WEIGHTS.selected);
  push("priorInterested", priorInterested, VOLUNTEER_WEIGHTS.priorInterested);
  push("declined", declined, VOLUNTEER_WEIGHTS.declined);
  push("absent", absent, VOLUNTEER_WEIGHTS.absent);
  push(
    "attendancePresent",
    presentCount,
    VOLUNTEER_WEIGHTS.attendancePresent,
    VOLUNTEER_WEIGHTS.attendancePresentCap,
  );
  if (current?.state === "interested") {
    factors.push({
      code: "interestedNow",
      count: 1,
      points: VOLUNTEER_WEIGHTS.interestedNow,
    });
  }
  if (factors.length === 0) {
    factors.push({ code: "no-history", count: 0, points: 0 });
  }

  const eligible = !current || current.state === "interested";
  return {
    personId,
    name,
    score: factors.reduce((sum, factor) => sum + factor.points, 0),
    completedCount,
    eligible,
    factors,
  };
}

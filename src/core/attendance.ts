import { ATTENDANCE_FORMULA } from "@/core/constants";
import { dateInRange, rangesOverlap } from "@/core/dates";
import { isMemberOnDate } from "@/core/groups";
import type {
  AdeEvent,
  AttendanceBreakdown,
  AttendanceLine,
  AttendanceQuery,
  AttendanceRecord,
  Database,
  Person,
} from "@/core/types";

function byName(a: Person, b: Person): number {
  return a.name.localeCompare(b.name) || a.id.localeCompare(b.id);
}

function byDate(a: AdeEvent, b: AdeEvent): number {
  return a.date.localeCompare(b.date) || a.id.localeCompare(b.id);
}

function eventsFor(db: Database, query: AttendanceQuery): AdeEvent[] {
  return db.events
    .filter((event) => {
      if (event.spaceId !== query.spaceId) return false;
      if (query.eventId && event.id !== query.eventId) return false;
      if (query.componentId && event.componentId !== query.componentId) {
        return false;
      }
      if (query.categoryId && event.categoryId !== query.categoryId) {
        return false;
      }
      if (query.periodId) {
        const period = db.periods.find((item) => item.id === query.periodId);
        if (!period) return false;
        if (!dateInRange(event.date, period.startDate, period.endDate)) {
          return false;
        }
      }
      return true;
    })
    .sort(byDate);
}

function peopleFor(db: Database, query: AttendanceQuery): Person[] {
  const people = db.people.filter((person) => person.spaceId === query.spaceId);
  if (query.personId) {
    return people.filter((person) => person.id === query.personId).sort(byName);
  }
  if (!query.groupId) return people.sort(byName);

  let windowStart = "0000-01-01";
  let windowEnd: string | null = null;
  if (query.periodId) {
    const period = db.periods.find((item) => item.id === query.periodId);
    if (!period) return [];
    windowStart = period.startDate;
    windowEnd = period.endDate;
  } else if (query.eventId) {
    const event = db.events.find((item) => item.id === query.eventId);
    if (!event) return [];
    windowStart = event.date;
    windowEnd = event.date;
  }

  const memberIds = new Set(
    db.memberships
      .filter(
        (membership) =>
          membership.spaceId === query.spaceId &&
          membership.groupId === query.groupId &&
          rangesOverlap(
            membership.startDate,
            membership.endDate,
            windowStart,
            windowEnd,
          ),
      )
      .map((membership) => membership.personId),
  );
  return people.filter((person) => memberIds.has(person.id)).sort(byName);
}

function latestRecord(
  records: AttendanceRecord[],
  eventId: string,
  personId: string,
): AttendanceRecord | null {
  const matches = records.filter(
    (record) => record.eventId === eventId && record.personId === personId,
  );
  if (matches.length === 0) return null;
  return matches.reduce((latest, record) =>
    record.updatedAt >= latest.updatedAt ? record : latest,
  );
}

/**
 * Attendance percentage uses only present and absent marks.
 * Pending, excused, missing marks, cancelled events, events that do not count,
 * and anyone not on that event's participant list are excluded.
 * A missing mark is not turned into an absence.
 * Group membership is applied only when the query names a group: a person counts
 * on an event only if they belonged to that group on the event date.
 */
export function attendanceLines(
  db: Database,
  query: AttendanceQuery,
): AttendanceLine[] {
  const events = eventsFor(db, query);
  const people = peopleFor(db, query);
  const lines: AttendanceLine[] = [];

  for (const person of people) {
    for (const event of events) {
      lines.push(lineFor(db, query, event, person.id));
    }
  }
  return lines;
}

function lineFor(
  db: Database,
  query: AttendanceQuery,
  event: AdeEvent,
  personId: string,
): AttendanceLine {
  const base = { eventId: event.id, personId };
  if (!event.participantIds.includes(personId)) {
    return { ...base, outcome: "excluded", reason: "not-participant", state: null };
  }
  if (
    query.groupId &&
    !isMemberOnDate(db, query.groupId, personId, event.date)
  ) {
    return {
      ...base,
      outcome: "excluded",
      reason: "not-member-on-date",
      state: null,
    };
  }
  if (event.status === "cancelled") {
    return { ...base, outcome: "excluded", reason: "cancelled", state: null };
  }
  if (!event.countsForAttendance) {
    return { ...base, outcome: "excluded", reason: "not-counting", state: null };
  }
  const record = latestRecord(db.attendance, event.id, personId);
  if (!record) {
    return { ...base, outcome: "excluded", reason: "unrecorded", state: null };
  }
  if (record.state === "pending" || record.state === "excused") {
    return {
      ...base,
      outcome: "excluded",
      reason: record.state,
      state: record.state,
    };
  }
  return {
    ...base,
    outcome: record.state,
    reason: null,
    state: record.state,
  };
}

export function summarizeAttendance(lines: AttendanceLine[]): AttendanceBreakdown {
  const breakdown: AttendanceBreakdown = {
    present: 0,
    absent: 0,
    excused: 0,
    pending: 0,
    unrecorded: 0,
    excludedCancelled: 0,
    excludedNotCounting: 0,
    excludedNotParticipant: 0,
    excludedNotMember: 0,
    denominator: 0,
    percentage: null,
    formula: ATTENDANCE_FORMULA,
    lines,
  };
  for (const line of lines) {
    if (line.outcome === "present") breakdown.present += 1;
    else if (line.outcome === "absent") breakdown.absent += 1;
    else if (line.reason === "excused") breakdown.excused += 1;
    else if (line.reason === "pending") breakdown.pending += 1;
    else if (line.reason === "unrecorded") breakdown.unrecorded += 1;
    else if (line.reason === "cancelled") breakdown.excludedCancelled += 1;
    else if (line.reason === "not-counting") breakdown.excludedNotCounting += 1;
    else if (line.reason === "not-participant") {
      breakdown.excludedNotParticipant += 1;
    } else if (line.reason === "not-member-on-date") {
      breakdown.excludedNotMember += 1;
    }
  }
  breakdown.denominator = breakdown.present + breakdown.absent;
  breakdown.percentage =
    breakdown.denominator === 0
      ? null
      : breakdown.present / breakdown.denominator;
  return breakdown;
}

export function computeAttendance(
  db: Database,
  query: AttendanceQuery,
): AttendanceBreakdown {
  return summarizeAttendance(attendanceLines(db, query));
}

export function attendanceByPerson(
  db: Database,
  query: AttendanceQuery,
): Array<{ person: Person; breakdown: AttendanceBreakdown }> {
  const people = peopleFor(db, query);
  return people.map((person) => ({
    person,
    breakdown: computeAttendance(db, { ...query, personId: person.id }),
  }));
}

export function formatPercent(percentage: number | null): string {
  if (percentage === null) return "—";
  return `${(percentage * 100).toFixed(1)}%`;
}

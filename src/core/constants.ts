import type { AttendanceState, EventStatus, VolunteerState } from "@/core/types";

/** Percentage = present / (present + absent). */
export const ATTENDANCE_FORMULA = "present / (present + absent)" as const;

/**
 * Volunteer suggestion weights. Previous participation is the primary signal.
 * The current event is never counted as previous participation.
 * Final selection is always a manual action; these weights only rank people.
 */
export const VOLUNTEER_WEIGHTS = {
  completed: 10,
  recentCompleted: 5,
  sameComponentCompleted: 2,
  selected: 3,
  priorInterested: 1,
  interestedNow: 8,
  declined: -2,
  absent: -4,
  attendancePresent: 1,
  attendancePresentCap: 10,
  recentDays: 180,
} as const;

export const PAGE_SIZES = {
  letter: { width: 612, height: 792 },
  a4: { width: 595.28, height: 841.89 },
} as const;

export const EVENT_TRANSITIONS: Record<EventStatus, EventStatus[]> = {
  draft: ["scheduled", "cancelled"],
  scheduled: ["draft", "completed", "cancelled"],
  completed: ["scheduled", "cancelled"],
  cancelled: ["scheduled"],
};

export const VOLUNTEER_TRANSITIONS: Record<
  VolunteerState,
  VolunteerState[]
> = {
  interested: ["selected", "declined"],
  selected: ["completed", "declined", "absent", "interested"],
  completed: ["selected"],
  declined: ["interested"],
  absent: ["selected"],
};

export const CAPACITY_STATES: ReadonlySet<VolunteerState> = new Set([
  "selected",
  "completed",
]);

export const ATTENDANCE_STATES: readonly AttendanceState[] = [
  "present",
  "absent",
  "excused",
  "pending",
];

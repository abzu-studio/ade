"use client";

import { VOLUNTEER_WEIGHTS } from "@/core/constants";
import { useI18n } from "@/i18n";
import type { MessageKey } from "@/i18n/en";

const rows: Array<{ key: MessageKey; points: number }> = [
  { key: "volunteers.factors.completed", points: VOLUNTEER_WEIGHTS.completed },
  { key: "volunteers.factors.recentCompleted", points: VOLUNTEER_WEIGHTS.recentCompleted },
  { key: "volunteers.factors.sameComponentCompleted", points: VOLUNTEER_WEIGHTS.sameComponentCompleted },
  { key: "volunteers.factors.selected", points: VOLUNTEER_WEIGHTS.selected },
  { key: "volunteers.factors.priorInterested", points: VOLUNTEER_WEIGHTS.priorInterested },
  { key: "volunteers.factors.interestedNow", points: VOLUNTEER_WEIGHTS.interestedNow },
  { key: "volunteers.factors.declined", points: VOLUNTEER_WEIGHTS.declined },
  { key: "volunteers.factors.absent", points: VOLUNTEER_WEIGHTS.absent },
  { key: "volunteers.factors.attendancePresent", points: VOLUNTEER_WEIGHTS.attendancePresent },
];

export function WeightList() {
  const { t } = useI18n();
  return (
    <ul className="flex flex-col gap-1 text-sm">
      {rows.map((row) => (
        <li key={row.key}>{t(row.key, { count: "1", points: String(row.points) })}</li>
      ))}
      <li>{t("volunteers.recentDays", { days: String(VOLUNTEER_WEIGHTS.recentDays) })}</li>
      <li>{t("volunteers.presentCap", { cap: String(VOLUNTEER_WEIGHTS.attendancePresentCap) })}</li>
    </ul>
  );
}

import { formatPercent } from "@/core/attendance";
import type { DocumentLabels, Revision } from "@/core/types";
import { en, type MessageKey } from "@/i18n/en";

type Translate = (key: MessageKey, params?: Record<string, string>) => string;

export function documentLabels(t: Translate): DocumentLabels {
  return {
    unrecorded: t("attendance.unrecorded"),
    attendance: {
      present: t("attendance.present"),
      absent: t("attendance.absent"),
      excused: t("attendance.excused"),
      pending: t("attendance.pending"),
    },
    volunteer: {
      interested: t("volunteer.interested"),
      selected: t("volunteer.selected"),
      completed: t("volunteer.completed"),
      declined: t("volunteer.declined"),
      absent: t("volunteer.absent"),
    },
    eventStatus: {
      draft: t("status.draft"),
      scheduled: t("status.scheduled"),
      completed: t("status.completed"),
      cancelled: t("status.cancelled"),
    },
    percent: formatPercent,
    counts: (present, absent) => `${present}/${present + absent}`,
    separator: " - ",
  };
}

export function revisionText(t: Translate, revision: Revision): string {
  const key = `revision.${revision.action}` as MessageKey;
  if (!(key in en)) return revision.action;
  const params = { ...revision.params };
  if (revision.action === "setAttendance" && params.state) {
    params.state = t(`attendance.${params.state}` as MessageKey);
  }
  if (revision.action === "setVolunteerState" && params.state) {
    params.state = t(`volunteer.${params.state}` as MessageKey);
  }
  if (params.status && `status.${params.status}` in en) {
    params.status = t(`status.${params.status}` as MessageKey);
  }
  if (params.resolution === "kept-local") params.resolution = t("conflicts.keepLocal");
  if (params.resolution === "kept-remote") params.resolution = t("conflicts.keepRemote");
  if (params.resolution === "kept-both") params.resolution = t("conflicts.keepBoth");
  return t(key, params);
}

export function formatWhen(iso: string, locale: string): string {
  const formatted = new Intl.DateTimeFormat(locale, {
    timeZone: "America/Puerto_Rico",
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(iso));
  return `${formatted} (Puerto Rico)`;
}

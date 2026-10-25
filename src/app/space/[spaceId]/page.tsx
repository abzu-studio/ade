"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { formatWhen, revisionText } from "@/components/ade/labels";
import { useSpaceData } from "@/components/ade/space";
import type { Revision } from "@/core/types";
import { useI18n } from "@/i18n";
import type { MessageKey } from "@/i18n/en";

const steps: Array<{ href: string; key: MessageKey }> = [
  { href: "people", key: "overview.stepPeople" },
  { href: "taxonomy", key: "overview.stepTaxonomy" },
  { href: "events", key: "overview.stepEvent" },
  { href: "events", key: "overview.stepVolunteers" },
  { href: "events", key: "overview.stepAttendance" },
  { href: "participation", key: "overview.stepResults" },
  { href: "documents", key: "overview.stepDocument" },
];

export default function OverviewPage() {
  const params = useParams<{ spaceId: string }>();
  const { t, locale } = useI18n();
  const data = useSpaceData(params.spaceId);
  if (!data.space) return null;
  const next = nextStep(data);
  const cursor = data.history?.cursor ?? -1;
  const currentId = cursor >= 0 ? data.history?.revisionIds[cursor] : undefined;
  const recent = (data.history?.revisionIds ?? [])
    .slice(0, cursor + 1)
    .slice(-6)
    .map((id) => data.revisions.find((revision) => revision.id === id))
    .filter((revision): revision is Revision => Boolean(revision));
  const counts = [
    [t("nav.people"), data.people.length],
    [t("nav.groups"), data.groups.length],
    [t("nav.periods"), data.periods.length],
    [t("taxonomy.component"), data.components.length],
    [t("nav.events"), data.events.length],
    [t("nav.documents"), data.templates.length],
  ] as const;

  return (
    <div className="grid gap-10 lg:grid-cols-[minmax(0,1fr)_18rem]">
      <div className="flex flex-col gap-8">
        <h1 className="ade-display text-5xl md:text-7xl">{data.space.name}</h1>
        <p className="flex flex-wrap items-baseline gap-3">
          <span className="ade-kicker">{t("overview.next")}</span>
          <Link href={`/space/${params.spaceId}/${next.href}`} className="ade-verb">
            {t(next.key)}
          </Link>
        </p>
        <section>
          <h2 className="ade-kicker">{t("overview.cycle")}</h2>
          <ol className="mt-2 border-t border-[#4a2a18]">
            {steps.map((step, index) => (
              <li key={step.key} className="ade-row">
                <Link
                  href={`/space/${params.spaceId}/${step.href}`}
                  className="flex items-baseline gap-4 py-2"
                >
                  <span className="ade-kicker w-8">{String(index + 1).padStart(2, "0")}</span>
                  <span className={step.key === next.key ? "ade-verb" : "text-sm"}>{t(step.key)}</span>
                </Link>
              </li>
            ))}
          </ol>
        </section>
        <section>
          <h2 className="ade-kicker">{t("overview.counts")}</h2>
          <ul className="mt-2 flex flex-wrap gap-x-6 gap-y-2 border-y border-[#4a2a18] py-3">
            {counts.map(([label, count]) => (
              <li key={label} className="flex items-baseline gap-2">
                <span className="ade-kicker">{label}</span>
                <span className="font-mono text-sm">{count}</span>
              </li>
            ))}
          </ul>
        </section>
      </div>
      <aside className="flex flex-col gap-3">
        <div className="flex items-baseline justify-between gap-3">
          <h2 className="ade-kicker">{t("nav.history")}</h2>
          <Link href={`/space/${params.spaceId}/history`} className="ade-verb">
            {t("action.open")}
          </Link>
        </div>
        {recent.length === 0 ? (
          <p className="text-sm">{t("history.empty")}</p>
        ) : (
          <ol className="border-t border-[#4a2a18]">
            {recent.map((revision) => (
              <li key={revision.id} className="ade-row flex flex-col items-start gap-1 py-2">
                <span className="font-mono text-[0.6875rem] leading-snug">{formatWhen(revision.at, locale)}</span>
                <span className="text-sm">{revisionText(t, revision)}</span>
                {revision.id === currentId ? <span className="ade-stamp">{t("history.current")}</span> : null}
              </li>
            ))}
          </ol>
        )}
      </aside>
    </div>
  );
}

function nextStep(data: ReturnType<typeof useSpaceData>): { href: string; key: MessageKey } {
  if (data.people.length === 0) return { href: "people", key: "overview.stepPeople" };
  if (data.components.length === 0) return { href: "taxonomy", key: "overview.stepTaxonomy" };
  if (data.events.length === 0) return { href: "events", key: "overview.stepEvent" };
  const withPeople = data.events.filter((event) => event.participantIds.length > 0);
  if (withPeople.length === 0) {
    return { href: `events/${data.events[0].id}`, key: "overview.stepEvent" };
  }
  const open = data.events.filter((event) => event.status === "scheduled" || event.status === "completed");
  if (open.length === 0) {
    return { href: `events/${withPeople[0].id}`, key: "overview.stepEvent" };
  }
  const volunteerTarget = open.find((event) => event.volunteerCapacity !== 0);
  const selected = data.volunteering.some(
    (record) => record.state === "selected" || record.state === "completed",
  );
  if (volunteerTarget && !selected) {
    return { href: `events/${volunteerTarget.id}/volunteers`, key: "overview.stepVolunteers" };
  }
  const attendanceTarget = open.find((event) => {
    if (!event.countsForAttendance || event.participantIds.length === 0) return false;
    return event.participantIds.some(
      (personId) =>
        !data.attendance.some((record) => record.eventId === event.id && record.personId === personId),
    );
  });
  if (attendanceTarget) {
    return { href: `events/${attendanceTarget.id}/attendance`, key: "overview.stepAttendance" };
  }
  if (data.templates.length === 0) return { href: "documents", key: "overview.stepDocument" };
  return { href: "participation", key: "overview.stepResults" };
}

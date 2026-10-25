"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { buttonVariants } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { useSpaceData } from "@/components/ade/space";
import { PageHeader } from "@/components/ade/widgets";
import { useI18n } from "@/i18n";
import type { MessageKey } from "@/i18n/en";
import { cn } from "@/lib/utils";

export default function OverviewPage() {
  const params = useParams<{ spaceId: string }>();
  const { t } = useI18n();
  const data = useSpaceData(params.spaceId);
  if (!data.space) return null;
  const steps: Array<{ href: string; key: MessageKey }> = [
    { href: "people", key: "overview.stepPeople" },
    { href: "taxonomy", key: "overview.stepTaxonomy" },
    { href: "events", key: "overview.stepEvent" },
    { href: "events", key: "overview.stepVolunteers" },
    { href: "events", key: "overview.stepAttendance" },
    { href: "participation", key: "overview.stepResults" },
    { href: "documents", key: "overview.stepDocument" },
  ];
  const counts = [
    [t("nav.people"), data.people.length],
    [t("nav.groups"), data.groups.length],
    [t("nav.periods"), data.periods.length],
    [t("taxonomy.component"), data.components.length],
    [t("nav.events"), data.events.length],
    [t("nav.documents"), data.templates.length],
  ] as const;
  return (
    <>
      <PageHeader title={data.space.name} description={t("overview.cycle")} />
      <Card>
        <CardHeader>
          <CardTitle>{t("overview.cycle")}</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-col gap-2">
          {steps.map((step, index) => (
            <Link
              key={step.key}
              href={`/space/${params.spaceId}/${step.href}`}
              className={cn(buttonVariants({ variant: "ghost" }), "justify-start")}
            >
              {index + 1}. {t(step.key)}
            </Link>
          ))}
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle>{t("overview.counts")}</CardTitle>
        </CardHeader>
        <CardContent>
          <ul className="flex flex-col gap-1 text-sm">
            {counts.map(([label, count]) => (
              <li key={label} className="flex justify-between gap-4">
                <span>{label}</span>
                <span>{count}</span>
              </li>
            ))}
          </ul>
        </CardContent>
      </Card>
    </>
  );
}

"use client";

import { useParams } from "next/navigation";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Checkbox } from "@/components/ui/checkbox";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { useSpaceData } from "@/components/ade/space";
import { Choice, EmptyState, PageHeader } from "@/components/ade/widgets";
import { attendanceByPerson, computeAttendance, formatPercent } from "@/core/attendance";
import type { AttendanceBreakdown } from "@/core/types";
import { useI18n } from "@/i18n";
import type { MessageKey } from "@/i18n/en";

export default function ParticipationPage() {
  const params = useParams<{ spaceId: string }>();
  const { t } = useI18n();
  const data = useSpaceData(params.spaceId);
  const [periodId, setPeriodId] = useState("all");
  const [groupId, setGroupId] = useState("all");
  const [componentId, setComponentId] = useState("all");
  const [categoryId, setCategoryId] = useState("all");
  const [showSkipped, setShowSkipped] = useState(false);
  const [personId, setPersonId] = useState<string | null>(null);

  const query = {
    spaceId: params.spaceId,
    periodId: periodId === "all" ? null : periodId,
    groupId: groupId === "all" ? null : groupId,
    componentId: componentId === "all" ? null : componentId,
    categoryId: categoryId === "all" ? null : categoryId,
  };
  const pooled = computeAttendance(data.db, query);
  const rows = attendanceByPerson(data.db, query);
  const selected = rows.find((row) => row.person.id === personId) ?? null;
  const categories = data.categories.filter(
    (category) => componentId === "all" || category.componentId === componentId,
  );

  return (
    <>
      <PageHeader title={t("participation.title")} description={t("participation.formula")} />
      <p className="max-w-3xl text-sm text-muted-foreground">{t("participation.explain")}</p>
      {groupId !== "all" ? <p className="max-w-3xl text-sm">{t("participation.groupRule")}</p> : null}
      <div className="grid gap-3 md:grid-cols-2">
        <Choice
          label={t("nav.periods")}
          value={periodId}
          onChange={setPeriodId}
          options={[
            { value: "all", label: t("common.all") },
            ...data.periods.map((period) => ({ value: period.id, label: period.name })),
          ]}
        />
        <Choice
          label={t("nav.groups")}
          value={groupId}
          onChange={setGroupId}
          options={[
            { value: "all", label: t("common.all") },
            ...data.groups.map((group) => ({ value: group.id, label: group.name })),
          ]}
        />
        <Choice
          label={t("taxonomy.component")}
          value={componentId}
          onChange={(value) => {
            setComponentId(value);
            setCategoryId("all");
          }}
          options={[
            { value: "all", label: t("common.all") },
            ...data.components.map((component) => ({ value: component.id, label: component.name })),
          ]}
        />
        <Choice
          label={t("taxonomy.category")}
          value={categoryId}
          onChange={setCategoryId}
          options={[
            { value: "all", label: t("common.all") },
            ...categories.map((category) => ({ value: category.id, label: category.name })),
          ]}
        />
      </div>
      {data.events.length === 0 ? (
        <EmptyState>{t("participation.empty")}</EmptyState>
      ) : (
        <>
          <Card>
            <CardHeader>
              <CardTitle>{t("participation.pooled")}</CardTitle>
            </CardHeader>
            <CardContent className="flex flex-col gap-1 text-sm">
              <p>
                {t("participation.percentage")}: {formatPercent(pooled.percentage)}
              </p>
              <p>
                {pooled.formula} = {pooled.present} / {pooled.denominator}
              </p>
              <p className="text-muted-foreground">{t("participation.pooledRule")}</p>
              <BreakdownCounts breakdown={pooled} />
            </CardContent>
          </Card>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("common.person")}</TableHead>
                <TableHead>{t("attendance.present")}</TableHead>
                <TableHead>{t("attendance.absent")}</TableHead>
                <TableHead>{t("participation.percentage")}</TableHead>
                <TableHead />
              </TableRow>
            </TableHeader>
            <TableBody>
              {rows.map((row) => (
                <TableRow key={row.person.id}>
                  <TableCell>{row.person.name}</TableCell>
                  <TableCell>{row.breakdown.present}</TableCell>
                  <TableCell>{row.breakdown.absent}</TableCell>
                  <TableCell>{formatPercent(row.breakdown.percentage)}</TableCell>
                  <TableCell>
                    <Button type="button" variant="outline" onClick={() => setPersonId(row.person.id)}>
                      {t("participation.detail")}
                    </Button>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </>
      )}
      <Dialog open={selected !== null} onOpenChange={(open) => { if (!open) setPersonId(null); }}>
        <DialogContent className="max-w-2xl">
          <DialogHeader>
            <DialogTitle>{selected?.person.name}</DialogTitle>
            <DialogDescription>
              {selected
                ? `${formatPercent(selected.breakdown.percentage)} · ${selected.breakdown.present} / ${selected.breakdown.denominator}`
                : ""}
            </DialogDescription>
          </DialogHeader>
          <label className="flex items-center gap-2 text-sm">
            <Checkbox checked={showSkipped} onCheckedChange={(checked) => setShowSkipped(checked === true)} />
            {t("participation.showSkipped")}
          </label>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("common.date")}</TableHead>
                <TableHead>{t("nav.events")}</TableHead>
                <TableHead>{t("common.status")}</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {(selected?.breakdown.lines ?? [])
                .filter((line) => showSkipped || line.reason !== "not-participant")
                .map((line) => {
                  const event = data.events.find((item) => item.id === line.eventId);
                  const label = line.reason
                    ? t(`participation.reason.${line.reason}` as MessageKey)
                    : t(`attendance.${line.outcome}` as MessageKey);
                  return (
                    <TableRow key={line.eventId}>
                      <TableCell>{event?.date}</TableCell>
                      <TableCell>{event?.title}</TableCell>
                      <TableCell>{label}</TableCell>
                    </TableRow>
                  );
                })}
            </TableBody>
          </Table>
        </DialogContent>
      </Dialog>
    </>
  );
}

function BreakdownCounts({ breakdown }: { breakdown: AttendanceBreakdown }) {
  const { t } = useI18n();
  const items = [
    [t("attendance.excused"), breakdown.excused],
    [t("attendance.pending"), breakdown.pending],
    [t("attendance.unrecorded"), breakdown.unrecorded],
    [t("participation.reason.cancelled"), breakdown.excludedCancelled],
    [t("participation.reason.not-counting"), breakdown.excludedNotCounting],
    [t("participation.reason.not-participant"), breakdown.excludedNotParticipant],
    [t("participation.reason.not-member-on-date"), breakdown.excludedNotMember],
  ] as const;
  return (
    <ul className="flex flex-col gap-1">
      {items
        .filter(([, count]) => count > 0)
        .map(([label, count]) => (
          <li key={label}>
            {label}: {count}
          </li>
        ))}
    </ul>
  );
}

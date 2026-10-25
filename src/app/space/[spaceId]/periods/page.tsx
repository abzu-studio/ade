"use client";

import { useState } from "react";
import { useParams } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { useSpaceData } from "@/components/ade/space";
import { EmptyState, PageHeader, SaveButton, TextField } from "@/components/ade/widgets";
import { useI18n } from "@/i18n";
import type { Period } from "@/core/types";

export default function PeriodsPage() {
  const params = useParams<{ spaceId: string }>();
  const { t } = useI18n();
  const { periods, run } = useSpaceData(params.spaceId);
  const [name, setName] = useState("");
  const [startDate, setStartDate] = useState("2026-01-01");
  const [endDate, setEndDate] = useState("2026-06-30");
  const [editing, setEditing] = useState<Period | null>(null);
  return (
    <>
      <PageHeader title={t("periods.title")} description={t("periods.empty")} />
      <form
        className="grid gap-3 md:grid-cols-4"
        onSubmit={(event) => {
          event.preventDefault();
          const result = run(
            { type: "createPeriod", spaceId: params.spaceId, name, startDate, endDate },
            t("common.saved"),
          );
          if (result.ok) setName("");
        }}
      >
        <TextField label={t("common.name")} value={name} onChange={setName} required />
        <TextField label={t("periods.start")} type="date" value={startDate} onChange={setStartDate} required />
        <TextField label={t("periods.end")} type="date" value={endDate} onChange={setEndDate} required />
        <div className="flex items-end">
          <SaveButton label={t("periods.add")} />
        </div>
      </form>
      {periods.length === 0 ? (
        <EmptyState>{t("periods.empty")}</EmptyState>
      ) : (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{t("common.name")}</TableHead>
              <TableHead>{t("periods.start")}</TableHead>
              <TableHead>{t("periods.end")}</TableHead>
              <TableHead />
            </TableRow>
          </TableHeader>
          <TableBody>
            {periods.map((period) => (
              <TableRow key={period.id}>
                <TableCell>{period.name}</TableCell>
                <TableCell>
                  {editing?.id === period.id ? (
                    <Input
                      type="date"
                      value={editing.startDate}
                      onChange={(event) => setEditing({ ...editing, startDate: event.target.value })}
                    />
                  ) : (
                    period.startDate
                  )}
                </TableCell>
                <TableCell>
                  {editing?.id === period.id ? (
                    <Input
                      type="date"
                      value={editing.endDate}
                      onChange={(event) => setEditing({ ...editing, endDate: event.target.value })}
                    />
                  ) : (
                    period.endDate
                  )}
                </TableCell>
                <TableCell className="flex gap-2">
                  {editing?.id === period.id ? (
                    <Button
                      type="button"
                      onClick={() => {
                        const result = run({
                          type: "updatePeriod",
                          spaceId: params.spaceId,
                          periodId: period.id,
                          name: editing.name,
                          startDate: editing.startDate,
                          endDate: editing.endDate,
                        });
                        if (result.ok) setEditing(null);
                      }}
                    >
                      {t("action.save")}
                    </Button>
                  ) : (
                    <Button type="button" variant="outline" onClick={() => setEditing(period)}>
                      {t("action.edit")}
                    </Button>
                  )}
                  <Button
                    type="button"
                    variant="outline"
                    onClick={() => run({ type: "deletePeriod", spaceId: params.spaceId, periodId: period.id })}
                  >
                    {t("action.delete")}
                  </Button>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      )}
    </>
  );
}

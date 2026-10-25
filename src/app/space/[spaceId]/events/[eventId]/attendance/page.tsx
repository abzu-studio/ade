"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useEffect, useState } from "react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button, buttonVariants } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { RecordHistory } from "@/components/ade/history-sheet";
import { useSpaceData } from "@/components/ade/space";
import { EmptyState, PageHeader } from "@/components/ade/widgets";
import { computeAttendance, formatPercent } from "@/core/attendance";
import { ATTENDANCE_STATES } from "@/core/constants";
import type { AttendanceState, Person } from "@/core/types";
import { useI18n } from "@/i18n";
import type { MessageKey } from "@/i18n/en";
import { cn } from "@/lib/utils";

const shortcut: Record<string, AttendanceState> = {
  p: "present",
  a: "absent",
  e: "excused",
  w: "pending",
};

export default function AttendancePage() {
  const params = useParams<{ spaceId: string; eventId: string }>();
  const { t } = useI18n();
  const data = useSpaceData(params.spaceId);
  const event = data.events.find((item) => item.id === params.eventId) ?? null;
  const participants = (event?.participantIds ?? [])
    .map((id) => data.people.find((person) => person.id === id))
    .filter((person): person is Person => Boolean(person));
  const [index, setIndex] = useState(0);
  const [notes, setNotes] = useState<Record<string, string>>({});
  const [historyFor, setHistoryFor] = useState<string | null>(null);
  const canMark = event?.status === "scheduled" || event?.status === "completed";
  const safeIndex = Math.min(index, Math.max(0, participants.length - 1));
  const savedNotes = (event?.participantIds ?? [])
    .map((personId) => {
      const record = data.db.attendance.find(
        (item) => item.eventId === event?.id && item.personId === personId,
      );
      return `${personId}:${record?.note ?? ""}:${record?.updatedAt ?? ""}`;
    })
    .join("|");

  useEffect(() => {
    if (!event) return;
    const next: Record<string, string> = {};
    for (const personId of event.participantIds) {
      const record = data.db.attendance.find(
        (item) => item.eventId === event.id && item.personId === personId,
      );
      next[personId] = record?.note ?? "";
    }
    setNotes(next);
  }, [event, data.db.attendance, savedNotes]);

  useEffect(() => {
    function onKey(keyEvent: KeyboardEvent) {
      const target = keyEvent.target;
      if (target instanceof HTMLElement) {
        const tag = target.tagName;
        if (tag === "INPUT" || tag === "TEXTAREA" || target.isContentEditable) return;
      }
      if (participants.length === 0) return;
      if (keyEvent.key === "ArrowDown") {
        keyEvent.preventDefault();
        setIndex((current) => Math.min(participants.length - 1, current + 1));
        return;
      }
      if (keyEvent.key === "ArrowUp") {
        keyEvent.preventDefault();
        setIndex((current) => Math.max(0, current - 1));
        return;
      }
      const state = shortcut[keyEvent.key.toLowerCase()];
      const person = participants[safeIndex];
      if (!state || !person || !canMark) return;
      keyEvent.preventDefault();
      data.run({
        type: "setAttendance",
        spaceId: params.spaceId,
        eventId: event!.id,
        personId: person.id,
        state,
        note: notes[person.id] ?? "",
      });
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [canMark, data, event, notes, params.spaceId, participants, safeIndex]);

  if (!event) return <EmptyState>{t("error.NOT_FOUND")}</EmptyState>;

  const breakdown = computeAttendance(data.db, { spaceId: params.spaceId, eventId: event.id });
  const historyPerson = participants.find((person) => person.id === historyFor) ?? null;
  const historyRecord = historyPerson
    ? data.attendance.find((record) => record.eventId === event.id && record.personId === historyPerson.id)
    : null;

  return (
    <>
      <PageHeader title={event.title} description={t("attendance.formula")}>
        <Link
          href={`/space/${params.spaceId}/events/${event.id}`}
          className={cn(buttonVariants({ variant: "outline" }))}
        >
          {t("events.details")}
        </Link>
      </PageHeader>
      <Alert>
        <AlertDescription>{t("attendance.help")}</AlertDescription>
      </Alert>
      <p className="text-sm text-muted-foreground">{t("attendance.shortcuts")}</p>
      {!canMark ? (
        <Alert>
          <AlertDescription>{t("attendance.notAllowed")}</AlertDescription>
        </Alert>
      ) : null}
      {!event.countsForAttendance ? (
        <Alert>
          <AlertDescription>{t("participation.reason.not-counting")}</AlertDescription>
        </Alert>
      ) : null}
      <Card>
        <CardHeader>
          <CardTitle>{t("attendance.running")}</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-col gap-1 text-sm">
          <p>
            {t("participation.percentage")}: {formatPercent(breakdown.percentage)}
          </p>
          <p>
            {breakdown.formula} = {breakdown.present} / {breakdown.denominator}
          </p>
          <p>
            {t("attendance.present")} {breakdown.present} · {t("attendance.absent")} {breakdown.absent} ·{" "}
            {t("attendance.excused")} {breakdown.excused} · {t("attendance.pending")} {breakdown.pending} ·{" "}
            {t("attendance.unrecorded")} {breakdown.unrecorded}
          </p>
        </CardContent>
      </Card>
      {participants.length === 0 ? (
        <EmptyState>{t("attendance.empty")}</EmptyState>
      ) : (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{t("common.person")}</TableHead>
              <TableHead>{t("common.status")}</TableHead>
              <TableHead>{t("attendance.title")}</TableHead>
              <TableHead>{t("attendance.note")}</TableHead>
              <TableHead />
            </TableRow>
          </TableHeader>
          <TableBody>
            {participants.map((person, personIndex) => {
              const record = data.attendance.find(
                (item) => item.eventId === event.id && item.personId === person.id,
              );
              return (
                <TableRow key={person.id} data-state={personIndex === safeIndex ? "selected" : undefined}>
                  <TableCell>
                    <button type="button" className="text-left" onClick={() => setIndex(personIndex)}>
                      {person.name}
                    </button>
                  </TableCell>
                  <TableCell>
                    <Badge variant="secondary">
                      {record ? t(`attendance.${record.state}` as MessageKey) : t("attendance.unrecorded")}
                    </Badge>
                  </TableCell>
                  <TableCell>
                    <div className="flex flex-wrap gap-1">
                      {ATTENDANCE_STATES.map((state) => (
                        <Button
                          key={state}
                          type="button"
                          size="sm"
                          variant={record?.state === state ? "secondary" : "outline"}
                          disabled={!canMark}
                          onClick={() => {
                            setIndex(personIndex);
                            data.run({
                              type: "setAttendance",
                              spaceId: params.spaceId,
                              eventId: event.id,
                              personId: person.id,
                              state,
                              note: notes[person.id] ?? "",
                            });
                          }}
                        >
                          {t(`attendance.${state}` as MessageKey)}
                        </Button>
                      ))}
                    </div>
                  </TableCell>
                  <TableCell>
                    <div className="flex gap-2">
                      <Input
                        value={notes[person.id] ?? ""}
                        onChange={(input) =>
                          setNotes((current) => ({ ...current, [person.id]: input.target.value }))
                        }
                        aria-label={t("attendance.note")}
                      />
                      <Button
                        type="button"
                        variant="outline"
                        disabled={!canMark || !record}
                        onClick={() =>
                          data.run(
                            {
                              type: "setAttendance",
                              spaceId: params.spaceId,
                              eventId: event.id,
                              personId: person.id,
                              state: record!.state,
                              note: notes[person.id] ?? "",
                            },
                            t("common.saved"),
                          )
                        }
                      >
                        {t("attendance.saveNote")}
                      </Button>
                    </div>
                  </TableCell>
                  <TableCell>
                    <Button type="button" variant="ghost" onClick={() => setHistoryFor(person.id)}>
                      {t("attendance.history")}
                    </Button>
                  </TableCell>
                </TableRow>
              );
            })}
          </TableBody>
        </Table>
      )}
      <RecordHistory
        open={historyFor !== null}
        title={historyPerson?.name ?? t("attendance.history")}
        onOpenChange={(open) => {
          if (!open) setHistoryFor(null);
        }}
        entries={(historyRecord?.history ?? []).map((entry) => ({
          at: entry.at,
          previous: entry.previousState ? t(`attendance.${entry.previousState}` as MessageKey) : null,
          next: t(`attendance.${entry.nextState}` as MessageKey),
          nextNote: entry.nextNote,
        }))}
      />
    </>
  );
}

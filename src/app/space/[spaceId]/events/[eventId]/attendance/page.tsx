"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useEffect, useState } from "react";
import { RecordHistory } from "@/components/ade/history-sheet";
import { useSpaceData } from "@/components/ade/space";
import { computeAttendance, formatPercent } from "@/core/attendance";
import { ATTENDANCE_STATES } from "@/core/constants";
import type { AttendanceState, Person } from "@/core/types";
import { useI18n } from "@/i18n";
import type { MessageKey } from "@/i18n/en";

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

  if (!event) return <p className="text-sm">{t("error.NOT_FOUND")}</p>;

  const breakdown = computeAttendance(data.db, { spaceId: params.spaceId, eventId: event.id });
  const historyPerson = participants.find((person) => person.id === historyFor) ?? null;
  const historyRecord = historyPerson
    ? data.attendance.find((record) => record.eventId === event.id && record.personId === historyPerson.id)
    : null;

  return (
    <>
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <p className="ade-kicker">{event.date}</p>
          <h1 className="ade-display mt-2 text-5xl md:text-6xl">{event.title}</h1>
        </div>
        <Link href={`/space/${params.spaceId}/events/${event.id}`} className="ade-verb">
          {t("events.details")}
        </Link>
      </div>
      <p role="alert" className="max-w-3xl text-sm">
        {t("attendance.help")}
      </p>
      <p className="text-sm">{t("attendance.formula")}</p>
      <p className="text-sm">{t("attendance.shortcuts")}</p>
      {!canMark ? (
        <p role="alert" className="text-sm">
          {t("attendance.notAllowed")}
        </p>
      ) : null}
      {!event.countsForAttendance ? (
        <p role="alert" className="text-sm">
          {t("participation.reason.not-counting")}
        </p>
      ) : null}
      <section className="flex flex-wrap items-end justify-between gap-6 border-y border-[#4a2a18] py-4">
        <div>
          <p className="ade-kicker">{t("attendance.running")}</p>
          <p className="ade-display mt-2 text-6xl">{formatPercent(breakdown.percentage)}</p>
          <p className="mt-2 font-mono text-sm">
            {breakdown.formula} = {breakdown.present} / {breakdown.denominator}
          </p>
        </div>
        <p className="max-w-md text-sm">
          {t("attendance.present")} {breakdown.present} · {t("attendance.absent")} {breakdown.absent} ·{" "}
          {t("attendance.excused")} {breakdown.excused} · {t("attendance.pending")} {breakdown.pending} ·{" "}
          {t("attendance.unrecorded")} {breakdown.unrecorded}
        </p>
      </section>
      {participants.length === 0 ? (
        <p className="text-sm">{t("attendance.empty")}</p>
      ) : (
        <div className="border-t border-[#4a2a18]">
          {participants.map((person, personIndex) => {
            const record = data.attendance.find(
              (item) => item.eventId === event.id && item.personId === person.id,
            );
            return (
              <div
                key={person.id}
                className="ade-row flex flex-col gap-3 py-3 md:flex-row md:items-start"
                data-state={personIndex === safeIndex ? "selected" : undefined}
              >
                <button type="button" className="w-48 shrink-0 text-left" onClick={() => setIndex(personIndex)}>
                  {person.name}
                </button>
                <div className="flex min-w-0 flex-1 flex-col gap-3">
                  <div className="flex flex-wrap items-center gap-2">
                    {record ? null : <span className="ade-kicker">{t("attendance.unrecorded")}</span>}
                    {ATTENDANCE_STATES.map((state) => (
                      <button
                        key={state}
                        type="button"
                        className="ade-stamp"
                        aria-pressed={record?.state === state}
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
                      </button>
                    ))}
                  </div>
                  <div className="flex flex-wrap items-end gap-4">
                    <label className="flex min-w-48 flex-1 flex-col gap-1">
                      <span className="ade-kicker">{t("attendance.note")}</span>
                      <input
                        className="ade-line"
                        value={notes[person.id] ?? ""}
                        onChange={(input) =>
                          setNotes((current) => ({ ...current, [person.id]: input.target.value }))
                        }
                      />
                    </label>
                    <button
                      type="button"
                      className="ade-verb"
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
                    </button>
                    <button type="button" className="ade-verb" onClick={() => setHistoryFor(person.id)}>
                      {t("attendance.history")}
                    </button>
                  </div>
                </div>
              </div>
            );
          })}
        </div>
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

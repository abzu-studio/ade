"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useState } from "react";
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from "@/components/ui/accordion";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button, buttonVariants } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { RecordHistory } from "@/components/ade/history-sheet";
import { useSpaceData } from "@/components/ade/space";
import { EmptyState, PageHeader } from "@/components/ade/widgets";
import { WeightList } from "@/components/ade/weights";
import { VOLUNTEER_TRANSITIONS } from "@/core/constants";
import { canTransitionVolunteer, consumingVolunteerCount, suggestVolunteers } from "@/core/volunteering";
import type { VolunteerState } from "@/core/types";
import { useI18n } from "@/i18n";
import type { MessageKey } from "@/i18n/en";
import { cn } from "@/lib/utils";

function canMove(from: VolunteerState | null, to: VolunteerState): boolean {
  return from !== to && canTransitionVolunteer(from, to);
}

export default function VolunteersPage() {
  const params = useParams<{ spaceId: string; eventId: string }>();
  const { t } = useI18n();
  const data = useSpaceData(params.spaceId);
  const event = data.events.find((item) => item.id === params.eventId) ?? null;
  const [notes, setNotes] = useState<Record<string, string>>({});
  const [historyFor, setHistoryFor] = useState<string | null>(null);

  if (!event) return <EmptyState>{t("error.NOT_FOUND")}</EmptyState>;

  const locked = event.status === "cancelled";
  const suggestions = suggestVolunteers(data.db, event.id);
  const roster = data.volunteering
    .filter((record) => record.eventId === event.id)
    .sort((a, b) => {
      const left = data.people.find((person) => person.id === a.personId)?.name ?? a.personId;
      const right = data.people.find((person) => person.id === b.personId)?.name ?? b.personId;
      return left.localeCompare(right);
    });
  const used = consumingVolunteerCount(data.db, event.id);
  const historyRecord = roster.find((record) => record.personId === historyFor) ?? null;
  const historyName = data.people.find((person) => person.id === historyFor)?.name ?? "";

  function noteFor(personId: string, saved: string): string {
    return notes[personId] ?? saved;
  }

  function setState(personId: string, state: VolunteerState, savedNote: string) {
    data.run(
      {
        type: "setVolunteerState",
        spaceId: params.spaceId,
        eventId: event!.id,
        personId,
        state,
        note: noteFor(personId, savedNote),
      },
      t("common.saved"),
    );
  }

  return (
    <>
      <PageHeader title={event.title} description={t("volunteers.manual")}>
        <Link
          href={`/space/${params.spaceId}/events/${event.id}`}
          className={cn(buttonVariants({ variant: "outline" }))}
        >
          {t("events.details")}
        </Link>
      </PageHeader>
      {locked ? (
        <Alert>
          <AlertDescription>{t("volunteers.notAllowed")}</AlertDescription>
        </Alert>
      ) : null}
      <Card>
        <CardHeader>
          <CardTitle>{t("events.volunteerCapacity")}</CardTitle>
        </CardHeader>
        <CardContent className="text-sm">
          {t("volunteers.capacity", {
            used: String(used),
            capacity: event.volunteerCapacity === null ? t("common.unlimited") : String(event.volunteerCapacity),
          })}
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle>{t("volunteers.weights")}</CardTitle>
        </CardHeader>
        <CardContent>
          <WeightList />
        </CardContent>
      </Card>
      <section className="flex flex-col gap-3">
        <h2 className="text-lg font-semibold">{t("volunteers.suggest")}</h2>
        {suggestions.length === 0 ? (
          <EmptyState>{t("volunteers.empty")}</EmptyState>
        ) : (
          <Accordion>
            {suggestions.map((suggestion) => {
              const record = data.volunteering.find(
                (item) => item.eventId === event.id && item.personId === suggestion.personId,
              );
              const from = record?.state ?? null;
              return (
                <AccordionItem key={suggestion.personId} value={suggestion.personId}>
                  <AccordionTrigger>
                    <span className="flex flex-wrap items-center gap-2">
                      {suggestion.name}
                      <Badge variant="secondary">
                        {t("volunteers.score", { score: String(suggestion.score) })}
                      </Badge>
                      {record ? (
                        <Badge variant="outline">{t(`volunteer.${record.state}` as MessageKey)}</Badge>
                      ) : null}
                    </span>
                  </AccordionTrigger>
                  <AccordionContent>
                    <ul className="mb-3 flex flex-col gap-1">
                      {suggestion.factors.map((factor) => (
                        <li key={factor.code}>
                          {t(`volunteers.factors.${factor.code}` as MessageKey, {
                            count: String(factor.count),
                            points: String(factor.points),
                          })}
                        </li>
                      ))}
                    </ul>
                    <div className="flex flex-wrap gap-2">
                      {suggestion.eligible && !locked ? (
                        <Button type="button" onClick={() => setState(suggestion.personId, "selected", record?.note ?? "")}>
                          {t("volunteers.select")}
                        </Button>
                      ) : null}
                      {!locked && canMove(from, "interested") ? (
                        <Button
                          type="button"
                          variant="outline"
                          onClick={() => setState(suggestion.personId, "interested", record?.note ?? "")}
                        >
                          {t("volunteers.markInterested")}
                        </Button>
                      ) : null}
                    </div>
                  </AccordionContent>
                </AccordionItem>
              );
            })}
          </Accordion>
        )}
      </section>
      <section className="flex flex-col gap-3">
        <h2 className="text-lg font-semibold">{t("volunteers.roster")}</h2>
        {roster.length === 0 ? (
          <EmptyState>{t("common.empty")}</EmptyState>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("common.person")}</TableHead>
                <TableHead>{t("common.status")}</TableHead>
                <TableHead>{t("common.actions")}</TableHead>
                <TableHead>{t("common.notes")}</TableHead>
                <TableHead />
              </TableRow>
            </TableHeader>
            <TableBody>
              {roster.map((record) => {
                const name = data.people.find((person) => person.id === record.personId)?.name ?? record.personId;
                return (
                  <TableRow key={record.id}>
                    <TableCell>{name}</TableCell>
                    <TableCell>
                      <Badge variant="secondary">{t(`volunteer.${record.state}` as MessageKey)}</Badge>
                    </TableCell>
                    <TableCell>
                      <div className="flex flex-wrap gap-1">
                        {VOLUNTEER_TRANSITIONS[record.state].map((state) => (
                          <Button
                            key={state}
                            type="button"
                            size="sm"
                            variant="outline"
                            disabled={locked}
                            onClick={() => setState(record.personId, state, record.note)}
                          >
                            {t(`volunteer.${state}` as MessageKey)}
                          </Button>
                        ))}
                      </div>
                    </TableCell>
                    <TableCell>
                      <div className="flex gap-2">
                        <Input
                          value={noteFor(record.personId, record.note)}
                          onChange={(input) =>
                            setNotes((current) => ({ ...current, [record.personId]: input.target.value }))
                          }
                          aria-label={t("common.notes")}
                        />
                        <Button
                          type="button"
                          variant="outline"
                          disabled={locked}
                          onClick={() => setState(record.personId, record.state, record.note)}
                        >
                          {t("action.save")}
                        </Button>
                      </div>
                    </TableCell>
                    <TableCell>
                      <Button type="button" variant="ghost" onClick={() => setHistoryFor(record.personId)}>
                        {t("attendance.history")}
                      </Button>
                    </TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        )}
      </section>
      <RecordHistory
        open={historyFor !== null}
        title={historyName}
        onOpenChange={(open) => {
          if (!open) setHistoryFor(null);
        }}
        entries={(historyRecord?.history ?? []).map((entry) => ({
          at: entry.at,
          previous: entry.previousState ? t(`volunteer.${entry.previousState}` as MessageKey) : null,
          next: t(`volunteer.${entry.nextState}` as MessageKey),
          nextNote: entry.nextNote,
        }))}
      />
    </>
  );
}

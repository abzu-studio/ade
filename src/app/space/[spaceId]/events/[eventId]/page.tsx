"use client";

import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button, buttonVariants } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import {
  AlertDialog,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Textarea } from "@/components/ui/textarea";
import { useSpaceData } from "@/components/ade/space";
import {
  CapacityField,
  Choice,
  EmptyState,
  Field,
  PageHeader,
  SaveButton,
  TextField,
  parseCapacity,
} from "@/components/ade/widgets";
import { EVENT_TRANSITIONS } from "@/core/constants";
import type { EventStatus } from "@/core/types";
import { useI18n } from "@/i18n";
import type { MessageKey } from "@/i18n/en";
import { cn } from "@/lib/utils";

const statusAction: Record<EventStatus, MessageKey> = {
  draft: "events.backToDraft",
  scheduled: "events.schedule",
  completed: "events.complete",
  cancelled: "events.cancel",
};

export default function EventPage() {
  const params = useParams<{ spaceId: string; eventId: string }>();
  const router = useRouter();
  const { t } = useI18n();
  const data = useSpaceData(params.spaceId);
  const event = data.events.find((item) => item.id === params.eventId) ?? null;
  const [title, setTitle] = useState(event?.title ?? "");
  const [description, setDescription] = useState(event?.description ?? "");
  const [date, setDate] = useState(event?.date ?? "");
  const [componentId, setComponentId] = useState<string | null>(event?.componentId ?? null);
  const [categoryId, setCategoryId] = useState(event?.categoryId ?? "none");
  const [capacity, setCapacity] = useState(event?.capacity === null || event?.capacity === undefined ? "" : String(event.capacity));
  const [volunteerCapacity, setVolunteerCapacity] = useState(
    event?.volunteerCapacity === null || event?.volunteerCapacity === undefined ? "" : String(event.volunteerCapacity),
  );
  const [counts, setCounts] = useState(event?.countsForAttendance ?? true);
  const [participants, setParticipants] = useState<string[]>(event?.participantIds ?? []);
  const [cancelOpen, setCancelOpen] = useState(false);

  useEffect(() => {
    if (!event) return;
    setTitle(event.title);
    setDescription(event.description);
    setDate(event.date);
    setComponentId(event.componentId);
    setCategoryId(event.categoryId ?? "none");
    setCapacity(event.capacity === null ? "" : String(event.capacity));
    setVolunteerCapacity(event.volunteerCapacity === null ? "" : String(event.volunteerCapacity));
    setCounts(event.countsForAttendance);
    setParticipants(event.participantIds);
  }, [event]);

  if (!event) return <EmptyState>{t("error.NOT_FOUND")}</EmptyState>;

  const categories = data.categories.filter((category) => category.componentId === componentId);
  const locked = event.status === "cancelled";
  const component = data.components.find((item) => item.id === event.componentId);
  const category = data.categories.find((item) => item.id === event.categoryId);
  const base = `/space/${params.spaceId}/events/${event.id}`;

  return (
    <>
      <PageHeader title={event.title} description={event.date}>
        <Link href={`/space/${params.spaceId}/events`} className={cn(buttonVariants({ variant: "outline" }))}>
          {t("nav.events")}
        </Link>
        <Link href={`${base}/volunteers`} className={cn(buttonVariants({ variant: "outline" }))}>
          {t("events.volunteers")}
        </Link>
        <Link href={`${base}/attendance`} className={cn(buttonVariants())}>
          {t("events.attendance")}
        </Link>
      </PageHeader>
      <div className="flex flex-wrap items-center gap-2">
        <Badge variant={event.status === "cancelled" ? "destructive" : "secondary"}>
          {t(`status.${event.status}` as "status.draft")}
        </Badge>
        {event.countsForAttendance ? <Badge variant="outline">{t("events.counts")}</Badge> : null}
        <span className="text-sm text-muted-foreground">
          {component?.name ?? ""}
          {category ? ` · ${category.name}` : ""}
        </span>
      </div>
      <div className="flex flex-wrap gap-2">
        {EVENT_TRANSITIONS[event.status].map((status) =>
          status === "cancelled" ? (
            <Button key={status} type="button" variant="outline" onClick={() => setCancelOpen(true)}>
              {t(statusAction[status])}
            </Button>
          ) : (
            <Button
              key={status}
              type="button"
              variant="outline"
              onClick={() =>
                data.run({
                  type: "setEventStatus",
                  spaceId: params.spaceId,
                  eventId: event.id,
                  status,
                })
              }
            >
              {t(statusAction[status])}
            </Button>
          ),
        )}
        <Button
          type="button"
          variant="outline"
          onClick={() => {
            const result = data.run({
              type: "duplicateEvent",
              spaceId: params.spaceId,
              eventId: event.id,
              titleSuffix: t("common.copySuffix"),
            });
            if (!result.ok) return;
            const copy = result.value.events
              .filter((item) => item.duplicatedFromId === event.id)
              .reduce<(typeof result.value.events)[number] | null>(
                (best, item) => (!best || item.createdAt >= best.createdAt ? item : best),
                null,
              );
            if (copy) router.push(`/space/${params.spaceId}/events/${copy.id}`);
          }}
        >
          {t("events.duplicate")}
        </Button>
        {event.status === "draft" ? (
          <Button
            type="button"
            variant="outline"
            onClick={() => {
              const result = data.run({ type: "deleteEvent", spaceId: params.spaceId, eventId: event.id });
              if (result.ok) router.push(`/space/${params.spaceId}/events`);
            }}
          >
            {t("action.delete")}
          </Button>
        ) : null}
      </div>
      <Tabs defaultValue="details">
        <TabsList>
          <TabsTrigger value="details">{t("events.details")}</TabsTrigger>
          <TabsTrigger value="participants">{t("events.participants")}</TabsTrigger>
        </TabsList>
        <TabsContent value="details">
          <form
            className="mt-4 flex max-w-xl flex-col gap-3"
            onSubmit={(formEvent) => {
              formEvent.preventDefault();
              if (!componentId) return;
              const parsedCapacity = parseCapacity(capacity);
              const parsedVolunteer = parseCapacity(volunteerCapacity);
              data.run(
                {
                  type: "updateEvent",
                  spaceId: params.spaceId,
                  eventId: event.id,
                  title,
                  description,
                  date,
                  componentId,
                  categoryId: categoryId === "none" ? null : categoryId,
                  capacity: parsedCapacity === "invalid" ? -1 : parsedCapacity,
                  volunteerCapacity: parsedVolunteer === "invalid" ? -1 : parsedVolunteer,
                  countsForAttendance: counts,
                },
                t("common.saved"),
              );
            }}
          >
            <TextField label={t("common.name")} value={title} onChange={setTitle} required />
            <Field label={t("common.description")}>
              <Textarea value={description} onChange={(input) => setDescription(input.target.value)} />
            </Field>
            <TextField label={t("common.date")} type="date" value={date} onChange={setDate} required />
            <Choice
              label={t("taxonomy.component")}
              value={componentId}
              onChange={(value) => {
                setComponentId(value);
                const stillValid = data.categories.some(
                  (item) => item.id === categoryId && item.componentId === value,
                );
                if (!stillValid) setCategoryId("none");
              }}
              options={data.components.map((item) => ({ value: item.id, label: item.name }))}
            />
            <Choice
              label={t("taxonomy.category")}
              value={categoryId}
              onChange={setCategoryId}
              options={[
                { value: "none", label: t("common.none") },
                ...categories.map((item) => ({ value: item.id, label: item.name })),
              ]}
            />
            <CapacityField label={t("events.capacity")} value={capacity} onChange={setCapacity} />
            <CapacityField
              label={t("events.volunteerCapacity")}
              value={volunteerCapacity}
              onChange={setVolunteerCapacity}
            />
            <label className="flex items-center gap-2 text-sm">
              <Checkbox checked={counts} onCheckedChange={(checked) => setCounts(checked === true)} />
              {t("events.counts")}
            </label>
            <SaveButton label={t("action.save")} />
          </form>
        </TabsContent>
        <TabsContent value="participants">
          <div className="mt-4 flex max-w-xl flex-col gap-3">
            <p className="text-sm text-muted-foreground">
              {t("events.used", {
                used: String(participants.length),
                capacity: event.capacity === null ? t("common.unlimited") : String(event.capacity),
              })}
            </p>
            {locked ? <p className="text-sm">{t("events.locked")}</p> : null}
            {data.people.length === 0 ? (
              <EmptyState>{t("people.empty")}</EmptyState>
            ) : (
              data.people.map((person) => (
                <label key={person.id} className="flex items-center gap-2 text-sm">
                  <Checkbox
                    checked={participants.includes(person.id)}
                    disabled={locked}
                    onCheckedChange={(checked) => {
                      setParticipants((current) =>
                        checked === true
                          ? [...current, person.id]
                          : current.filter((id) => id !== person.id),
                      );
                    }}
                  />
                  <span>{person.name}</span>
                  {person.status === "inactive" ? (
                    <Badge variant="outline">{t("common.inactive")}</Badge>
                  ) : null}
                </label>
              ))
            )}
            {locked ? null : (
              <Button
                type="button"
                onClick={() =>
                  data.run(
                    {
                      type: "setEventParticipants",
                      spaceId: params.spaceId,
                      eventId: event.id,
                      participantIds: participants,
                    },
                    t("common.saved"),
                  )
                }
              >
                {t("action.save")}
              </Button>
            )}
          </div>
        </TabsContent>
      </Tabs>
      <AlertDialog open={cancelOpen} onOpenChange={setCancelOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t("events.cancel")}</AlertDialogTitle>
            <AlertDialogDescription>{t("events.cancelHelp")}</AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{t("action.close")}</AlertDialogCancel>
            <Button
              type="button"
              onClick={() => {
                const result = data.run({
                  type: "setEventStatus",
                  spaceId: params.spaceId,
                  eventId: event.id,
                  status: "cancelled",
                });
                if (result.ok) setCancelOpen(false);
              }}
            >
              {t("events.cancel")}
            </Button>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  );
}

"use client";

import Link from "next/link";
import { useState } from "react";
import { useParams } from "next/navigation";
import { Checkbox } from "@/components/ui/checkbox";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { useSpaceData } from "@/components/ade/space";
import { CapacityField, Choice, SaveButton, TextField, parseCapacity } from "@/components/ade/widgets";
import type { EventStatus } from "@/core/types";
import { useI18n } from "@/i18n";

const filters: Array<{ value: "all" | EventStatus; label: "common.all" | `status.${EventStatus}` }> = [
  { value: "all", label: "common.all" },
  { value: "draft", label: "status.draft" },
  { value: "scheduled", label: "status.scheduled" },
  { value: "completed", label: "status.completed" },
  { value: "cancelled", label: "status.cancelled" },
];

export default function EventsPage() {
  const params = useParams<{ spaceId: string }>();
  const { t } = useI18n();
  const data = useSpaceData(params.spaceId);
  const [open, setOpen] = useState(false);
  const [title, setTitle] = useState("");
  const [date, setDate] = useState("2026-06-01");
  const [componentId, setComponentId] = useState<string | null>(data.components[0]?.id ?? null);
  const [categoryId, setCategoryId] = useState<string>("none");
  const [capacity, setCapacity] = useState("");
  const [volunteerCapacity, setVolunteerCapacity] = useState("");
  const [counts, setCounts] = useState(true);
  const [status, setStatus] = useState<string>("all");
  const categories = data.categories.filter((category) => category.componentId === componentId);
  const visible = data.events.filter((event) => status === "all" || event.status === status);

  return (
    <>
      <div className="flex flex-wrap items-baseline justify-between gap-4">
        <div>
          <h1 className="ade-display text-5xl md:text-6xl">{t("events.title")}</h1>
          <p className="mt-3 max-w-3xl text-sm">{t("events.empty")}</p>
        </div>
        <button
          type="button"
          className="ade-verb"
          disabled={data.components.length === 0}
          onClick={() => setOpen(true)}
        >
          {t("events.add")}
        </button>
      </div>
      {data.components.length === 0 ? <p className="text-sm">{t("taxonomy.empty")}</p> : null}
      <div className="flex flex-wrap items-center gap-2">
        <span className="ade-kicker">{t("common.status")}</span>
        {filters.map((filter) => (
          <button
            key={filter.value}
            type="button"
            className="ade-stamp"
            aria-pressed={status === filter.value}
            onClick={() => setStatus(filter.value)}
          >
            {t(filter.label)}
          </button>
        ))}
      </div>
      {visible.length === 0 ? (
        <p className="text-sm">{t("events.empty")}</p>
      ) : (
        <div className="border-t border-[#4a2a18]">
          {visible.map((event) => (
            <div key={event.id} className="ade-row flex flex-wrap items-baseline gap-x-4 gap-y-2 py-3">
              <span className="w-28 font-mono text-sm">{event.date}</span>
              <span className="min-w-40 flex-1">{event.title}</span>
              <span className="ade-stamp" data-status={event.status}>
                {t(`status.${event.status}`)}
              </span>
              <span className="ade-kicker">
                {event.participantIds.length} {t("events.participants")}
              </span>
              <span className="flex flex-wrap gap-4">
                <Link href={`/space/${params.spaceId}/events/${event.id}`} className="ade-verb">
                  {t("action.open")}
                </Link>
                <button
                  type="button"
                  className="ade-verb"
                  onClick={() =>
                    data.run({
                      type: "duplicateEvent",
                      spaceId: params.spaceId,
                      eventId: event.id,
                      titleSuffix: t("common.copySuffix"),
                    })
                  }
                >
                  {t("events.duplicate")}
                </button>
                {event.status !== "cancelled" ? (
                  <button
                    type="button"
                    className="ade-verb"
                    onClick={() =>
                      data.run({
                        type: "setEventStatus",
                        spaceId: params.spaceId,
                        eventId: event.id,
                        status: "cancelled",
                      })
                    }
                  >
                    {t("events.cancel")}
                  </button>
                ) : null}
              </span>
            </div>
          ))}
        </div>
      )}
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{t("events.add")}</DialogTitle>
            <DialogDescription>{t("events.empty")}</DialogDescription>
          </DialogHeader>
          <form
            className="flex flex-col gap-3"
            onSubmit={(event) => {
              event.preventDefault();
              if (!componentId) return;
              const parsedCapacity = parseCapacity(capacity);
              const parsedVolunteer = parseCapacity(volunteerCapacity);
              if (parsedCapacity === "invalid" || parsedVolunteer === "invalid") {
                data.run({
                  type: "createEvent",
                  spaceId: params.spaceId,
                  title,
                  date,
                  componentId,
                  categoryId: null,
                  capacity: -1,
                  volunteerCapacity: null,
                  countsForAttendance: counts,
                });
                return;
              }
              const result = data.run(
                {
                  type: "createEvent",
                  spaceId: params.spaceId,
                  title,
                  date,
                  componentId,
                  categoryId: categoryId === "none" ? null : categoryId,
                  capacity: parsedCapacity,
                  volunteerCapacity: parsedVolunteer,
                  countsForAttendance: counts,
                },
                t("common.saved"),
              );
              if (result.ok) {
                setTitle("");
                setOpen(false);
              }
            }}
          >
            <TextField label={t("common.name")} value={title} onChange={setTitle} required />
            <TextField label={t("common.date")} type="date" value={date} onChange={setDate} required />
            <Choice
              label={t("taxonomy.component")}
              value={componentId}
              onChange={(value) => {
                setComponentId(value);
                setCategoryId("none");
              }}
              options={data.components.map((component) => ({ value: component.id, label: component.name }))}
            />
            <Choice
              label={t("taxonomy.category")}
              value={categoryId}
              onChange={setCategoryId}
              options={[
                { value: "none", label: t("common.none") },
                ...categories.map((category) => ({ value: category.id, label: category.name })),
              ]}
            />
            <CapacityField label={t("events.capacity")} value={capacity} onChange={setCapacity} />
            <CapacityField label={t("events.volunteerCapacity")} value={volunteerCapacity} onChange={setVolunteerCapacity} />
            <label className="flex items-center gap-2 text-sm">
              <Checkbox checked={counts} onCheckedChange={setCounts} />
              {t("events.counts")}
            </label>
            <DialogFooter>
              <SaveButton label={t("action.create")} />
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </>
  );
}

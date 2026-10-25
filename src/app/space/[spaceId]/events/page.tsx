"use client";

import Link from "next/link";
import { useState } from "react";
import { useParams } from "next/navigation";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { useSpaceData } from "@/components/ade/space";
import {
  CapacityField,
  Choice,
  EmptyState,
  PageHeader,
  SaveButton,
  TextField,
  parseCapacity,
} from "@/components/ade/widgets";
import { useI18n } from "@/i18n";

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
      <PageHeader title={t("events.title")} description={t("events.empty")}>
        <Button type="button" onClick={() => setOpen(true)} disabled={data.components.length === 0}>
          {t("events.add")}
        </Button>
      </PageHeader>
      {data.components.length === 0 ? <EmptyState>{t("taxonomy.empty")}</EmptyState> : null}
      <Choice
        label={t("common.status")}
        value={status}
        onChange={setStatus}
        options={[
          { value: "all", label: t("common.all") },
          { value: "draft", label: t("status.draft") },
          { value: "scheduled", label: t("status.scheduled") },
          { value: "completed", label: t("status.completed") },
          { value: "cancelled", label: t("status.cancelled") },
        ]}
      />
      {visible.length === 0 ? (
        <EmptyState>{t("events.empty")}</EmptyState>
      ) : (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{t("common.date")}</TableHead>
              <TableHead>{t("common.name")}</TableHead>
              <TableHead>{t("common.status")}</TableHead>
              <TableHead>{t("events.participants")}</TableHead>
              <TableHead />
            </TableRow>
          </TableHeader>
          <TableBody>
            {visible.map((event) => (
              <TableRow key={event.id}>
                <TableCell>{event.date}</TableCell>
                <TableCell>{event.title}</TableCell>
                <TableCell>
                  <Badge variant={event.status === "cancelled" ? "destructive" : "secondary"}>
                    {t(`status.${event.status}` as "status.draft")}
                  </Badge>
                </TableCell>
                <TableCell>{event.participantIds.length}</TableCell>
                <TableCell>
                  <DropdownMenu>
                    <DropdownMenuTrigger render={<Button variant="outline" />}>
                      {t("common.actions")}
                    </DropdownMenuTrigger>
                    <DropdownMenuContent>
                      <DropdownMenuItem render={<Link href={`/space/${params.spaceId}/events/${event.id}`} />}>
                        {t("action.open")}
                      </DropdownMenuItem>
                      <DropdownMenuItem
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
                      </DropdownMenuItem>
                      {event.status !== "cancelled" ? (
                        <DropdownMenuItem
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
                        </DropdownMenuItem>
                      ) : null}
                    </DropdownMenuContent>
                  </DropdownMenu>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
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

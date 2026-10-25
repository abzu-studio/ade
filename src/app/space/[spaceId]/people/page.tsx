"use client";

import { useState } from "react";
import { useParams } from "next/navigation";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  AlertDialog,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Textarea } from "@/components/ui/textarea";
import { useSpaceData } from "@/components/ade/space";
import { Choice, EmptyState, PageHeader, SaveButton, TextField } from "@/components/ade/widgets";
import { useI18n } from "@/i18n";
import type { Person, PersonStatus } from "@/core/types";

export default function PeoplePage() {
  const params = useParams<{ spaceId: string }>();
  const { t } = useI18n();
  const { people, run } = useSpaceData(params.spaceId);
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [notes, setNotes] = useState("");
  const [query, setQuery] = useState("");
  const [editing, setEditing] = useState<Person | null>(null);
  const [removing, setRemoving] = useState<Person | null>(null);
  const visible = people.filter((person) => person.name.toLowerCase().includes(query.trim().toLowerCase()));

  return (
    <>
      <PageHeader title={t("people.title")} />
      <form
        className="grid gap-3 md:grid-cols-2"
        onSubmit={(event) => {
          event.preventDefault();
          const result = run(
            { type: "createPerson", spaceId: params.spaceId, name, email, notes },
            t("common.saved"),
          );
          if (result.ok) {
            setName("");
            setEmail("");
            setNotes("");
          }
        }}
      >
        <TextField label={t("common.name")} value={name} onChange={setName} required />
        <TextField label={t("common.email")} value={email} onChange={setEmail} type="email" />
        <label className="flex flex-col gap-1.5 text-sm md:col-span-2">
          <span>{t("common.notes")}</span>
          <Textarea value={notes} onChange={(event) => setNotes(event.target.value)} />
        </label>
        <SaveButton label={t("people.add")} />
      </form>
      <TextField label={t("common.search")} value={query} onChange={setQuery} />
      {visible.length === 0 ? (
        <EmptyState>{t("people.empty")}</EmptyState>
      ) : (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{t("common.name")}</TableHead>
              <TableHead>{t("common.email")}</TableHead>
              <TableHead>{t("common.status")}</TableHead>
              <TableHead>{t("common.actions")}</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {visible.map((person) => (
              <TableRow key={person.id}>
                <TableCell>{person.name}</TableCell>
                <TableCell>{person.email}</TableCell>
                <TableCell>
                  <Badge variant={person.status === "active" ? "default" : "secondary"}>
                    {t(person.status === "active" ? "common.active" : "common.inactive")}
                  </Badge>
                </TableCell>
                <TableCell className="flex gap-2">
                  <Button type="button" variant="outline" onClick={() => setEditing(person)}>
                    {t("action.edit")}
                  </Button>
                  <Button type="button" variant="outline" onClick={() => setRemoving(person)}>
                    {t("action.delete")}
                  </Button>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      )}
      <PersonDialog person={editing} spaceId={params.spaceId} onClose={() => setEditing(null)} />
      <AlertDialog open={removing !== null} onOpenChange={(open) => !open && setRemoving(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t("people.delete")}</AlertDialogTitle>
            <AlertDialogDescription>{t("people.deleteHelp")}</AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{t("action.cancel")}</AlertDialogCancel>
            <Button
              type="button"
              variant="destructive"
              onClick={() => {
                if (!removing) return;
                const result = run({ type: "deletePerson", spaceId: params.spaceId, personId: removing.id });
                if (result.ok) setRemoving(null);
              }}
            >
              {t("action.delete")}
            </Button>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  );
}

function PersonDialog({
  person,
  spaceId,
  onClose,
}: {
  person: Person | null;
  spaceId: string;
  onClose: () => void;
}) {
  const { t } = useI18n();
  const { run } = useSpaceData(spaceId);
  const [draft, setDraft] = useState<Person | null>(null);
  const current = draft && person && draft.id === person.id ? draft : person;
  if (!current) return null;
  return (
    <Dialog open={person !== null} onOpenChange={(open) => !open && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{t("people.edit")}</DialogTitle>
          <DialogDescription>{current.name}</DialogDescription>
        </DialogHeader>
        <form
          className="flex flex-col gap-3"
          onSubmit={(event) => {
            event.preventDefault();
            const result = run(
              {
                type: "updatePerson",
                spaceId,
                personId: current.id,
                name: current.name,
                email: current.email,
                notes: current.notes,
                status: current.status,
              },
              t("common.saved"),
            );
            if (result.ok) onClose();
          }}
        >
          <TextField label={t("common.name")} value={current.name} onChange={(name) => setDraft({ ...current, name })} required />
          <TextField label={t("common.email")} value={current.email} onChange={(email) => setDraft({ ...current, email })} />
          <label className="flex flex-col gap-1.5 text-sm">
            <span>{t("common.notes")}</span>
            <Textarea value={current.notes} onChange={(event) => setDraft({ ...current, notes: event.target.value })} />
          </label>
          <Choice
            label={t("common.status")}
            value={current.status}
            onChange={(status) => setDraft({ ...current, status: status as PersonStatus })}
            options={[
              { value: "active", label: t("common.active") },
              { value: "inactive", label: t("common.inactive") },
            ]}
          />
          <DialogFooter>
            <Button type="button" variant="outline" onClick={onClose}>
              {t("action.cancel")}
            </Button>
            <SaveButton label={t("action.save")} />
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

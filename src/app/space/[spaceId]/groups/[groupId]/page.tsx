"use client";

import { useState } from "react";
import { useParams } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { membersAt } from "@/core/groups";
import { useSpaceData } from "@/components/ade/space";
import { Choice, EmptyState, PageHeader, SaveButton, TextField } from "@/components/ade/widgets";
import { useI18n } from "@/i18n";

export default function GroupPage() {
  const params = useParams<{ spaceId: string; groupId: string }>();
  const { t } = useI18n();
  const data = useSpaceData(params.spaceId);
  const group = data.groups.find((item) => item.id === params.groupId);
  const [personId, setPersonId] = useState<string | null>(data.people[0]?.id ?? null);
  const [startDate, setStartDate] = useState("2026-01-01");
  const [endDate, setEndDate] = useState("");
  const [onDate, setOnDate] = useState("2026-06-01");
  const [asked, setAsked] = useState(false);
  if (!group) return <p className="text-sm">{t("error.NOT_FOUND")}</p>;
  const memberships = data.db.memberships.filter((item) => item.groupId === group.id);
  const members = asked ? membersAt(data.db, group.id, onDate) : [];
  return (
    <>
      <PageHeader title={group.name} description={group.description || t("groups.empty")} />
      <form
        className="grid gap-3 md:grid-cols-4"
        onSubmit={(event) => {
          event.preventDefault();
          if (!personId) return;
          data.run(
            {
              type: "addMembership",
              spaceId: params.spaceId,
              groupId: group.id,
              personId,
              startDate,
              endDate: endDate || null,
            },
            t("common.saved"),
          );
        }}
      >
        <Choice
          label={t("common.person")}
          value={personId}
          onChange={setPersonId}
          options={data.people.map((person) => ({ value: person.id, label: person.name }))}
        />
        <TextField label={t("groups.start")} type="date" value={startDate} onChange={setStartDate} required />
        <TextField label={t("groups.end")} type="date" value={endDate} onChange={setEndDate} />
        <div className="flex items-end">
          <SaveButton label={t("groups.addMember")} />
        </div>
      </form>
      <p className="text-sm text-muted-foreground">{t("groups.endHelp")}</p>
      {memberships.length === 0 ? (
        <EmptyState>{t("groups.noMembers")}</EmptyState>
      ) : (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{t("common.person")}</TableHead>
              <TableHead>{t("groups.start")}</TableHead>
              <TableHead>{t("groups.end")}</TableHead>
              <TableHead />
            </TableRow>
          </TableHeader>
          <TableBody>
            {memberships.map((membership) => (
              <TableRow key={membership.id}>
                <TableCell>{data.people.find((person) => person.id === membership.personId)?.name}</TableCell>
                <TableCell>{membership.startDate}</TableCell>
                <TableCell>{membership.endDate ?? t("common.unlimited")}</TableCell>
                <TableCell>
                  <Button
                    type="button"
                    variant="outline"
                    onClick={() =>
                      data.run({
                        type: "deleteMembership",
                        spaceId: params.spaceId,
                        membershipId: membership.id,
                      })
                    }
                  >
                    {t("groups.deleteMembership")}
                  </Button>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      )}
      <form
        className="flex flex-wrap items-end gap-3"
        onSubmit={(event) => {
          event.preventDefault();
          setAsked(true);
        }}
      >
        <TextField label={t("groups.onDate")} type="date" value={onDate} onChange={setOnDate} required />
        <SaveButton label={t("groups.who")} />
      </form>
      {asked ? (
        members.length === 0 ? (
          <p className="text-sm text-muted-foreground">{t("groups.noMembers")}</p>
        ) : (
          <ul className="text-sm">
            {members.map((person) => (
              <li key={person.id}>{person.name}</li>
            ))}
          </ul>
        )
      ) : null}
    </>
  );
}

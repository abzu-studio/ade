"use client";

import Link from "next/link";
import { useState } from "react";
import { useParams } from "next/navigation";
import { buttonVariants } from "@/components/ui/button";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { useSpaceData } from "@/components/ade/space";
import { EmptyState, PageHeader, SaveButton, TextField } from "@/components/ade/widgets";
import { useI18n } from "@/i18n";

export default function GroupsPage() {
  const params = useParams<{ spaceId: string }>();
  const { t } = useI18n();
  const { groups, memberships, run } = useSpaceData(params.spaceId);
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  return (
    <>
      <PageHeader title={t("groups.title")} description={t("groups.empty")} />
      <form
        className="flex flex-wrap items-end gap-3"
        onSubmit={(event) => {
          event.preventDefault();
          const result = run(
            { type: "createGroup", spaceId: params.spaceId, name, description },
            t("common.saved"),
          );
          if (result.ok) {
            setName("");
            setDescription("");
          }
        }}
      >
        <div className="min-w-56 flex-1">
          <TextField label={t("common.name")} value={name} onChange={setName} required />
        </div>
        <div className="min-w-56 flex-1">
          <TextField label={t("common.description")} value={description} onChange={setDescription} />
        </div>
        <SaveButton label={t("groups.add")} />
      </form>
      {groups.length === 0 ? (
        <EmptyState>{t("groups.empty")}</EmptyState>
      ) : (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{t("common.name")}</TableHead>
              <TableHead>{t("groups.members")}</TableHead>
              <TableHead />
            </TableRow>
          </TableHeader>
          <TableBody>
            {groups.map((group) => (
              <TableRow key={group.id}>
                <TableCell>{group.name}</TableCell>
                <TableCell>{memberships.filter((item) => item.groupId === group.id).length}</TableCell>
                <TableCell>
                  <Link
                    href={`/space/${params.spaceId}/groups/${group.id}`}
                    className={buttonVariants({ variant: "outline" })}
                  >
                    {t("action.open")}
                  </Link>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      )}
    </>
  );
}

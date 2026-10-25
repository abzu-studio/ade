"use client";

import { useParams } from "next/navigation";
import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import {
  AlertDialog,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { Input } from "@/components/ui/input";
import { useSpaceData } from "@/components/ade/space";
import { Field, PageHeader, TextField } from "@/components/ade/widgets";
import { BACKUP_FORMAT } from "@/core/types";
import { toBackup, toSyncBundle } from "@/core/transfer";
import { useI18n } from "@/i18n";
import { downloadJson, readJsonFile } from "@/persistence/files";

function isBackup(value: unknown): boolean {
  return typeof value === "object" && value !== null && "format" in value && value.format === BACKUP_FORMAT;
}

export default function DataPage() {
  const params = useParams<{ spaceId: string }>();
  const { t } = useI18n();
  const data = useSpaceData(params.spaceId);
  const [name, setName] = useState(data.db.actor.name);
  const [pending, setPending] = useState<unknown | null>(null);

  useEffect(() => {
    setName(data.db.actor.name);
  }, [data.db.actor.name]);

  return (
    <>
      <PageHeader title={t("data.title")} />
      <form
        className="flex max-w-md flex-col gap-3"
        onSubmit={(event) => {
          event.preventDefault();
          data.run({ type: "setActorName", name }, t("common.saved"));
        }}
      >
        <TextField label={t("data.actor")} value={name} onChange={setName} required />
        <Button type="submit">{t("action.save")}</Button>
      </form>
      <section className="flex max-w-xl flex-col gap-2">
        <h2 className="text-sm font-medium">{t("data.backup")}</h2>
        <p className="text-sm text-muted-foreground">{t("data.backupHelp")}</p>
        <Button
          type="button"
          variant="outline"
          onClick={() => downloadJson("ade-backup.json", toBackup(data.db, new Date().toISOString()))}
        >
          {t("action.export")}
        </Button>
      </section>
      <section className="flex max-w-xl flex-col gap-2">
        <h2 className="text-sm font-medium">{t("data.sync")}</h2>
        <p className="text-sm text-muted-foreground">{t("data.syncHelp")}</p>
        <Button
          type="button"
          variant="outline"
          onClick={() => {
            const bundle = toSyncBundle(data.db, params.spaceId, new Date().toISOString());
            if (!bundle.ok) {
              data.run({ type: "importSync", bundle: null });
              return;
            }
            const filename = `ade-${(data.space?.name ?? "space").replace(/[^\w.-]+/g, "-")}.json`;
            downloadJson(filename, bundle.value);
          }}
        >
          {t("action.export")}
        </Button>
      </section>
      <Field label={t("data.import")}>
        <Input
          type="file"
          accept="application/json,.json"
          onChange={(event) => {
            const file = event.target.files?.[0];
            event.target.value = "";
            if (!file) return;
            void readJsonFile(file)
              .then((json) => {
                if (isBackup(json)) {
                  setPending(json);
                  return;
                }
                data.run({ type: "importSync", bundle: json }, t("data.imported"));
              })
              .catch(() => {
                data.run({ type: "importSync", bundle: null });
              });
          }}
        />
      </Field>
      <AlertDialog open={pending !== null} onOpenChange={(open) => { if (!open) setPending(null); }}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t("data.replaceTitle")}</AlertDialogTitle>
            <AlertDialogDescription>{t("data.replaceHelp")}</AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{t("action.cancel")}</AlertDialogCancel>
            <Button
              type="button"
              onClick={() => {
                const result = data.run({ type: "importBackup", backup: pending }, t("data.imported"));
                if (result.ok) setPending(null);
              }}
            >
              {t("action.import")}
            </Button>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  );
}

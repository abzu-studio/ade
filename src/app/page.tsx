"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { buttonVariants } from "@/components/ui/button";
import { PageHeader, SaveButton, TextField } from "@/components/ade/widgets";
import { useI18n } from "@/i18n";
import { isMacDesktop } from "@/lib/platform";
import { useApp } from "@/state/store";

export default function HomePage() {
  const { t } = useI18n();
  const { db, run } = useApp();
  const [name, setName] = useState("");
  const [mac, setMac] = useState<boolean | null>(null);
  useEffect(() => setMac(isMacDesktop()), []);

  return (
    <main className="mx-auto flex w-full max-w-3xl flex-col gap-6 p-6">
      <PageHeader title={t("app.name")} description={t("app.tagline")} />
      {mac === false ? (
        <Alert>
          <AlertTitle>{t("app.name")}</AlertTitle>
          <AlertDescription>{t("app.macNotice")}</AlertDescription>
        </Alert>
      ) : null}
      <Card>
        <CardHeader>
          <CardTitle>{t("spaces.create")}</CardTitle>
        </CardHeader>
        <CardContent>
          <form
            className="flex flex-wrap items-end gap-3"
            onSubmit={(event) => {
              event.preventDefault();
              const result = run({ type: "createSpace", name }, t("common.saved"));
              if (result.ok) setName("");
            }}
          >
            <div className="min-w-64 flex-1">
              <TextField label={t("common.name")} value={name} onChange={setName} required />
            </div>
            <SaveButton label={t("action.create")} />
          </form>
        </CardContent>
      </Card>
      <div className="flex flex-col gap-2">
        <Button type="button" variant="outline" onClick={() => run({ type: "loadDemo" }, t("common.saved"))}>
          {t("spaces.demo")}
        </Button>
        <p className="text-sm text-muted-foreground">{t("spaces.demoHelp")}</p>
      </div>
      {db.spaces.length === 0 ? (
        <p className="text-sm text-muted-foreground">{t("spaces.empty")}</p>
      ) : (
        <div className="flex flex-col gap-2">
          {db.spaces
            .slice()
            .sort((a, b) => a.name.localeCompare(b.name))
            .map((space) => (
              <Card key={space.id}>
                <CardContent className="flex items-center justify-between gap-3">
                  <span className="font-medium">{space.name}</span>
                  <Link href={`/space/${space.id}`} className={buttonVariants({ variant: "outline" })}>
                    {t("action.open")}
                  </Link>
                </CardContent>
              </Card>
            ))}
        </div>
      )}
    </main>
  );
}

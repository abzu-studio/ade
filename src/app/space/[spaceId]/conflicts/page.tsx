"use client";

import { useParams } from "next/navigation";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { useSpaceData } from "@/components/ade/space";
import { EmptyState, PageHeader } from "@/components/ade/widgets";
import type { ConflictResolution } from "@/core/types";
import { useI18n } from "@/i18n";

function payloadText(value: unknown): string {
  if (value === null || value === undefined) return "";
  return JSON.stringify(value, null, 2);
}

export default function ConflictsPage() {
  const params = useParams<{ spaceId: string }>();
  const { t } = useI18n();
  const data = useSpaceData(params.spaceId);
  const ordered = [...data.conflicts].sort((a, b) => b.createdAt.localeCompare(a.createdAt));

  function resolve(conflictId: string, resolution: Exclude<ConflictResolution, "pending">) {
    data.run(
      { type: "resolveConflict", spaceId: params.spaceId, conflictId, resolution },
      t("common.saved"),
    );
  }

  return (
    <>
      <PageHeader title={t("conflicts.title")} description={t("conflicts.help")} />
      {ordered.length === 0 ? (
        <EmptyState>{t("conflicts.empty")}</EmptyState>
      ) : (
        ordered.map((conflict) => (
          <Card key={conflict.id}>
            <CardHeader>
              <CardTitle className="flex flex-wrap items-center gap-2 text-base">
                <span>
                  {conflict.entityType} · {conflict.key}
                </span>
                <Badge variant={conflict.resolution === "pending" ? "secondary" : "outline"}>
                  {conflict.resolution === "pending"
                    ? t("conflicts.pending")
                    : t("conflicts.resolved")}
                </Badge>
              </CardTitle>
            </CardHeader>
            <CardContent className="grid gap-3 md:grid-cols-2">
              <section className="flex flex-col gap-2">
                <h2 className="text-sm font-medium">{t("conflicts.local")}</h2>
                <pre className="max-h-64 overflow-auto rounded-lg border p-2 text-xs">
                  {payloadText(conflict.local)}
                </pre>
              </section>
              <section className="flex flex-col gap-2">
                <h2 className="text-sm font-medium">{t("conflicts.remote")}</h2>
                {conflict.remoteDeleted ? (
                  <p className="text-sm">{t("conflicts.remoteDeleted")}</p>
                ) : (
                  <pre className="max-h-64 overflow-auto rounded-lg border p-2 text-xs">
                    {payloadText(conflict.remote)}
                  </pre>
                )}
              </section>
              {conflict.resolution === "pending" ? (
                <div className="flex flex-wrap gap-2 md:col-span-2">
                  <Button type="button" variant="outline" onClick={() => resolve(conflict.id, "kept-local")}>
                    {t("conflicts.keepLocal")}
                  </Button>
                  <Button type="button" variant="outline" onClick={() => resolve(conflict.id, "kept-remote")}>
                    {t("conflicts.keepRemote")}
                  </Button>
                  <Button type="button" onClick={() => resolve(conflict.id, "kept-both")}>
                    {t("conflicts.keepBoth")}
                  </Button>
                </div>
              ) : (
                <p className="text-sm text-muted-foreground md:col-span-2">
                  {t(
                    conflict.resolution === "kept-local"
                      ? "conflicts.keepLocal"
                      : conflict.resolution === "kept-remote"
                        ? "conflicts.keepRemote"
                        : "conflicts.keepBoth",
                  )}
                </p>
              )}
            </CardContent>
          </Card>
        ))
      )}
    </>
  );
}

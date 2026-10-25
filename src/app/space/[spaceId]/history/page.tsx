"use client";

import { useParams } from "next/navigation";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { formatWhen, revisionText } from "@/components/ade/labels";
import { useSpaceData } from "@/components/ade/space";
import { EmptyState, PageHeader } from "@/components/ade/widgets";
import { useI18n } from "@/i18n";

export default function HistoryPage() {
  const params = useParams<{ spaceId: string }>();
  const { t, locale } = useI18n();
  const data = useSpaceData(params.spaceId);
  const ids = data.history?.revisionIds ?? [];
  const cursor = data.history?.cursor ?? -1;
  const rows = ids
    .map((id) => data.revisions.find((revision) => revision.id === id))
    .filter((revision) => revision !== undefined);

  return (
    <>
      <PageHeader title={t("history.title")} />
      <Alert>
        <AlertDescription>{t("history.warning")}</AlertDescription>
      </Alert>
      {rows.length === 0 ? (
        <EmptyState>{t("history.empty")}</EmptyState>
      ) : (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{t("common.date")}</TableHead>
              <TableHead>{t("common.description")}</TableHead>
              <TableHead>{t("common.status")}</TableHead>
              <TableHead />
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.map((revision, index) => (
              <TableRow key={revision.id}>
                <TableCell>{formatWhen(revision.at, locale)}</TableCell>
                <TableCell>{revisionText(t, revision)}</TableCell>
                <TableCell>
                  {index === cursor ? <Badge>{t("history.current")}</Badge> : null}
                  {index > cursor ? <Badge variant="outline">{index + 1}</Badge> : null}
                </TableCell>
                <TableCell>
                  {index === cursor ? null : (
                    <Button
                      type="button"
                      variant="outline"
                      onClick={() =>
                        data.run(
                          { type: "restoreRevision", spaceId: params.spaceId, revisionId: revision.id },
                          t("common.saved"),
                        )
                      }
                    >
                      {t("history.restore")}
                    </Button>
                  )}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      )}
    </>
  );
}

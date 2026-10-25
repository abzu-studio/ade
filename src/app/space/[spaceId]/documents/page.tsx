"use client";

import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { Button, buttonVariants } from "@/components/ui/button";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { AssetUploader } from "@/components/ade/assets";
import { useSpaceData } from "@/components/ade/space";
import { EmptyState, PageHeader } from "@/components/ade/widgets";
import { attendanceSummaryElements } from "@/core/documents";
import { useI18n } from "@/i18n";
import { cn } from "@/lib/utils";

export default function DocumentsPage() {
  const params = useParams<{ spaceId: string }>();
  const router = useRouter();
  const { t } = useI18n();
  const data = useSpaceData(params.spaceId);

  function openNewest(result: ReturnType<typeof data.run>) {
    if (!result.ok) return;
    const created = result.value.templates
      .filter((template) => template.spaceId === params.spaceId)
      .reduce<(typeof result.value.templates)[number] | null>(
        (best, template) => (!best || template.createdAt >= best.createdAt ? template : best),
        null,
      );
    if (created) router.push(`/space/${params.spaceId}/documents/${created.id}`);
  }

  return (
    <>
      <PageHeader title={t("documents.title")} description={t("documents.empty")}>
        <Button
          type="button"
          variant="outline"
          onClick={() =>
            openNewest(
              data.run({
                type: "createTemplate",
                spaceId: params.spaceId,
                name: t("documents.add"),
                pageSize: "letter",
                backgroundAssetId: null,
                elements: [],
              }),
            )
          }
        >
          {t("documents.add")}
        </Button>
        <Button
          type="button"
          onClick={() =>
            openNewest(
              data.run(
                {
                  type: "createTemplate",
                  spaceId: params.spaceId,
                  name: t("documents.preset"),
                  pageSize: "letter",
                  backgroundAssetId: null,
                  elements: attendanceSummaryElements(),
                },
                t("common.saved"),
              ),
            )
          }
        >
          {t("documents.preset")}
        </Button>
      </PageHeader>
      <AssetUploader spaceId={params.spaceId} />
      {data.assets.length === 0 ? (
        <EmptyState>{t("documents.noAssets")}</EmptyState>
      ) : (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{t("documents.asset")}</TableHead>
              <TableHead>{t("common.status")}</TableHead>
              <TableHead />
            </TableRow>
          </TableHeader>
          <TableBody>
            {data.assets.map((asset) => (
              <TableRow key={asset.id}>
                <TableCell>{asset.name}</TableCell>
                <TableCell>{asset.mime}</TableCell>
                <TableCell>
                  <Button
                    type="button"
                    variant="outline"
                    onClick={() => data.run({ type: "deleteAsset", spaceId: params.spaceId, assetId: asset.id })}
                  >
                    {t("action.delete")}
                  </Button>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      )}
      {data.templates.length === 0 ? (
        <EmptyState>{t("documents.empty")}</EmptyState>
      ) : (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{t("common.name")}</TableHead>
              <TableHead>{t("documents.pageSize")}</TableHead>
              <TableHead />
            </TableRow>
          </TableHeader>
          <TableBody>
            {data.templates.map((template) => (
              <TableRow key={template.id}>
                <TableCell>{template.name}</TableCell>
                <TableCell>{template.pageSize}</TableCell>
                <TableCell className="flex gap-2">
                  <Link
                    href={`/space/${params.spaceId}/documents/${template.id}`}
                    className={cn(buttonVariants({ variant: "outline" }))}
                  >
                    {t("action.open")}
                  </Link>
                  <Button
                    type="button"
                    variant="outline"
                    onClick={() =>
                      data.run({ type: "deleteTemplate", spaceId: params.spaceId, templateId: template.id })
                    }
                  >
                    {t("action.delete")}
                  </Button>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      )}
    </>
  );
}

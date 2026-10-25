"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import { Button, buttonVariants } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { AssetUploader } from "@/components/ade/assets";
import { documentLabels } from "@/components/ade/labels";
import { useSpaceData } from "@/components/ade/space";
import { Choice, EmptyState, Field, PageHeader, TextField } from "@/components/ade/widgets";
import { planDocument } from "@/core/documents";
import type {
  DocumentTemplate,
  ListBinding,
  PageSize,
  TemplateElement,
  TextAlign,
  TextBinding,
} from "@/core/types";
import { useI18n } from "@/i18n";
import type { MessageKey } from "@/i18n/en";
import { cn } from "@/lib/utils";
import { downloadBytes } from "@/persistence/files";

const textBindings: Array<TextBinding | "none"> = [
  "none",
  "space.name",
  "period.name",
  "period.range",
  "event.title",
  "event.date",
  "event.component",
  "event.category",
  "event.status",
  "group.name",
  "generatedAt",
];

const listBindings: ListBinding[] = [
  "event.participants",
  "event.attendance",
  "event.volunteers",
  "period.participation",
  "group.members",
];

export default function TemplatePage() {
  const params = useParams<{ spaceId: string; templateId: string }>();
  const { t } = useI18n();
  const data = useSpaceData(params.spaceId);
  const template = data.templates.find((item) => item.id === params.templateId) ?? null;
  const [name, setName] = useState(template?.name ?? "");
  const [description, setDescription] = useState(template?.description ?? "");
  const [pageSize, setPageSize] = useState<PageSize>(template?.pageSize ?? "letter");
  const [backgroundAssetId, setBackgroundAssetId] = useState(template?.backgroundAssetId ?? "none");
  const [elements, setElements] = useState<TemplateElement[]>(template?.elements ?? []);
  const [periodId, setPeriodId] = useState(data.periods[0]?.id ?? "none");
  const [eventId, setEventId] = useState(data.events[0]?.id ?? "none");
  const [groupId, setGroupId] = useState("none");

  useEffect(() => {
    if (!template) return;
    setName(template.name);
    setDescription(template.description);
    setPageSize(template.pageSize);
    setBackgroundAssetId(template.backgroundAssetId ?? "none");
    setElements(template.elements);
  }, [template]);

  if (!template) return <EmptyState>{t("error.NOT_FOUND")}</EmptyState>;

  const images = data.assets.filter((asset) => asset.mime === "image/png" || asset.mime === "image/jpeg");
  const pdfs = data.assets.filter((asset) => asset.mime === "application/pdf");

  function update(index: number, next: TemplateElement) {
    setElements((current) => current.map((element, elementIndex) => (elementIndex === index ? next : element)));
  }

  function draftTemplate(): DocumentTemplate {
    return {
      ...template!,
      name,
      description,
      pageSize,
      backgroundAssetId: backgroundAssetId === "none" ? null : backgroundAssetId,
      elements,
    };
  }

  async function generate() {
    const planned = planDocument(
      data.db,
      draftTemplate(),
      {
        spaceId: params.spaceId,
        periodId: periodId === "none" ? null : periodId,
        eventId: eventId === "none" ? null : eventId,
        groupId: groupId === "none" ? null : groupId,
        generatedAt: new Date().toISOString(),
      },
      documentLabels(t),
    );
    if (!planned.ok) {
      toast.error(t(`error.${planned.error.code}` as MessageKey, planned.error.params));
      return;
    }
    try {
      const { renderPdf } = await import("@/lib/pdf/render");
      const bytes = await renderPdf(data.db, planned.value);
      const filename = `${name.replace(/[^\w.-]+/g, "-") || "ade"}.pdf`;
      downloadBytes(filename, bytes, "application/pdf");
      toast.success(t("documents.generated", { count: String(planned.value.length) }));
    } catch (error) {
      toast.error(error instanceof Error ? error.message : t("error.INVALID_TEMPLATE"));
    }
  }

  return (
    <>
      <PageHeader title={template.name} description={t("documents.empty")}>
        <Link
          href={`/space/${params.spaceId}/documents`}
          className={cn(buttonVariants({ variant: "outline" }))}
        >
          {t("nav.documents")}
        </Link>
        <Button
          type="button"
          onClick={() =>
            data.run(
              {
                type: "updateTemplate",
                spaceId: params.spaceId,
                templateId: template.id,
                name,
                description,
                pageSize,
                backgroundAssetId: backgroundAssetId === "none" ? null : backgroundAssetId,
                elements,
              },
              t("common.saved"),
            )
          }
        >
          {t("action.save")}
        </Button>
        <Button type="button" variant="outline" onClick={() => void generate()}>
          {t("documents.generate")}
        </Button>
      </PageHeader>
      <div className="grid max-w-3xl gap-3 md:grid-cols-2">
        <TextField label={t("common.name")} value={name} onChange={setName} required />
        <TextField label={t("common.description")} value={description} onChange={setDescription} />
        <Choice
          label={t("documents.pageSize")}
          value={pageSize}
          onChange={(value) => setPageSize(value as PageSize)}
          options={[
            { value: "letter", label: "Letter" },
            { value: "a4", label: "A4" },
          ]}
        />
        <Choice
          label={t("documents.background")}
          value={backgroundAssetId ?? "none"}
          onChange={setBackgroundAssetId}
          options={[
            { value: "none", label: t("common.none") },
            ...pdfs.map((asset) => ({ value: asset.id, label: asset.name })),
          ]}
        />
      </div>
      <AssetUploader spaceId={params.spaceId} />
      <div className="flex flex-wrap gap-2">
        <Button
          type="button"
          variant="outline"
          onClick={() =>
            setElements((current) => [
              ...current,
              {
                id: crypto.randomUUID(),
                type: "text",
                x: 48,
                y: 48,
                width: 400,
                height: 24,
                text: "",
                binding: null,
                fontSize: 12,
                align: "left",
              },
            ])
          }
        >
          {t("documents.addText")}
        </Button>
        <Button
          type="button"
          variant="outline"
          disabled={images.length === 0}
          onClick={() =>
            setElements((current) => [
              ...current,
              {
                id: crypto.randomUUID(),
                type: "image",
                x: 48,
                y: 80,
                width: 120,
                height: 80,
                assetId: images[0].id,
              },
            ])
          }
        >
          {t("documents.addImage")}
        </Button>
        <Button
          type="button"
          variant="outline"
          onClick={() =>
            setElements((current) => [
              ...current,
              {
                id: crypto.randomUUID(),
                type: "columns",
                x: 48,
                y: 160,
                width: 500,
                height: 400,
                columns: 1,
                gap: 12,
                binding: "period.participation",
                fontSize: 11,
              },
            ])
          }
        >
          {t("documents.addColumns")}
        </Button>
      </div>
      {images.length === 0 ? <p className="text-sm text-muted-foreground">{t("documents.noAssets")}</p> : null}
      <div className="flex flex-col gap-3">
        {elements.map((element, index) => (
          <Card key={element.id}>
            <CardHeader>
              <CardTitle className="flex items-center justify-between gap-2 text-base">
                <span>{element.type}</span>
                <Button
                  type="button"
                  variant="outline"
                  onClick={() => setElements((current) => current.filter((_, elementIndex) => elementIndex !== index))}
                >
                  {t("documents.remove")}
                </Button>
              </CardTitle>
            </CardHeader>
            <CardContent className="grid gap-3 md:grid-cols-4">
              <Field label={t("documents.x")}>
                <Input
                  type="number"
                  value={element.x}
                  onChange={(input) => update(index, { ...element, x: Number(input.target.value) })}
                />
              </Field>
              <Field label={t("documents.y")}>
                <Input
                  type="number"
                  value={element.y}
                  onChange={(input) => update(index, { ...element, y: Number(input.target.value) })}
                />
              </Field>
              <Field label={t("documents.width")}>
                <Input
                  type="number"
                  value={element.width}
                  onChange={(input) => update(index, { ...element, width: Number(input.target.value) })}
                />
              </Field>
              <Field label={t("documents.height")}>
                <Input
                  type="number"
                  value={element.height}
                  onChange={(input) => update(index, { ...element, height: Number(input.target.value) })}
                />
              </Field>
              {element.type === "text" ? (
                <>
                  <TextField
                    label={t("documents.literal")}
                    value={element.text}
                    onChange={(value) => update(index, { ...element, text: value })}
                  />
                  <Choice
                    label={t("documents.binding")}
                    value={element.binding ?? "none"}
                    onChange={(value) =>
                      update(index, { ...element, binding: value === "none" ? null : (value as TextBinding) })
                    }
                    options={textBindings.map((binding) => ({
                      value: binding,
                      label: t((binding === "none" ? "binding.none" : `binding.${binding}`) as MessageKey),
                    }))}
                  />
                  <Field label={t("documents.fontSize")}>
                    <Input
                      type="number"
                      value={element.fontSize}
                      onChange={(input) => update(index, { ...element, fontSize: Number(input.target.value) })}
                    />
                  </Field>
                  <Choice
                    label={t("documents.align")}
                    value={element.align}
                    onChange={(value) => update(index, { ...element, align: value as TextAlign })}
                    options={[
                      { value: "left", label: t("documents.left") },
                      { value: "center", label: t("documents.center") },
                      { value: "right", label: t("documents.right") },
                    ]}
                  />
                </>
              ) : null}
              {element.type === "image" ? (
                <Choice
                  label={t("documents.asset")}
                  value={element.assetId}
                  onChange={(value) => update(index, { ...element, assetId: value })}
                  options={images.map((asset) => ({ value: asset.id, label: asset.name }))}
                />
              ) : null}
              {element.type === "columns" ? (
                <>
                  <Choice
                    label={t("documents.listBinding")}
                    value={element.binding}
                    onChange={(value) => update(index, { ...element, binding: value as ListBinding })}
                    options={listBindings.map((binding) => ({
                      value: binding,
                      label: t(`list.${binding}` as MessageKey),
                    }))}
                  />
                  <Field label={t("documents.columnsCount")}>
                    <Input
                      type="number"
                      value={element.columns}
                      onChange={(input) => update(index, { ...element, columns: Number(input.target.value) })}
                    />
                  </Field>
                  <Field label={t("documents.gap")}>
                    <Input
                      type="number"
                      value={element.gap}
                      onChange={(input) => update(index, { ...element, gap: Number(input.target.value) })}
                    />
                  </Field>
                  <Field label={t("documents.fontSize")}>
                    <Input
                      type="number"
                      value={element.fontSize}
                      onChange={(input) => update(index, { ...element, fontSize: Number(input.target.value) })}
                    />
                  </Field>
                </>
              ) : null}
            </CardContent>
          </Card>
        ))}
      </div>
      <Card>
        <CardHeader>
          <CardTitle>{t("documents.context")}</CardTitle>
        </CardHeader>
        <CardContent className="grid gap-3 md:grid-cols-3">
          <Choice
            label={t("nav.periods")}
            value={periodId}
            onChange={setPeriodId}
            options={[
              { value: "none", label: t("common.none") },
              ...data.periods.map((period) => ({ value: period.id, label: period.name })),
            ]}
          />
          <Choice
            label={t("nav.events")}
            value={eventId}
            onChange={setEventId}
            options={[
              { value: "none", label: t("common.none") },
              ...data.events.map((event) => ({ value: event.id, label: `${event.date} ${event.title}` })),
            ]}
          />
          <Choice
            label={t("nav.groups")}
            value={groupId}
            onChange={setGroupId}
            options={[
              { value: "none", label: t("common.none") },
              ...data.groups.map((group) => ({ value: group.id, label: group.name })),
            ]}
          />
        </CardContent>
      </Card>
    </>
  );
}

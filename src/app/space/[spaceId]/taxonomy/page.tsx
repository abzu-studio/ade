"use client";

import { useState } from "react";
import { useParams } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { useSpaceData } from "@/components/ade/space";
import { Choice, EmptyState, PageHeader, SaveButton, TextField } from "@/components/ade/widgets";
import { useI18n } from "@/i18n";

export default function TaxonomyPage() {
  const params = useParams<{ spaceId: string }>();
  const { t } = useI18n();
  const { components, categories, run } = useSpaceData(params.spaceId);
  const [componentName, setComponentName] = useState("");
  const [categoryName, setCategoryName] = useState("");
  const [componentId, setComponentId] = useState<string | null>(components[0]?.id ?? null);
  return (
    <>
      <PageHeader title={t("taxonomy.title")} description={t("taxonomy.empty")} />
      <form
        className="flex flex-wrap items-end gap-3"
        onSubmit={(event) => {
          event.preventDefault();
          const result = run(
            { type: "createComponent", spaceId: params.spaceId, name: componentName },
            t("common.saved"),
          );
          if (result.ok) setComponentName("");
        }}
      >
        <div className="min-w-64 flex-1">
          <TextField label={t("taxonomy.component")} value={componentName} onChange={setComponentName} required />
        </div>
        <SaveButton label={t("taxonomy.addComponent")} />
      </form>
      {components.length === 0 ? (
        <EmptyState>{t("taxonomy.empty")}</EmptyState>
      ) : (
        <div className="flex flex-col gap-3">
          {components.map((component) => (
            <Card key={component.id}>
              <CardHeader className="flex-row items-center justify-between">
                <CardTitle>{component.name}</CardTitle>
                <Button
                  type="button"
                  variant="outline"
                  onClick={() =>
                    run({ type: "deleteComponent", spaceId: params.spaceId, componentId: component.id })
                  }
                >
                  {t("action.delete")}
                </Button>
              </CardHeader>
              <CardContent className="flex flex-col gap-2">
                {categories
                  .filter((category) => category.componentId === component.id)
                  .map((category) => (
                    <div key={category.id} className="flex items-center justify-between gap-2 text-sm">
                      <span>{category.name}</span>
                      <Button
                        type="button"
                        variant="ghost"
                        onClick={() =>
                          run({ type: "deleteCategory", spaceId: params.spaceId, categoryId: category.id })
                        }
                      >
                        {t("action.delete")}
                      </Button>
                    </div>
                  ))}
              </CardContent>
            </Card>
          ))}
        </div>
      )}
      {components.length > 0 ? (
        <form
          className="flex flex-wrap items-end gap-3"
          onSubmit={(event) => {
            event.preventDefault();
            if (!componentId) return;
            const result = run(
              { type: "createCategory", spaceId: params.spaceId, componentId, name: categoryName },
              t("common.saved"),
            );
            if (result.ok) setCategoryName("");
          }}
        >
          <Choice
            label={t("taxonomy.component")}
            value={componentId}
            onChange={setComponentId}
            options={components.map((component) => ({ value: component.id, label: component.name }))}
          />
          <div className="min-w-56 flex-1">
            <TextField label={t("taxonomy.category")} value={categoryName} onChange={setCategoryName} required />
          </div>
          <SaveButton label={t("taxonomy.addCategory")} />
        </form>
      ) : null}
    </>
  );
}

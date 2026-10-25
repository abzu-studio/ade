"use client";

import { toast } from "sonner";
import { Input } from "@/components/ui/input";
import { useSpaceData } from "@/components/ade/space";
import { Field } from "@/components/ade/widgets";
import { useI18n } from "@/i18n";
import { assetMime, fileToBase64 } from "@/persistence/files";

export function AssetUploader({ spaceId }: { spaceId: string }) {
  const { t } = useI18n();
  const { run } = useSpaceData(spaceId);
  return (
    <Field label={t("documents.upload")}>
      <Input
        type="file"
        accept="image/png,image/jpeg,.png,.jpg,.jpeg,application/pdf,.pdf"
        onChange={(event) => {
          const file = event.target.files?.[0];
          event.target.value = "";
          if (!file) return;
          const mime = assetMime(file);
          if (!mime) {
            toast.error(t("documents.noAssets"));
            return;
          }
          void fileToBase64(file).then((dataBase64) => {
            run(
              { type: "addAsset", spaceId, name: file.name, mime, dataBase64 },
              t("common.saved"),
            );
          });
        }}
      />
    </Field>
  );
}

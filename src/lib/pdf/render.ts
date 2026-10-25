import { PDFDocument, StandardFonts, rgb } from "pdf-lib";
import type { Database, PlannedPage } from "@/core/types";

export function decodeBase64(data: string): Uint8Array {
  const binary = atob(data);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

export function encodeBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function pdfSafe(text: string): string {
  let safe = "";
  for (const character of text) {
    const code = character.codePointAt(0) ?? 0;
    safe += code >= 32 && code <= 255 ? character : "?";
  }
  return safe;
}

export async function renderPdf(db: Database, pages: PlannedPage[]): Promise<Uint8Array> {
  const document = await PDFDocument.create();
  const font = await document.embedFont(StandardFonts.Helvetica);
  for (const planned of pages) {
    const page = document.addPage([planned.width, planned.height]);
    if (planned.backgroundAssetId) {
      const asset = db.assets.find(
        (item) => item.id === planned.backgroundAssetId && !item.deletedAt,
      );
      if (!asset || asset.mime !== "application/pdf") {
        throw new Error("Missing background PDF");
      }
      const background = await PDFDocument.load(decodeBase64(asset.dataBase64));
      const index = Math.min(planned.backgroundPageIndex, Math.max(0, background.getPageCount() - 1));
      const embedded = await document.embedPage(background.getPages()[index]);
      page.drawPage(embedded, {
        x: 0,
        y: 0,
        width: planned.width,
        height: planned.height,
      });
    }
    for (const item of planned.items) {
      if (item.kind === "image") {
        const asset = db.assets.find((entry) => entry.id === item.assetId && !entry.deletedAt);
        if (!asset) continue;
        const bytes = decodeBase64(asset.dataBase64);
        const image =
          asset.mime === "image/jpeg"
            ? await document.embedJpg(bytes)
            : await document.embedPng(bytes);
        page.drawImage(image, {
          x: item.x,
          y: planned.height - item.y - item.height,
          width: item.width,
          height: item.height,
        });
        continue;
      }
      const text = pdfSafe(item.text);
      let width = 0;
      try {
        width = font.widthOfTextAtSize(text, item.fontSize);
      } catch {
        width = font.widthOfTextAtSize(text.replace(/[^\x20-\x7E]/g, "?"), item.fontSize);
      }
      let x = item.x;
      if (item.align === "center") x += Math.max(0, (item.width - width) / 2);
      if (item.align === "right") x += Math.max(0, item.width - width);
      const draw = (value: string) => {
        page.drawText(value, {
          x,
          y: planned.height - item.y - item.fontSize,
          size: item.fontSize,
          font,
          color: rgb(0, 0, 0),
          maxWidth: item.width,
        });
      };
      try {
        draw(text);
      } catch {
        draw(text.replace(/[^\x20-\x7E]/g, "?"));
      }
    }
  }
  return document.save();
}

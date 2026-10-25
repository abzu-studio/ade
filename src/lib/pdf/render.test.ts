import { PDFDocument, StandardFonts } from "pdf-lib";
import { describe, expect, it } from "vitest";
import { createEmptyDatabase, dispatch } from "@/core/reduce";
import { planDocument } from "@/core/documents";
import type { ReduceContext } from "@/core/types";
import { encodeBase64, renderPdf } from "@/lib/pdf/render";

const PNG =
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==";

describe("pdf renderer", () => {
  it("builds a multi-page PDF with text, an image, columns, and a background", async () => {
    let serial = 0;
    const ctx: ReduceContext = {
      now: "2026-06-15T15:00:00.000Z",
      actorId: "actor-1",
      newId: () => `pdf-${++serial}`,
    };
    let db = createEmptyDatabase(ctx.actorId, ctx.now);
    const act = (action: Parameters<typeof dispatch>[1]) => {
      const result = dispatch(db, action, ctx);
      if (!result.ok) throw new Error(result.error.code);
      db = result.value;
    };
    act({ type: "loadDemo" });
    const spaceId = db.spaces[0].id;
    const periodId = db.periods[0].id;
    const background = await PDFDocument.create();
    const backgroundPage = background.addPage([612, 792]);
    backgroundPage.drawText("background", {
      x: 24,
      y: 24,
      size: 12,
      font: await background.embedFont(StandardFonts.Helvetica),
    });
    const backgroundBytes = await background.save();
    act({
      type: "addAsset",
      spaceId,
      name: "Background",
      mime: "application/pdf",
      dataBase64: encodeBase64(backgroundBytes),
    });
    act({
      type: "addAsset",
      spaceId,
      name: "Mark",
      mime: "image/png",
      dataBase64: PNG,
    });
    const [backgroundAsset, image] = db.assets;
    act({
      type: "createTemplate",
      spaceId,
      name: "Pack",
      pageSize: "letter",
      backgroundAssetId: backgroundAsset.id,
      elements: [
        {
          type: "text",
          x: 48,
          y: 36,
          width: 200,
          height: 20,
          text: "José Niño",
          binding: null,
          fontSize: 14,
          align: "left",
        },
        {
          type: "image",
          x: 48,
          y: 64,
          width: 24,
          height: 24,
          assetId: image.id,
        },
        {
          type: "columns",
          x: 48,
          y: 100,
          width: 180,
          height: 20,
          columns: 1,
          gap: 0,
          binding: "period.participation",
          fontSize: 11,
        },
      ],
    });
    const planned = planDocument(db, db.templates[0], {
      spaceId,
      periodId,
      eventId: null,
      groupId: null,
      generatedAt: ctx.now,
    });
    if (!planned.ok) throw new Error(planned.error.code);
    expect(planned.value.length).toBeGreaterThan(1);
    const bytes = await renderPdf(db, planned.value);
    expect(Buffer.from(bytes.subarray(0, 4)).toString("utf8")).toBe("%PDF");
    const loaded = await PDFDocument.load(bytes);
    expect(loaded.getPageCount()).toBe(planned.value.length);
  });
});

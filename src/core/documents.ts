import { attendanceByPerson, formatPercent } from "@/core/attendance";
import { PAGE_SIZES } from "@/core/constants";
import { err, ok, type Result } from "@/core/result";
import { membersAt } from "@/core/groups";
import type {
  Database,
  DocumentLabels,
  DocumentTemplate,
  EventStatus,
  ListBinding,
  PlannedImage,
  PlannedPage,
  PlannedText,
  TemplateColumnsElement,
  TemplateDataContext,
  TemplateElement,
  TemplateTextElement,
  TextBinding,
} from "@/core/types";

export const DEFAULT_DOCUMENT_LABELS: DocumentLabels = {
  unrecorded: "unrecorded",
  attendance: {
    present: "present",
    absent: "absent",
    excused: "excused",
    pending: "pending",
  },
  volunteer: {
    interested: "interested",
    selected: "selected",
    completed: "completed",
    declined: "declined",
    absent: "absent",
  },
  eventStatus: {
    draft: "draft",
    scheduled: "scheduled",
    completed: "completed",
    cancelled: "cancelled",
  },
  percent: formatPercent,
  counts: (present, absent) => `${present}/${present + absent}`,
  separator: " - ",
};

export function attendanceSummaryElements(): Array<
  Omit<TemplateTextElement, "id"> | Omit<TemplateColumnsElement, "id">
> {
  return [
    {
      type: "text",
      x: 48,
      y: 48,
      width: 516,
      height: 28,
      text: "Attendance summary",
      binding: null,
      fontSize: 18,
      align: "left",
    },
    {
      type: "text",
      x: 48,
      y: 84,
      width: 516,
      height: 18,
      text: "",
      binding: "space.name",
      fontSize: 12,
      align: "left",
    },
    {
      type: "text",
      x: 48,
      y: 106,
      width: 250,
      height: 18,
      text: "",
      binding: "period.name",
      fontSize: 12,
      align: "left",
    },
    {
      type: "text",
      x: 310,
      y: 106,
      width: 254,
      height: 18,
      text: "",
      binding: "period.range",
      fontSize: 12,
      align: "right",
    },
    {
      type: "columns",
      x: 48,
      y: 140,
      width: 516,
      height: 600,
      columns: 2,
      gap: 16,
      binding: "period.participation",
      fontSize: 11,
    },
  ];
}

function personName(db: Database, personId: string): string {
  return db.people.find((person) => person.id === personId)?.name ?? personId;
}

function resolveText(
  db: Database,
  context: TemplateDataContext,
  labels: DocumentLabels,
  binding: TextBinding | null,
  literal: string,
): string {
  if (!binding) return literal;
  const space = db.spaces.find((item) => item.id === context.spaceId);
  const period = context.periodId
    ? db.periods.find((item) => item.id === context.periodId)
    : undefined;
  const event = context.eventId
    ? db.events.find((item) => item.id === context.eventId)
    : undefined;
  const group = context.groupId
    ? db.groups.find((item) => item.id === context.groupId)
    : undefined;
  switch (binding) {
    case "space.name":
      return space?.name ?? "";
    case "period.name":
      return period?.name ?? "";
    case "period.range":
      return period ? `${period.startDate} - ${period.endDate}` : "";
    case "event.title":
      return event?.title ?? "";
    case "event.date":
      return event?.date ?? "";
    case "event.component":
      return (
        db.components.find((item) => item.id === event?.componentId)?.name ?? ""
      );
    case "event.category":
      return (
        db.categories.find((item) => item.id === event?.categoryId)?.name ?? ""
      );
    case "event.status":
      return event ? labels.eventStatus[event.status as EventStatus] : "";
    case "group.name":
      return group?.name ?? "";
    case "generatedAt":
      return context.generatedAt;
    default:
      return literal;
  }
}

function memberDate(db: Database, context: TemplateDataContext): string {
  if (context.periodId) {
    const period = db.periods.find((item) => item.id === context.periodId);
    if (period) return period.endDate;
  }
  if (context.eventId) {
    const event = db.events.find((item) => item.id === context.eventId);
    if (event) return event.date;
  }
  return context.generatedAt.slice(0, 10);
}

function resolveList(
  db: Database,
  context: TemplateDataContext,
  labels: DocumentLabels,
  binding: ListBinding,
): string[] {
  if (binding === "event.participants" || binding === "event.attendance" || binding === "event.volunteers") {
    const event = context.eventId
      ? db.events.find((item) => item.id === context.eventId)
      : undefined;
    if (!event) return [];
    if (binding === "event.participants") {
      return event.participantIds.map((personId) => personName(db, personId));
    }
    if (binding === "event.attendance") {
      return event.participantIds.map((personId) => {
        const record = db.attendance.find(
          (item) => item.eventId === event.id && item.personId === personId,
        );
        const state = record
          ? labels.attendance[record.state]
          : labels.unrecorded;
        return `${personName(db, personId)}${labels.separator}${state}`;
      });
    }
    return db.volunteering
      .filter((record) => record.eventId === event.id)
      .map(
        (record) =>
          `${personName(db, record.personId)}${labels.separator}${labels.volunteer[record.state]}`,
      );
  }
  if (binding === "period.participation") {
    if (!context.periodId) return [];
    return attendanceByPerson(db, {
      spaceId: context.spaceId,
      periodId: context.periodId,
      groupId: context.groupId,
    }).map(({ person, breakdown }) => {
      return `${person.name}${labels.separator}${labels.percent(breakdown.percentage)} (${labels.counts(breakdown.present, breakdown.absent)})`;
    });
  }
  if (!context.groupId) return [];
  return membersAt(db, context.groupId, memberDate(db, context)).map(
    (person) => person.name,
  );
}

function truncate(text: string, fontSize: number, width: number): string {
  const maxChars = Math.max(1, Math.floor(width / (fontSize * 0.5)));
  if (text.length <= maxChars) return text;
  if (maxChars === 1) return ".";
  return `${text.slice(0, maxChars - 3)}...`;
}

function columnCapacity(height: number, fontSize: number): number {
  return Math.max(1, Math.floor(height / (fontSize * 1.35)));
}

export function validateElements(
  db: Database,
  spaceId: string,
  elements: TemplateElement[],
  backgroundAssetId: string | null,
): Result<true> {
  if (backgroundAssetId) {
    const asset = db.assets.find((item) => item.id === backgroundAssetId);
    if (!asset || asset.spaceId !== spaceId || asset.deletedAt || asset.mime !== "application/pdf") {
      return err("ASSET_NOT_FOUND");
    }
  }
  for (const element of elements) {
    if (
      !Number.isFinite(element.x) ||
      !Number.isFinite(element.y) ||
      !Number.isFinite(element.width) ||
      !Number.isFinite(element.height) ||
      element.width <= 0 ||
      element.height <= 0
    ) {
      return err("INVALID_TEMPLATE");
    }
    if (element.type === "text" && element.fontSize <= 0) return err("INVALID_TEMPLATE");
    if (element.type === "columns") {
      if (
        !Number.isInteger(element.columns) ||
        element.columns < 1 ||
        element.gap < 0 ||
        element.fontSize <= 0
      ) {
        return err("INVALID_TEMPLATE");
      }
    }
    if (element.type === "image") {
      const asset = db.assets.find((item) => item.id === element.assetId);
      if (
        !asset ||
        asset.spaceId !== spaceId ||
        asset.deletedAt ||
        (asset.mime !== "image/png" && asset.mime !== "image/jpeg")
      ) {
        return err("ASSET_NOT_FOUND");
      }
    }
  }
  return ok(true);
}

export function planDocument(
  db: Database,
  template: DocumentTemplate,
  context: TemplateDataContext,
  labels: DocumentLabels = DEFAULT_DOCUMENT_LABELS,
): Result<PlannedPage[]> {
  if (template.spaceId !== context.spaceId) return err("NOT_FOUND");
  const valid = validateElements(
    db,
    template.spaceId,
    template.elements,
    template.backgroundAssetId,
  );
  if (!valid.ok) return valid;
  const page = PAGE_SIZES[template.pageSize];
  const staticItems: Array<PlannedText | PlannedImage> = [];
  for (const element of template.elements) {
    if (element.type === "text") {
      staticItems.push({
        kind: "text",
        x: element.x,
        y: element.y,
        width: element.width,
        height: element.height,
        text: resolveText(db, context, labels, element.binding, element.text),
        fontSize: element.fontSize,
        align: element.align,
      });
    } else if (element.type === "image") {
      staticItems.push({
        kind: "image",
        x: element.x,
        y: element.y,
        width: element.width,
        height: element.height,
        assetId: element.assetId,
      });
    }
  }

  const flows = template.elements.filter((element) => element.type === "columns");
  const pageCount = Math.max(
    1,
    ...flows.map((element) => {
      const items = resolveList(db, context, labels, element.binding);
      const perColumn = columnCapacity(element.height, element.fontSize);
      const perPage = perColumn * element.columns;
      return Math.max(1, Math.ceil(items.length / perPage));
    }),
  );

  const pages: PlannedPage[] = [];
  for (let pageIndex = 0; pageIndex < pageCount; pageIndex += 1) {
    const items = [...staticItems];
    for (const element of flows) {
      const lines = resolveList(db, context, labels, element.binding).map((line) =>
        truncate(line, element.fontSize, columnWidth(element.width, element.columns, element.gap)),
      );
      const perColumn = columnCapacity(element.height, element.fontSize);
      const perPage = perColumn * element.columns;
      const slice = lines.slice(pageIndex * perPage, (pageIndex + 1) * perPage);
      const colWidth = columnWidth(element.width, element.columns, element.gap);
      const lineHeight = element.fontSize * 1.35;
      slice.forEach((line, index) => {
        const column = Math.floor(index / perColumn);
        const row = index % perColumn;
        items.push({
          kind: "text",
          x: element.x + column * (colWidth + element.gap),
          y: element.y + row * lineHeight,
          width: colWidth,
          height: lineHeight,
          text: line,
          fontSize: element.fontSize,
          align: "left",
        });
      });
    }
    pages.push({
      width: page.width,
      height: page.height,
      backgroundAssetId: template.backgroundAssetId,
      backgroundPageIndex: pageIndex,
      items,
    });
  }
  return ok(pages);
}

function columnWidth(width: number, columns: number, gap: number): number {
  return (width - gap * (columns - 1)) / columns;
}

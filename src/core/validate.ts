import { isIsoDate, isIsoDateTime } from "@/core/dates";
import { err, ok, type Result } from "@/core/result";
import {
  BACKUP_FORMAT,
  DATABASE_FORMAT,
  SYNC_FORMAT,
  type ActivityComponent,
  type TextBinding,
  type AdeEvent,
  type Asset,
  type AssetMime,
  type AttendanceRecord,
  type AttendanceState,
  type BackupFile,
  type Category,
  type ConflictRecord,
  type ConflictResolution,
  type Database,
  type DocumentTemplate,
  type EntityType,
  type EventStatus,
  type Group,
  type GroupMembership,
  type Locale,
  type PageSize,
  type Period,
  type Person,
  type PersonStatus,
  type Revision,
  type Space,
  type SpaceHistory,
  type SpaceSnapshot,
  type SyncBundle,
  type TemplateElement,
  type Tombstone,
  type VolunteerRecord,
  type VolunteerState,
} from "@/core/types";

const ENTITY_TYPES: readonly EntityType[] = [
  "space",
  "person",
  "group",
  "membership",
  "period",
  "component",
  "category",
  "event",
  "attendance",
  "volunteering",
  "template",
  "asset",
];
const ATTENDANCE: readonly AttendanceState[] = ["present", "absent", "excused", "pending"];
const VOLUNTEER: readonly VolunteerState[] = [
  "interested",
  "selected",
  "completed",
  "declined",
  "absent",
];
const EVENT_STATUS: readonly EventStatus[] = ["draft", "scheduled", "completed", "cancelled"];
const RESOLUTIONS: readonly ConflictResolution[] = [
  "pending",
  "kept-local",
  "kept-remote",
  "kept-both",
];
const MIMES: readonly AssetMime[] = ["image/png", "image/jpeg", "application/pdf"];
const TEXT_BINDINGS = [
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
] as const;
const LIST_BINDINGS = [
  "event.participants",
  "event.attendance",
  "event.volunteers",
  "period.participation",
  "group.members",
] as const;

function rec(value: unknown): Record<string, unknown> | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  return value as Record<string, unknown>;
}

function str(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

function bool(value: unknown): boolean | null {
  return typeof value === "boolean" ? value : null;
}

function num(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function strMap(value: unknown): Record<string, string> | null {
  const record = rec(value);
  if (!record) return null;
  const out: Record<string, string> = {};
  for (const [key, entry] of Object.entries(record)) {
    if (typeof entry !== "string") return null;
    out[key] = entry;
  }
  return out;
}

function readArray<T>(
  value: unknown,
  read: (item: unknown) => T | null,
): T[] | null {
  if (!Array.isArray(value)) return null;
  const items: T[] = [];
  for (const item of value) {
    const parsed = read(item);
    if (!parsed) return null;
    items.push(parsed);
  }
  return items;
}

function stamp(record: Record<string, unknown>): { createdAt: string; updatedAt: string } | null {
  const createdAt = str(record.createdAt);
  const updatedAt = str(record.updatedAt);
  if (!createdAt || !updatedAt || !isIsoDateTime(createdAt) || !isIsoDateTime(updatedAt)) {
    return null;
  }
  return { createdAt, updatedAt };
}

function readSpace(value: unknown): Space | null {
  const record = rec(value);
  if (!record) return null;
  const id = str(record.id);
  const name = str(record.name);
  const times = stamp(record);
  if (!id || !name?.trim() || !times) return null;
  return { id, name, ...times };
}

function readPerson(value: unknown): Person | null {
  const record = rec(value);
  if (!record) return null;
  const id = str(record.id);
  const spaceId = str(record.spaceId);
  const name = str(record.name);
  const email = str(record.email);
  const notes = str(record.notes);
  const status = str(record.status);
  const times = stamp(record);
  if (!id || !spaceId || !name || email === null || notes === null || !times) return null;
  if (status !== "active" && status !== "inactive") return null;
  return { id, spaceId, name, email, notes, status: status as PersonStatus, ...times };
}

function readGroup(value: unknown): Group | null {
  const record = rec(value);
  if (!record) return null;
  const id = str(record.id);
  const spaceId = str(record.spaceId);
  const name = str(record.name);
  const description = str(record.description);
  const times = stamp(record);
  if (!id || !spaceId || !name || description === null || !times) return null;
  return { id, spaceId, name, description, ...times };
}

function readMembership(value: unknown): GroupMembership | null {
  const record = rec(value);
  if (!record) return null;
  const id = str(record.id);
  const spaceId = str(record.spaceId);
  const groupId = str(record.groupId);
  const personId = str(record.personId);
  const startDate = str(record.startDate);
  const endDate = record.endDate === null ? null : str(record.endDate);
  const times = stamp(record);
  if (!id || !spaceId || !groupId || !personId || !startDate || endDate === undefined || !times) {
    return null;
  }
  if (!isIsoDate(startDate) || (endDate !== null && !isIsoDate(endDate))) return null;
  return { id, spaceId, groupId, personId, startDate, endDate, ...times };
}

function readPeriod(value: unknown): Period | null {
  const record = rec(value);
  if (!record) return null;
  const id = str(record.id);
  const spaceId = str(record.spaceId);
  const name = str(record.name);
  const startDate = str(record.startDate);
  const endDate = str(record.endDate);
  const times = stamp(record);
  if (!id || !spaceId || !name || !startDate || !endDate || !times) return null;
  if (!isIsoDate(startDate) || !isIsoDate(endDate)) return null;
  return { id, spaceId, name, startDate, endDate, ...times };
}

function readComponent(value: unknown): ActivityComponent | null {
  const record = rec(value);
  if (!record) return null;
  const id = str(record.id);
  const spaceId = str(record.spaceId);
  const name = str(record.name);
  const description = str(record.description);
  const times = stamp(record);
  if (!id || !spaceId || !name || description === null || !times) return null;
  return { id, spaceId, name, description, ...times };
}

function readCategory(value: unknown): Category | null {
  const record = rec(value);
  if (!record) return null;
  const id = str(record.id);
  const spaceId = str(record.spaceId);
  const componentId = str(record.componentId);
  const name = str(record.name);
  const description = str(record.description);
  const times = stamp(record);
  if (!id || !spaceId || !componentId || !name || description === null || !times) return null;
  return { id, spaceId, componentId, name, description, ...times };
}

function readEvent(value: unknown): AdeEvent | null {
  const record = rec(value);
  if (!record) return null;
  const id = str(record.id);
  const spaceId = str(record.spaceId);
  const title = str(record.title);
  const description = str(record.description);
  const date = str(record.date);
  const componentId = str(record.componentId);
  const categoryId = record.categoryId === null ? null : str(record.categoryId);
  const participantIds = readArray(record.participantIds, (item) => str(item));
  const capacity = record.capacity === null ? null : num(record.capacity);
  const countsForAttendance = bool(record.countsForAttendance);
  const status = str(record.status);
  const volunteerCapacity = record.volunteerCapacity === null ? null : num(record.volunteerCapacity);
  const duplicatedFromId = record.duplicatedFromId === null ? null : str(record.duplicatedFromId);
  const times = stamp(record);
  if (
    !id ||
    !spaceId ||
    !title ||
    description === null ||
    !date ||
    !componentId ||
    categoryId === undefined ||
    !participantIds ||
    capacity === undefined ||
    countsForAttendance === null ||
    !status ||
    volunteerCapacity === undefined ||
    duplicatedFromId === undefined ||
    !times ||
    !isIsoDate(date) ||
    !EVENT_STATUS.includes(status as EventStatus)
  ) {
    return null;
  }
  return {
    id,
    spaceId,
    title,
    description,
    date,
    componentId,
    categoryId,
    participantIds,
    capacity,
    countsForAttendance,
    status: status as EventStatus,
    volunteerCapacity,
    duplicatedFromId,
    ...times,
  };
}

function readAttendance(value: unknown): AttendanceRecord | null {
  const record = rec(value);
  if (!record) return null;
  const id = str(record.id);
  const spaceId = str(record.spaceId);
  const eventId = str(record.eventId);
  const personId = str(record.personId);
  const state = str(record.state);
  const note = str(record.note);
  const times = stamp(record);
  const history = readArray(record.history, (item) => {
    const entry = rec(item);
    if (!entry) return null;
    const at = str(entry.at);
    const actorId = str(entry.actorId);
    const previousState = entry.previousState === null ? null : str(entry.previousState);
    const nextState = str(entry.nextState);
    const previousNote = str(entry.previousNote);
    const nextNote = str(entry.nextNote);
    if (!at || !actorId || previousState === undefined || !nextState || previousNote === null || nextNote === null) {
      return null;
    }
    if (!ATTENDANCE.includes(nextState as AttendanceState)) return null;
    if (previousState !== null && !ATTENDANCE.includes(previousState as AttendanceState)) return null;
    return {
      at,
      actorId,
      previousState: previousState as AttendanceState | null,
      nextState: nextState as AttendanceState,
      previousNote,
      nextNote,
    };
  });
  if (!id || !spaceId || !eventId || !personId || !state || note === null || !history || !times) {
    return null;
  }
  if (!ATTENDANCE.includes(state as AttendanceState)) return null;
  return {
    id,
    spaceId,
    eventId,
    personId,
    state: state as AttendanceState,
    note,
    history,
    ...times,
  };
}

function readVolunteer(value: unknown): VolunteerRecord | null {
  const record = rec(value);
  if (!record) return null;
  const id = str(record.id);
  const spaceId = str(record.spaceId);
  const eventId = str(record.eventId);
  const personId = str(record.personId);
  const state = str(record.state);
  const note = str(record.note);
  const times = stamp(record);
  const history = readArray(record.history, (item) => {
    const entry = rec(item);
    if (!entry) return null;
    const at = str(entry.at);
    const actorId = str(entry.actorId);
    const previousState = entry.previousState === null ? null : str(entry.previousState);
    const nextState = str(entry.nextState);
    const previousNote = str(entry.previousNote);
    const nextNote = str(entry.nextNote);
    if (!at || !actorId || previousState === undefined || !nextState || previousNote === null || nextNote === null) {
      return null;
    }
    if (!VOLUNTEER.includes(nextState as VolunteerState)) return null;
    if (previousState !== null && !VOLUNTEER.includes(previousState as VolunteerState)) return null;
    return {
      at,
      actorId,
      previousState: previousState as VolunteerState | null,
      nextState: nextState as VolunteerState,
      previousNote,
      nextNote,
    };
  });
  if (!id || !spaceId || !eventId || !personId || !state || note === null || !history || !times) {
    return null;
  }
  if (!VOLUNTEER.includes(state as VolunteerState)) return null;
  return { id, spaceId, eventId, personId, state: state as VolunteerState, note, history, ...times };
}

function readElement(value: unknown): TemplateElement | null {
  const record = rec(value);
  if (!record) return null;
  const id = str(record.id);
  const type = str(record.type);
  const x = num(record.x);
  const y = num(record.y);
  const width = num(record.width);
  const height = num(record.height);
  if (!id || !type || x === null || y === null || width === null || height === null) return null;
  if (type === "text") {
    const text = str(record.text);
    const binding = record.binding === null ? null : str(record.binding);
    const fontSize = num(record.fontSize);
    const align = str(record.align);
    if (text === null || binding === undefined || fontSize === null || !align) return null;
    if (binding !== null && !TEXT_BINDINGS.includes(binding as (typeof TEXT_BINDINGS)[number])) {
      return null;
    }
    if (align !== "left" && align !== "center" && align !== "right") return null;
    return {
      id,
      type,
      x,
      y,
      width,
      height,
      text,
      binding: binding as TextBinding | null,
      fontSize,
      align,
    };
  }
  if (type === "image") {
    const assetId = str(record.assetId);
    if (!assetId) return null;
    return { id, type, x, y, width, height, assetId };
  }
  if (type === "columns") {
    const columns = num(record.columns);
    const gap = num(record.gap);
    const binding = str(record.binding);
    const fontSize = num(record.fontSize);
    if (columns === null || gap === null || !binding || fontSize === null) return null;
    if (!LIST_BINDINGS.includes(binding as (typeof LIST_BINDINGS)[number])) return null;
    return {
      id,
      type,
      x,
      y,
      width,
      height,
      columns,
      gap,
      binding: binding as (typeof LIST_BINDINGS)[number],
      fontSize,
    };
  }
  return null;
}

function readTemplate(value: unknown): DocumentTemplate | null {
  const record = rec(value);
  if (!record) return null;
  const id = str(record.id);
  const spaceId = str(record.spaceId);
  const name = str(record.name);
  const description = str(record.description);
  const pageSize = str(record.pageSize);
  const backgroundAssetId = record.backgroundAssetId === null ? null : str(record.backgroundAssetId);
  const elements = readArray(record.elements, readElement);
  const times = stamp(record);
  if (!id || !spaceId || !name || description === null || !pageSize || backgroundAssetId === undefined || !elements || !times) {
    return null;
  }
  if (pageSize !== "letter" && pageSize !== "a4") return null;
  return {
    id,
    spaceId,
    name,
    description,
    pageSize: pageSize as PageSize,
    backgroundAssetId,
    elements,
    ...times,
  };
}

function readAsset(value: unknown): Asset | null {
  const record = rec(value);
  if (!record) return null;
  const id = str(record.id);
  const spaceId = str(record.spaceId);
  const name = str(record.name);
  const mime = str(record.mime);
  const dataBase64 = str(record.dataBase64);
  const createdAt = str(record.createdAt);
  const deletedAt = record.deletedAt === null ? null : str(record.deletedAt);
  if (!id || !spaceId || !name || !mime || dataBase64 === null || !createdAt || deletedAt === undefined) {
    return null;
  }
  if (!MIMES.includes(mime as AssetMime) || !isIsoDateTime(createdAt)) return null;
  if (deletedAt !== null && !isIsoDateTime(deletedAt)) return null;
  return { id, spaceId, name, mime: mime as AssetMime, dataBase64, createdAt, deletedAt };
}

function readTombstone(value: unknown): Tombstone | null {
  const record = rec(value);
  if (!record) return null;
  const id = str(record.id);
  const spaceId = str(record.spaceId);
  const entityType = str(record.entityType);
  const entityId = str(record.entityId);
  const naturalKey = str(record.naturalKey);
  const deletedAt = str(record.deletedAt);
  const deletedBy = str(record.deletedBy);
  if (!id || !spaceId || !entityType || !entityId || !naturalKey || !deletedAt || !deletedBy) {
    return null;
  }
  if (!ENTITY_TYPES.includes(entityType as EntityType)) return null;
  if (!("payload" in record)) return null;
  return {
    id,
    spaceId,
    entityType: entityType as EntityType,
    entityId,
    naturalKey,
    deletedAt,
    deletedBy,
    payload: record.payload,
  };
}

function readConflict(value: unknown): ConflictRecord | null {
  const record = rec(value);
  if (!record) return null;
  const id = str(record.id);
  const spaceId = str(record.spaceId);
  const entityType = str(record.entityType);
  const key = str(record.key);
  const localEntityId = record.localEntityId === null ? null : str(record.localEntityId);
  const remoteEntityId = record.remoteEntityId === null ? null : str(record.remoteEntityId);
  const remoteDeleted = bool(record.remoteDeleted);
  const createdAt = str(record.createdAt);
  const resolvedAt = record.resolvedAt === null ? null : str(record.resolvedAt);
  const resolution = str(record.resolution);
  const materializedId = record.materializedId === null ? null : str(record.materializedId);
  if (
    !id ||
    !spaceId ||
    !entityType ||
    !key ||
    localEntityId === undefined ||
    remoteEntityId === undefined ||
    remoteDeleted === null ||
    !createdAt ||
    resolvedAt === undefined ||
    !resolution ||
    materializedId === undefined
  ) {
    return null;
  }
  if (!ENTITY_TYPES.includes(entityType as EntityType)) return null;
  if (!RESOLUTIONS.includes(resolution as ConflictResolution)) return null;
  return {
    id,
    spaceId,
    entityType: entityType as EntityType,
    key,
    localEntityId,
    remoteEntityId,
    local: "local" in record ? record.local : null,
    remote: "remote" in record ? record.remote : null,
    remoteDeleted,
    createdAt,
    resolvedAt,
    resolution: resolution as ConflictResolution,
    materializedId,
  };
}

function readSnapshot(value: unknown): SpaceSnapshot | null {
  const record = rec(value);
  if (!record) return null;
  const space = readSpace(record.space);
  const people = readArray(record.people, readPerson);
  const groups = readArray(record.groups, readGroup);
  const memberships = readArray(record.memberships, readMembership);
  const periods = readArray(record.periods, readPeriod);
  const components = readArray(record.components, readComponent);
  const categories = readArray(record.categories, readCategory);
  const events = readArray(record.events, readEvent);
  const attendance = readArray(record.attendance, readAttendance);
  const volunteering = readArray(record.volunteering, readVolunteer);
  const templates = readArray(record.templates, readTemplate);
  const assets = readArray(record.assets, readAsset);
  const conflicts = readArray(record.conflicts, readConflict);
  const tombstones = readArray(record.tombstones, readTombstone);
  if (
    !space ||
    !people ||
    !groups ||
    !memberships ||
    !periods ||
    !components ||
    !categories ||
    !events ||
    !attendance ||
    !volunteering ||
    !templates ||
    !assets ||
    !conflicts ||
    !tombstones
  ) {
    return null;
  }
  return {
    space,
    people,
    groups,
    memberships,
    periods,
    components,
    categories,
    events,
    attendance,
    volunteering,
    templates,
    assets,
    conflicts,
    tombstones,
  };
}

function readRevision(value: unknown): Revision | null {
  const record = rec(value);
  if (!record) return null;
  const id = str(record.id);
  const spaceId = str(record.spaceId);
  const at = str(record.at);
  const actorId = str(record.actorId);
  const action = str(record.action);
  const params = strMap(record.params);
  const snapshot = readSnapshot(record.snapshot);
  if (!id || !spaceId || !at || !actorId || !action || !params || !snapshot) return null;
  return { id, spaceId, at, actorId, action, params, snapshot };
}

function readHistory(value: unknown): SpaceHistory | null {
  const record = rec(value);
  if (!record) return null;
  const spaceId = str(record.spaceId);
  const revisionIds = readArray(record.revisionIds, (item) => str(item));
  const cursor = num(record.cursor);
  if (!spaceId || !revisionIds || cursor === null || !Number.isInteger(cursor)) return null;
  if (cursor < -1 || cursor >= revisionIds.length) return null;
  return { spaceId, revisionIds, cursor };
}

export function sanitizeDatabase(value: unknown): Result<Database> {
  const record = rec(value);
  if (!record || record.format !== DATABASE_FORMAT) return err("INVALID_IMPORT");
  const actor = rec(record.actor);
  const locale = str(record.locale);
  if (!actor || !str(actor.id) || !str(actor.name) || (locale !== "en" && locale !== "es")) {
    return err("INVALID_IMPORT");
  }
  const spaces = readArray(record.spaces, readSpace);
  const people = readArray(record.people, readPerson);
  const groups = readArray(record.groups, readGroup);
  const memberships = readArray(record.memberships, readMembership);
  const periods = readArray(record.periods, readPeriod);
  const components = readArray(record.components, readComponent);
  const categories = readArray(record.categories, readCategory);
  const events = readArray(record.events, readEvent);
  const attendance = readArray(record.attendance, readAttendance);
  const volunteering = readArray(record.volunteering, readVolunteer);
  const templates = readArray(record.templates, readTemplate);
  const assets = readArray(record.assets, readAsset);
  const conflicts = readArray(record.conflicts, readConflict);
  const tombstones = readArray(record.tombstones, readTombstone);
  const revisions = readArray(record.revisions, readRevision);
  const histories = readArray(record.histories, readHistory);
  if (
    !spaces ||
    !people ||
    !groups ||
    !memberships ||
    !periods ||
    !components ||
    !categories ||
    !events ||
    !attendance ||
    !volunteering ||
    !templates ||
    !assets ||
    !conflicts ||
    !tombstones ||
    !revisions ||
    !histories
  ) {
    return err("INVALID_IMPORT");
  }
  const revisionIds = new Set(revisions.map((revision) => revision.id));
  const cleanHistories = histories.map((history) => ({
    ...history,
    revisionIds: history.revisionIds.filter((id) => revisionIds.has(id)),
  }));
  for (const history of cleanHistories) {
    if (history.cursor >= history.revisionIds.length) return err("INVALID_IMPORT");
  }
  return ok({
    format: DATABASE_FORMAT,
    actor: { id: str(actor.id)!, name: str(actor.name)! },
    locale: locale as Locale,
    spaces,
    people,
    groups,
    memberships,
    periods,
    components,
    categories,
    events,
    attendance,
    volunteering,
    templates,
    assets,
    conflicts,
    tombstones,
    revisions,
    histories: cleanHistories,
  });
}

export function sanitizeSyncBundle(value: unknown): Result<SyncBundle> {
  const record = rec(value);
  if (!record || record.format !== SYNC_FORMAT) return err("INVALID_IMPORT");
  const exportedAt = str(record.exportedAt);
  const actor = rec(record.actor);
  const snapshot = readSnapshot(record.snapshot);
  const tombstones = readArray(record.tombstones, readTombstone);
  if (!exportedAt || !actor || !str(actor.id) || !str(actor.name) || !snapshot || !tombstones) {
    return err("INVALID_IMPORT");
  }
  return ok({
    format: SYNC_FORMAT,
    exportedAt,
    actor: { id: str(actor.id)!, name: str(actor.name)! },
    snapshot,
    tombstones,
  });
}

export function sanitizeBackup(value: unknown): Result<BackupFile> {
  const record = rec(value);
  if (!record || record.format !== BACKUP_FORMAT) return err("INVALID_IMPORT");
  const exportedAt = str(record.exportedAt);
  const database = sanitizeDatabase(record.database);
  if (!exportedAt || !database.ok) return err("INVALID_IMPORT");
  return ok({ format: BACKUP_FORMAT, exportedAt, database: database.value });
}

import { canonical } from "@/core/canonical";
import {
  CAPACITY_STATES,
  EVENT_TRANSITIONS,
} from "@/core/constants";
import { isIsoDate } from "@/core/dates";
import { findMembershipOverlap } from "@/core/groups";
import { mergeSyncBundle } from "@/core/merge";
import { err, ok, type Result } from "@/core/result";
import { replaceSpace, stripSpace, takeSnapshot } from "@/core/snapshot";
import {
  DATABASE_FORMAT,
  type ActivityComponent,
  type AdeEvent,
  type Asset,
  type AssetMime,
  type AttendanceRecord,
  type AttendanceState,
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
  type ReduceContext,
  type SpaceHistory,
  type TemplateElement,
  type Tombstone,
  type VolunteerRecord,
  type VolunteerState,
} from "@/core/types";
import { validateElements } from "@/core/documents";
import { canTransitionVolunteer, consumingVolunteerCount } from "@/core/volunteering";
import { sanitizeBackup, sanitizeDatabase, sanitizeSyncBundle } from "@/core/validate";

export type ElementDraft = {
  [K in TemplateElement["type"]]: Omit<Extract<TemplateElement, { type: K }>, "id"> & {
    id?: string;
  };
}[TemplateElement["type"]];

export type Action =
  | { type: "setLocale"; locale: Locale }
  | { type: "setActorName"; name: string }
  | { type: "createSpace"; name: string }
  | { type: "renameSpace"; spaceId: string; name: string }
  | {
      type: "createPerson";
      spaceId: string;
      name: string;
      email?: string;
      notes?: string;
      status?: PersonStatus;
    }
  | {
      type: "updatePerson";
      spaceId: string;
      personId: string;
      name: string;
      email: string;
      notes: string;
      status: PersonStatus;
    }
  | { type: "deletePerson"; spaceId: string; personId: string }
  | { type: "createGroup"; spaceId: string; name: string; description?: string }
  | { type: "updateGroup"; spaceId: string; groupId: string; name: string; description: string }
  | { type: "deleteGroup"; spaceId: string; groupId: string }
  | {
      type: "addMembership";
      spaceId: string;
      groupId: string;
      personId: string;
      startDate: string;
      endDate: string | null;
    }
  | {
      type: "updateMembership";
      spaceId: string;
      membershipId: string;
      startDate: string;
      endDate: string | null;
    }
  | { type: "deleteMembership"; spaceId: string; membershipId: string }
  | { type: "createPeriod"; spaceId: string; name: string; startDate: string; endDate: string }
  | {
      type: "updatePeriod";
      spaceId: string;
      periodId: string;
      name: string;
      startDate: string;
      endDate: string;
    }
  | { type: "deletePeriod"; spaceId: string; periodId: string }
  | { type: "createComponent"; spaceId: string; name: string; description?: string }
  | {
      type: "updateComponent";
      spaceId: string;
      componentId: string;
      name: string;
      description: string;
    }
  | { type: "deleteComponent"; spaceId: string; componentId: string }
  | {
      type: "createCategory";
      spaceId: string;
      componentId: string;
      name: string;
      description?: string;
    }
  | {
      type: "updateCategory";
      spaceId: string;
      categoryId: string;
      name: string;
      description: string;
    }
  | { type: "deleteCategory"; spaceId: string; categoryId: string }
  | {
      type: "createEvent";
      spaceId: string;
      title: string;
      description?: string;
      date: string;
      componentId: string;
      categoryId: string | null;
      capacity: number | null;
      volunteerCapacity: number | null;
      countsForAttendance: boolean;
      participantIds?: string[];
    }
  | {
      type: "updateEvent";
      spaceId: string;
      eventId: string;
      title: string;
      description: string;
      date: string;
      componentId: string;
      categoryId: string | null;
      capacity: number | null;
      volunteerCapacity: number | null;
      countsForAttendance: boolean;
    }
  | { type: "setEventStatus"; spaceId: string; eventId: string; status: EventStatus }
  | { type: "setEventParticipants"; spaceId: string; eventId: string; participantIds: string[] }
  | { type: "duplicateEvent"; spaceId: string; eventId: string; titleSuffix: string }
  | { type: "deleteEvent"; spaceId: string; eventId: string }
  | {
      type: "setAttendance";
      spaceId: string;
      eventId: string;
      personId: string;
      state: AttendanceState;
      note: string;
    }
  | {
      type: "setVolunteerState";
      spaceId: string;
      eventId: string;
      personId: string;
      state: VolunteerState;
      note: string;
    }
  | {
      type: "createTemplate";
      spaceId: string;
      name: string;
      description?: string;
      pageSize: PageSize;
      backgroundAssetId: string | null;
      elements: ElementDraft[];
    }
  | {
      type: "updateTemplate";
      spaceId: string;
      templateId: string;
      name: string;
      description: string;
      pageSize: PageSize;
      backgroundAssetId: string | null;
      elements: ElementDraft[];
    }
  | { type: "deleteTemplate"; spaceId: string; templateId: string }
  | { type: "addAsset"; spaceId: string; name: string; mime: AssetMime; dataBase64: string }
  | { type: "deleteAsset"; spaceId: string; assetId: string }
  | { type: "undo"; spaceId: string }
  | { type: "redo"; spaceId: string }
  | { type: "restoreRevision"; spaceId: string; revisionId: string }
  | { type: "importBackup"; backup: unknown }
  | { type: "importSync"; bundle: unknown }
  | {
      type: "resolveConflict";
      spaceId: string;
      conflictId: string;
      resolution: Exclude<ConflictResolution, "pending">;
    }
  | { type: "loadDemo" };

export function createEmptyDatabase(actorId: string, now: string, actorName = "Local user"): Database {
  return {
    format: DATABASE_FORMAT,
    actor: { id: actorId, name: actorName },
    locale: "en",
    spaces: [],
    people: [],
    groups: [],
    memberships: [],
    periods: [],
    components: [],
    categories: [],
    events: [],
    attendance: [],
    volunteering: [],
    templates: [],
    assets: [],
    conflicts: [],
    tombstones: [],
    revisions: [],
    histories: [],
  };
}

function cleanName(value: string): Result<string> {
  const name = value.trim();
  if (!name) return err("NAME_REQUIRED");
  return ok(name);
}

function cleanDate(value: string): Result<string> {
  if (!isIsoDate(value)) return err("INVALID_DATE");
  return ok(value);
}

function cleanRange(start: string, end: string | null): Result<{ start: string; end: string | null }> {
  if (!isIsoDate(start) || (end !== null && !isIsoDate(end))) return err("INVALID_DATE");
  if (end !== null && end < start) return err("INVALID_DATE_RANGE");
  return ok({ start, end });
}

function cleanCapacity(value: number | null): Result<number | null> {
  if (value === null) return ok(null);
  if (!Number.isInteger(value) || value < 0) return err("INVALID_CAPACITY");
  return ok(value);
}

function commit(
  db: Database,
  spaceId: string,
  action: string,
  params: Record<string, string>,
  ctx: ReduceContext,
): Database {
  const revision = {
    id: ctx.newId(),
    spaceId,
    at: ctx.now,
    actorId: ctx.actorId,
    action,
    params,
    snapshot: takeSnapshot(db, spaceId),
  };
  const history = db.histories.find((item) => item.spaceId === spaceId) ?? {
    spaceId,
    revisionIds: [],
    cursor: -1,
  };
  const kept = history.revisionIds.slice(0, history.cursor + 1);
  const dropped = new Set(history.revisionIds.slice(history.cursor + 1));
  const nextHistory: SpaceHistory = {
    spaceId,
    revisionIds: [...kept, revision.id],
    cursor: kept.length,
  };
  return {
    ...db,
    revisions: [...db.revisions.filter((item) => !dropped.has(item.id)), revision],
    histories: [...db.histories.filter((item) => item.spaceId !== spaceId), nextHistory],
  };
}

function setCursor(db: Database, spaceId: string, cursor: number): Database {
  return {
    ...db,
    histories: db.histories.map((history) =>
      history.spaceId === spaceId ? { ...history, cursor } : history,
    ),
  };
}

function tombstone(
  db: Database,
  entityType: EntityType,
  entity: { id: string; spaceId: string },
  naturalKey: string,
  ctx: ReduceContext,
): Database {
  const stone: Tombstone = {
    id: ctx.newId(),
    spaceId: entity.spaceId,
    entityType,
    entityId: entity.id,
    naturalKey,
    deletedAt: ctx.now,
    deletedBy: ctx.actorId,
    payload: structuredClone(entity),
  };
  return { ...db, tombstones: [...db.tombstones, stone] };
}

function requireSpace(db: Database, spaceId: string): Result<true> {
  return db.spaces.some((space) => space.id === spaceId) ? ok(true) : err("NOT_FOUND", { entity: "space" });
}

function categoryOk(
  db: Database,
  spaceId: string,
  componentId: string,
  categoryId: string | null,
): Result<true> {
  const component = db.components.find((item) => item.id === componentId);
  if (!component || component.spaceId !== spaceId) return err("NOT_FOUND", { entity: "component" });
  if (!categoryId) return ok(true);
  const category = db.categories.find((item) => item.id === categoryId);
  if (!category || category.spaceId !== spaceId) return err("NOT_FOUND", { entity: "category" });
  if (category.componentId !== componentId) return err("CATEGORY_COMPONENT_MISMATCH");
  return ok(true);
}

function withIds(elements: ElementDraft[], ctx: ReduceContext): TemplateElement[] {
  return elements.map((element) => ({
    ...element,
    id: element.id ?? ctx.newId(),
  })) as TemplateElement[];
}

function participantsOk(
  db: Database,
  spaceId: string,
  participantIds: string[],
  capacity: number | null,
): Result<string[]> {
  if (new Set(participantIds).size !== participantIds.length) return err("DUPLICATE_PARTICIPANT");
  for (const personId of participantIds) {
    const person = db.people.find((item) => item.id === personId);
    if (!person || person.spaceId !== spaceId) return err("NOT_FOUND", { entity: "person" });
  }
  if (capacity !== null && participantIds.length > capacity) {
    return err("CAPACITY_EXCEEDED", {
      capacity: String(capacity),
      used: String(participantIds.length),
    });
  }
  return ok(participantIds);
}

function applyRemote(db: Database, conflict: ConflictRecord, ctx: ReduceContext): Result<Database> {
  if (conflict.remoteDeleted) {
    return deleteByConflict(db, conflict, ctx);
  }
  if (!conflict.remote || typeof conflict.remote !== "object") return err("INVALID_IMPORT");
  const remote = structuredClone(conflict.remote) as { id: string; spaceId: string };
  if (!remote.id || remote.spaceId !== conflict.spaceId) return err("INVALID_IMPORT");
  switch (conflict.entityType) {
    case "space": {
      const space = conflict.remote as Database["spaces"][number];
      return ok({
        ...db,
        spaces: db.spaces.map((item) => (item.id === space.id ? structuredClone(space) : item)),
      });
    }
    case "person":
      return ok({ ...db, people: upsert(db.people, conflict.remote as Person) });
    case "group":
      return ok({ ...db, groups: upsert(db.groups, conflict.remote as Group) });
    case "membership":
      return ok({
        ...db,
        memberships: upsert(db.memberships, conflict.remote as GroupMembership),
      });
    case "period":
      return ok({ ...db, periods: upsert(db.periods, conflict.remote as Period) });
    case "component":
      return ok({
        ...db,
        components: upsert(db.components, conflict.remote as ActivityComponent),
      });
    case "category":
      return ok({ ...db, categories: upsert(db.categories, conflict.remote as Category) });
    case "event":
      return ok({ ...db, events: upsert(db.events, conflict.remote as AdeEvent) });
    case "attendance": {
      const record = conflict.remote as AttendanceRecord;
      const rest = db.attendance.filter(
        (item) =>
          !(
            item.spaceId === record.spaceId &&
            item.eventId === record.eventId &&
            item.personId === record.personId
          ),
      );
      return ok({ ...db, attendance: [...rest, structuredClone(record)] });
    }
    case "volunteering": {
      const record = conflict.remote as VolunteerRecord;
      const rest = db.volunteering.filter(
        (item) =>
          !(
            item.spaceId === record.spaceId &&
            item.eventId === record.eventId &&
            item.personId === record.personId
          ),
      );
      return ok({ ...db, volunteering: [...rest, structuredClone(record)] });
    }
    case "template":
      return ok({
        ...db,
        templates: upsert(db.templates, conflict.remote as DocumentTemplate),
      });
    case "asset":
      return ok({ ...db, assets: upsert(db.assets, conflict.remote as Asset) });
    default:
      return err("INVALID_IMPORT");
  }
}

function upsert<T extends { id: string }>(list: T[], item: T): T[] {
  const copy = structuredClone(item);
  return list.some((entry) => entry.id === copy.id)
    ? list.map((entry) => (entry.id === copy.id ? copy : entry))
    : [...list, copy];
}

function deleteByConflict(
  db: Database,
  conflict: ConflictRecord,
  ctx: ReduceContext,
): Result<Database> {
  const id = conflict.localEntityId;
  if (!id) return ok(db);
  switch (conflict.entityType) {
    case "person": {
      const person = db.people.find((item) => item.id === id);
      if (!person) return ok(db);
      return ok(tombstone({ ...db, people: db.people.filter((item) => item.id !== id) }, "person", person, person.id, ctx));
    }
    case "attendance": {
      const record = db.attendance.find((item) => item.id === id);
      if (!record) return ok(db);
      return ok(
        tombstone(
          { ...db, attendance: db.attendance.filter((item) => item.id !== id) },
          "attendance",
          record,
          `${record.eventId}:${record.personId}`,
          ctx,
        ),
      );
    }
    default:
      return ok(removeGeneric(db, conflict.entityType, id, ctx));
  }
}

function removeGeneric(db: Database, entityType: EntityType, id: string, ctx: ReduceContext): Database {
  const drop = <T extends { id: string; spaceId: string }>(list: T[], type: EntityType): Database | null => {
    const entity = list.find((item) => item.id === id);
    if (!entity) return null;
    const nextList = list.filter((item) => item.id !== id);
    const base = { ...db };
    if (type === "group") return tombstone({ ...base, groups: nextList as unknown as Group[] }, type, entity, id, ctx);
    if (type === "membership") {
      return tombstone({ ...base, memberships: nextList as unknown as GroupMembership[] }, type, entity, id, ctx);
    }
    if (type === "period") return tombstone({ ...base, periods: nextList as unknown as Period[] }, type, entity, id, ctx);
    if (type === "component") {
      return tombstone({ ...base, components: nextList as unknown as ActivityComponent[] }, type, entity, id, ctx);
    }
    if (type === "category") return tombstone({ ...base, categories: nextList as unknown as Category[] }, type, entity, id, ctx);
    if (type === "event") return tombstone({ ...base, events: nextList as unknown as AdeEvent[] }, type, entity, id, ctx);
    if (type === "volunteering") {
      const record = entity as unknown as VolunteerRecord;
      return tombstone(
        { ...base, volunteering: nextList as unknown as VolunteerRecord[] },
        type,
        record,
        `${record.eventId}:${record.personId}`,
        ctx,
      );
    }
    if (type === "template") {
      return tombstone({ ...base, templates: nextList as unknown as DocumentTemplate[] }, type, entity, id, ctx);
    }
    if (type === "asset") return tombstone({ ...base, assets: nextList as unknown as Asset[] }, type, entity, id, ctx);
    return null;
  };
  if (entityType === "group") return drop(db.groups, entityType) ?? db;
  if (entityType === "membership") return drop(db.memberships, entityType) ?? db;
  if (entityType === "period") return drop(db.periods, entityType) ?? db;
  if (entityType === "component") return drop(db.components, entityType) ?? db;
  if (entityType === "category") return drop(db.categories, entityType) ?? db;
  if (entityType === "event") return drop(db.events, entityType) ?? db;
  if (entityType === "volunteering") return drop(db.volunteering, entityType) ?? db;
  if (entityType === "template") return drop(db.templates, entityType) ?? db;
  if (entityType === "asset") return drop(db.assets, entityType) ?? db;
  return db;
}

function materialize(
  db: Database,
  conflict: ConflictRecord,
  ctx: ReduceContext,
): { db: Database; materializedId: string | null } {
  if (
    conflict.remoteDeleted ||
    !conflict.remote ||
    conflict.entityType === "attendance" ||
    conflict.entityType === "volunteering" ||
    conflict.entityType === "space"
  ) {
    return { db, materializedId: null };
  }
  const id = ctx.newId();
  const stampCopy = <T extends { id: string; createdAt: string; updatedAt: string }>(item: T): T => ({
    ...structuredClone(item),
    id,
    createdAt: ctx.now,
    updatedAt: ctx.now,
  });
  if (conflict.entityType === "person") {
    const person = stampCopy(conflict.remote as Person);
    person.name = `${person.name} (conflict)`;
    return { db: { ...db, people: [...db.people, person] }, materializedId: id };
  }
  if (conflict.entityType === "group") {
    const group = stampCopy(conflict.remote as Group);
    group.name = `${group.name} (conflict)`;
    return { db: { ...db, groups: [...db.groups, group] }, materializedId: id };
  }
  if (conflict.entityType === "membership") {
    const membership = stampCopy(conflict.remote as GroupMembership);
    if (findMembershipOverlap(db.memberships, membership)) return { db, materializedId: null };
    return { db: { ...db, memberships: [...db.memberships, membership] }, materializedId: id };
  }
  if (conflict.entityType === "period") {
    const period = stampCopy(conflict.remote as Period);
    period.name = `${period.name} (conflict)`;
    return { db: { ...db, periods: [...db.periods, period] }, materializedId: id };
  }
  if (conflict.entityType === "component") {
    const component = stampCopy(conflict.remote as ActivityComponent);
    component.name = `${component.name} (conflict)`;
    return { db: { ...db, components: [...db.components, component] }, materializedId: id };
  }
  if (conflict.entityType === "category") {
    const category = stampCopy(conflict.remote as Category);
    category.name = `${category.name} (conflict)`;
    return { db: { ...db, categories: [...db.categories, category] }, materializedId: id };
  }
  if (conflict.entityType === "event") {
    const event = stampCopy(conflict.remote as AdeEvent);
    event.title = `${event.title} (conflict)`;
    event.duplicatedFromId = (conflict.remote as AdeEvent).id;
    return { db: { ...db, events: [...db.events, event] }, materializedId: id };
  }
  if (conflict.entityType === "template") {
    const template = stampCopy(conflict.remote as DocumentTemplate);
    template.name = `${template.name} (conflict)`;
    return { db: { ...db, templates: [...db.templates, template] }, materializedId: id };
  }
  if (conflict.entityType === "asset") {
    const asset = structuredClone(conflict.remote as Asset);
    asset.id = id;
    asset.name = `${asset.name} (conflict)`;
    asset.createdAt = ctx.now;
    return { db: { ...db, assets: [...db.assets, asset] }, materializedId: id };
  }
  return { db, materializedId: null };
}

function finishConflict(
  db: Database,
  conflict: ConflictRecord,
  resolution: Exclude<ConflictResolution, "pending">,
  materializedId: string | null,
  ctx: ReduceContext,
): Database {
  const next: ConflictRecord = {
    ...conflict,
    resolution,
    resolvedAt: ctx.now,
    materializedId,
  };
  return {
    ...db,
    conflicts: db.conflicts.map((item) => (item.id === conflict.id ? next : item)),
  };
}

export function dispatch(db: Database, action: Action, ctx: ReduceContext): Result<Database> {
  switch (action.type) {
    case "setLocale":
      if (action.locale !== "en" && action.locale !== "es") return err("INVALID_IMPORT");
      return db.locale === action.locale ? ok(db) : ok({ ...db, locale: action.locale });
    case "setActorName": {
      const name = cleanName(action.name);
      if (!name.ok) return name;
      return ok({ ...db, actor: { ...db.actor, name: name.value } });
    }
    case "createSpace": {
      const name = cleanName(action.name);
      if (!name.ok) return name;
      const space = {
        id: ctx.newId(),
        name: name.value,
        createdAt: ctx.now,
        updatedAt: ctx.now,
      };
      return ok(
        commit({ ...db, spaces: [...db.spaces, space] }, space.id, "createSpace", { name: space.name }, ctx),
      );
    }
    case "loadDemo":
      return applyDemo(db, ctx);
    case "importBackup": {
      const backup = sanitizeBackup(action.backup);
      if (!backup.ok) return backup;
      return ok(backup.value.database);
    }
    case "importSync": {
      const bundle = sanitizeSyncBundle(action.bundle);
      if (!bundle.ok) return bundle;
      const spaceId = bundle.value.snapshot.space.id;
      const existed = db.spaces.some((space) => space.id === spaceId);
      const merged = mergeSyncBundle(db, bundle.value, ctx);
      if (!merged.ok) return merged;
      if (existed && canonical(takeSnapshot(db, spaceId)) === canonical(takeSnapshot(merged.value, spaceId))) {
        return ok(db);
      }
      return ok(
        commit(merged.value, spaceId, "importSync", { name: bundle.value.snapshot.space.name }, ctx),
      );
    }
    case "undo": {
      const history = db.histories.find((item) => item.spaceId === action.spaceId);
      if (!history || history.cursor < 0) return err("NOTHING_TO_UNDO");
      const cursor = history.cursor - 1;
      if (cursor < 0) return ok(setCursor(stripSpace(db, action.spaceId), action.spaceId, -1));
      const revision = db.revisions.find((item) => item.id === history.revisionIds[cursor]);
      if (!revision) return err("NOT_FOUND", { entity: "revision" });
      return ok(setCursor(replaceSpace(db, revision.snapshot), action.spaceId, cursor));
    }
    case "redo": {
      const history = db.histories.find((item) => item.spaceId === action.spaceId);
      if (!history || history.cursor >= history.revisionIds.length - 1) return err("NOTHING_TO_REDO");
      const cursor = history.cursor + 1;
      const revision = db.revisions.find((item) => item.id === history.revisionIds[cursor]);
      if (!revision) return err("NOT_FOUND", { entity: "revision" });
      return ok(setCursor(replaceSpace(db, revision.snapshot), action.spaceId, cursor));
    }
    case "restoreRevision": {
      const history = db.histories.find((item) => item.spaceId === action.spaceId);
      if (!history) return err("NOT_FOUND", { entity: "revision" });
      const cursor = history.revisionIds.indexOf(action.revisionId);
      if (cursor < 0) return err("NOT_FOUND", { entity: "revision" });
      const revision = db.revisions.find((item) => item.id === action.revisionId);
      if (!revision) return err("NOT_FOUND", { entity: "revision" });
      return ok(setCursor(replaceSpace(db, revision.snapshot), action.spaceId, cursor));
    }
    default:
      break;
  }

  if (!("spaceId" in action)) return err("NOT_FOUND");
  const space = requireSpace(db, action.spaceId);
  if (!space.ok) return space;

  switch (action.type) {
    case "renameSpace": {
      const name = cleanName(action.name);
      if (!name.ok) return name;
      const next = {
        ...db,
        spaces: db.spaces.map((item) =>
          item.id === action.spaceId ? { ...item, name: name.value, updatedAt: ctx.now } : item,
        ),
      };
      return ok(commit(next, action.spaceId, "renameSpace", { name: name.value }, ctx));
    }
    case "createPerson": {
      const name = cleanName(action.name);
      if (!name.ok) return name;
      const person: Person = {
        id: ctx.newId(),
        spaceId: action.spaceId,
        name: name.value,
        email: action.email?.trim() ?? "",
        notes: action.notes?.trim() ?? "",
        status: action.status ?? "active",
        createdAt: ctx.now,
        updatedAt: ctx.now,
      };
      return ok(
        commit({ ...db, people: [...db.people, person] }, action.spaceId, "createPerson", { name: person.name }, ctx),
      );
    }
    case "updatePerson": {
      const name = cleanName(action.name);
      if (!name.ok) return name;
      const current = db.people.find((item) => item.id === action.personId && item.spaceId === action.spaceId);
      if (!current) return err("NOT_FOUND", { entity: "person" });
      const person: Person = {
        ...current,
        name: name.value,
        email: action.email.trim(),
        notes: action.notes.trim(),
        status: action.status,
        updatedAt: ctx.now,
      };
      return ok(
        commit(
          { ...db, people: db.people.map((item) => (item.id === person.id ? person : item)) },
          action.spaceId,
          "updatePerson",
          { name: person.name },
          ctx,
        ),
      );
    }
    case "deletePerson": {
      const person = db.people.find((item) => item.id === action.personId && item.spaceId === action.spaceId);
      if (!person) return err("NOT_FOUND", { entity: "person" });
      if (db.memberships.some((item) => item.personId === person.id)) {
        return err("IN_USE", { entity: "person", reason: "memberships" });
      }
      if (db.events.some((item) => item.participantIds.includes(person.id))) {
        return err("IN_USE", { entity: "person", reason: "events" });
      }
      if (db.attendance.some((item) => item.personId === person.id)) {
        return err("IN_USE", { entity: "person", reason: "attendance" });
      }
      if (db.volunteering.some((item) => item.personId === person.id)) {
        return err("IN_USE", { entity: "person", reason: "volunteering" });
      }
      const next = tombstone(
        { ...db, people: db.people.filter((item) => item.id !== person.id) },
        "person",
        person,
        person.id,
        ctx,
      );
      return ok(commit(next, action.spaceId, "deletePerson", { name: person.name }, ctx));
    }
    case "createGroup": {
      const name = cleanName(action.name);
      if (!name.ok) return name;
      const group: Group = {
        id: ctx.newId(),
        spaceId: action.spaceId,
        name: name.value,
        description: action.description?.trim() ?? "",
        createdAt: ctx.now,
        updatedAt: ctx.now,
      };
      return ok(commit({ ...db, groups: [...db.groups, group] }, action.spaceId, "createGroup", { name: group.name }, ctx));
    }
    case "updateGroup": {
      const name = cleanName(action.name);
      if (!name.ok) return name;
      const current = db.groups.find((item) => item.id === action.groupId && item.spaceId === action.spaceId);
      if (!current) return err("NOT_FOUND", { entity: "group" });
      const group: Group = { ...current, name: name.value, description: action.description.trim(), updatedAt: ctx.now };
      return ok(
        commit(
          { ...db, groups: db.groups.map((item) => (item.id === group.id ? group : item)) },
          action.spaceId,
          "updateGroup",
          { name: group.name },
          ctx,
        ),
      );
    }
    case "deleteGroup": {
      const group = db.groups.find((item) => item.id === action.groupId && item.spaceId === action.spaceId);
      if (!group) return err("NOT_FOUND", { entity: "group" });
      if (db.memberships.some((item) => item.groupId === group.id)) {
        return err("IN_USE", { entity: "group", reason: "memberships" });
      }
      const next = tombstone(
        { ...db, groups: db.groups.filter((item) => item.id !== group.id) },
        "group",
        group,
        group.id,
        ctx,
      );
      return ok(commit(next, action.spaceId, "deleteGroup", { name: group.name }, ctx));
    }
    case "addMembership": {
      const range = cleanRange(action.startDate, action.endDate);
      if (!range.ok) return range;
      const group = db.groups.find((item) => item.id === action.groupId && item.spaceId === action.spaceId);
      const person = db.people.find((item) => item.id === action.personId && item.spaceId === action.spaceId);
      if (!group || !person) return err("NOT_FOUND", { entity: group ? "person" : "group" });
      if (findMembershipOverlap(db.memberships, { ...action, startDate: range.value.start, endDate: range.value.end })) {
        return err("OVERLAPPING_MEMBERSHIP");
      }
      const membership: GroupMembership = {
        id: ctx.newId(),
        spaceId: action.spaceId,
        groupId: group.id,
        personId: person.id,
        startDate: range.value.start,
        endDate: range.value.end,
        createdAt: ctx.now,
        updatedAt: ctx.now,
      };
      return ok(
        commit(
          { ...db, memberships: [...db.memberships, membership] },
          action.spaceId,
          "addMembership",
          { name: person.name, group: group.name },
          ctx,
        ),
      );
    }
    case "updateMembership": {
      const range = cleanRange(action.startDate, action.endDate);
      if (!range.ok) return range;
      const current = db.memberships.find(
        (item) => item.id === action.membershipId && item.spaceId === action.spaceId,
      );
      if (!current) return err("NOT_FOUND", { entity: "membership" });
      if (
        findMembershipOverlap(db.memberships, {
          groupId: current.groupId,
          personId: current.personId,
          startDate: range.value.start,
          endDate: range.value.end,
          ignoreId: current.id,
        })
      ) {
        return err("OVERLAPPING_MEMBERSHIP");
      }
      const membership: GroupMembership = {
        ...current,
        startDate: range.value.start,
        endDate: range.value.end,
        updatedAt: ctx.now,
      };
      return ok(
        commit(
          {
            ...db,
            memberships: db.memberships.map((item) => (item.id === membership.id ? membership : item)),
          },
          action.spaceId,
          "updateMembership",
          { name: db.people.find((item) => item.id === current.personId)?.name ?? "" },
          ctx,
        ),
      );
    }
    case "deleteMembership": {
      const membership = db.memberships.find(
        (item) => item.id === action.membershipId && item.spaceId === action.spaceId,
      );
      if (!membership) return err("NOT_FOUND", { entity: "membership" });
      const next = tombstone(
        { ...db, memberships: db.memberships.filter((item) => item.id !== membership.id) },
        "membership",
        membership,
        membership.id,
        ctx,
      );
      return ok(commit(next, action.spaceId, "deleteMembership", {}, ctx));
    }
    case "createPeriod": {
      const name = cleanName(action.name);
      if (!name.ok) return name;
      const range = cleanRange(action.startDate, action.endDate);
      if (!range.ok) return range;
      const period: Period = {
        id: ctx.newId(),
        spaceId: action.spaceId,
        name: name.value,
        startDate: range.value.start,
        endDate: range.value.end!,
        createdAt: ctx.now,
        updatedAt: ctx.now,
      };
      return ok(commit({ ...db, periods: [...db.periods, period] }, action.spaceId, "createPeriod", { name: period.name }, ctx));
    }
    case "updatePeriod": {
      const name = cleanName(action.name);
      if (!name.ok) return name;
      const range = cleanRange(action.startDate, action.endDate);
      if (!range.ok) return range;
      const current = db.periods.find((item) => item.id === action.periodId && item.spaceId === action.spaceId);
      if (!current) return err("NOT_FOUND", { entity: "period" });
      const period: Period = {
        ...current,
        name: name.value,
        startDate: range.value.start,
        endDate: range.value.end!,
        updatedAt: ctx.now,
      };
      return ok(
        commit(
          { ...db, periods: db.periods.map((item) => (item.id === period.id ? period : item)) },
          action.spaceId,
          "updatePeriod",
          { name: period.name },
          ctx,
        ),
      );
    }
    case "deletePeriod": {
      const period = db.periods.find((item) => item.id === action.periodId && item.spaceId === action.spaceId);
      if (!period) return err("NOT_FOUND", { entity: "period" });
      const next = tombstone(
        { ...db, periods: db.periods.filter((item) => item.id !== period.id) },
        "period",
        period,
        period.id,
        ctx,
      );
      return ok(commit(next, action.spaceId, "deletePeriod", { name: period.name }, ctx));
    }
    case "createComponent": {
      const name = cleanName(action.name);
      if (!name.ok) return name;
      const component: ActivityComponent = {
        id: ctx.newId(),
        spaceId: action.spaceId,
        name: name.value,
        description: action.description?.trim() ?? "",
        createdAt: ctx.now,
        updatedAt: ctx.now,
      };
      return ok(
        commit(
          { ...db, components: [...db.components, component] },
          action.spaceId,
          "createComponent",
          { name: component.name },
          ctx,
        ),
      );
    }
    case "updateComponent": {
      const name = cleanName(action.name);
      if (!name.ok) return name;
      const current = db.components.find((item) => item.id === action.componentId && item.spaceId === action.spaceId);
      if (!current) return err("NOT_FOUND", { entity: "component" });
      const component = { ...current, name: name.value, description: action.description.trim(), updatedAt: ctx.now };
      return ok(
        commit(
          { ...db, components: db.components.map((item) => (item.id === component.id ? component : item)) },
          action.spaceId,
          "updateComponent",
          { name: component.name },
          ctx,
        ),
      );
    }
    case "deleteComponent": {
      const component = db.components.find((item) => item.id === action.componentId && item.spaceId === action.spaceId);
      if (!component) return err("NOT_FOUND", { entity: "component" });
      if (db.categories.some((item) => item.componentId === component.id)) {
        return err("IN_USE", { entity: "component", reason: "categories" });
      }
      if (db.events.some((item) => item.componentId === component.id)) {
        return err("IN_USE", { entity: "component", reason: "events" });
      }
      const next = tombstone(
        { ...db, components: db.components.filter((item) => item.id !== component.id) },
        "component",
        component,
        component.id,
        ctx,
      );
      return ok(commit(next, action.spaceId, "deleteComponent", { name: component.name }, ctx));
    }
    case "createCategory": {
      const name = cleanName(action.name);
      if (!name.ok) return name;
      const linked = categoryOk(db, action.spaceId, action.componentId, null);
      if (!linked.ok) return linked;
      const category: Category = {
        id: ctx.newId(),
        spaceId: action.spaceId,
        componentId: action.componentId,
        name: name.value,
        description: action.description?.trim() ?? "",
        createdAt: ctx.now,
        updatedAt: ctx.now,
      };
      return ok(
        commit({ ...db, categories: [...db.categories, category] }, action.spaceId, "createCategory", { name: category.name }, ctx),
      );
    }
    case "updateCategory": {
      const name = cleanName(action.name);
      if (!name.ok) return name;
      const current = db.categories.find((item) => item.id === action.categoryId && item.spaceId === action.spaceId);
      if (!current) return err("NOT_FOUND", { entity: "category" });
      const category = { ...current, name: name.value, description: action.description.trim(), updatedAt: ctx.now };
      return ok(
        commit(
          { ...db, categories: db.categories.map((item) => (item.id === category.id ? category : item)) },
          action.spaceId,
          "updateCategory",
          { name: category.name },
          ctx,
        ),
      );
    }
    case "deleteCategory": {
      const category = db.categories.find((item) => item.id === action.categoryId && item.spaceId === action.spaceId);
      if (!category) return err("NOT_FOUND", { entity: "category" });
      if (db.events.some((item) => item.categoryId === category.id)) {
        return err("IN_USE", { entity: "category", reason: "events" });
      }
      const next = tombstone(
        { ...db, categories: db.categories.filter((item) => item.id !== category.id) },
        "category",
        category,
        category.id,
        ctx,
      );
      return ok(commit(next, action.spaceId, "deleteCategory", { name: category.name }, ctx));
    }
    case "createEvent": {
      const title = cleanName(action.title);
      if (!title.ok) return title;
      const date = cleanDate(action.date);
      if (!date.ok) return date;
      const capacity = cleanCapacity(action.capacity);
      if (!capacity.ok) return capacity;
      const volunteerCapacity = cleanCapacity(action.volunteerCapacity);
      if (!volunteerCapacity.ok) return volunteerCapacity;
      const linked = categoryOk(db, action.spaceId, action.componentId, action.categoryId);
      if (!linked.ok) return linked;
      const participants = participantsOk(db, action.spaceId, action.participantIds ?? [], capacity.value);
      if (!participants.ok) return participants;
      const event: AdeEvent = {
        id: ctx.newId(),
        spaceId: action.spaceId,
        title: title.value,
        description: action.description?.trim() ?? "",
        date: date.value,
        componentId: action.componentId,
        categoryId: action.categoryId,
        participantIds: participants.value,
        capacity: capacity.value,
        countsForAttendance: action.countsForAttendance,
        status: "draft",
        volunteerCapacity: volunteerCapacity.value,
        duplicatedFromId: null,
        createdAt: ctx.now,
        updatedAt: ctx.now,
      };
      return ok(commit({ ...db, events: [...db.events, event] }, action.spaceId, "createEvent", { name: event.title }, ctx));
    }
    case "updateEvent": {
      const title = cleanName(action.title);
      if (!title.ok) return title;
      const date = cleanDate(action.date);
      if (!date.ok) return date;
      const capacity = cleanCapacity(action.capacity);
      if (!capacity.ok) return capacity;
      const volunteerCapacity = cleanCapacity(action.volunteerCapacity);
      if (!volunteerCapacity.ok) return volunteerCapacity;
      const current = db.events.find((item) => item.id === action.eventId && item.spaceId === action.spaceId);
      if (!current) return err("NOT_FOUND", { entity: "event" });
      const linked = categoryOk(db, action.spaceId, action.componentId, action.categoryId);
      if (!linked.ok) return linked;
      if (capacity.value !== null && current.participantIds.length > capacity.value) {
        return err("CAPACITY_EXCEEDED", {
          capacity: String(capacity.value),
          used: String(current.participantIds.length),
        });
      }
      const used = consumingVolunteerCount(db, current.id);
      if (volunteerCapacity.value !== null && used > volunteerCapacity.value) {
        return err("CAPACITY_EXCEEDED", { capacity: String(volunteerCapacity.value), used: String(used) });
      }
      const event: AdeEvent = {
        ...current,
        title: title.value,
        description: action.description.trim(),
        date: date.value,
        componentId: action.componentId,
        categoryId: action.categoryId,
        capacity: capacity.value,
        volunteerCapacity: volunteerCapacity.value,
        countsForAttendance: action.countsForAttendance,
        updatedAt: ctx.now,
      };
      return ok(
        commit(
          { ...db, events: db.events.map((item) => (item.id === event.id ? event : item)) },
          action.spaceId,
          "updateEvent",
          { name: event.title },
          ctx,
        ),
      );
    }
    case "setEventStatus": {
      const current = db.events.find((item) => item.id === action.eventId && item.spaceId === action.spaceId);
      if (!current) return err("NOT_FOUND", { entity: "event" });
      if (current.status === action.status) return ok(db);
      if (!EVENT_TRANSITIONS[current.status].includes(action.status)) {
        return err("INVALID_TRANSITION", { from: current.status, to: action.status });
      }
      const event = { ...current, status: action.status, updatedAt: ctx.now };
      return ok(
        commit(
          { ...db, events: db.events.map((item) => (item.id === event.id ? event : item)) },
          action.spaceId,
          "setEventStatus",
          { name: event.title, status: event.status },
          ctx,
        ),
      );
    }
    case "setEventParticipants": {
      const current = db.events.find((item) => item.id === action.eventId && item.spaceId === action.spaceId);
      if (!current) return err("NOT_FOUND", { entity: "event" });
      if (current.status === "cancelled") return err("EVENT_LOCKED");
      const participants = participantsOk(db, action.spaceId, action.participantIds, current.capacity);
      if (!participants.ok) return participants;
      const event = { ...current, participantIds: participants.value, updatedAt: ctx.now };
      return ok(
        commit(
          { ...db, events: db.events.map((item) => (item.id === event.id ? event : item)) },
          action.spaceId,
          "setEventParticipants",
          { name: event.title, count: String(event.participantIds.length) },
          ctx,
        ),
      );
    }
    case "duplicateEvent": {
      const current = db.events.find((item) => item.id === action.eventId && item.spaceId === action.spaceId);
      if (!current) return err("NOT_FOUND", { entity: "event" });
      const event: AdeEvent = {
        ...structuredClone(current),
        id: ctx.newId(),
        title: `${current.title}${action.titleSuffix}`,
        status: "draft",
        duplicatedFromId: current.id,
        createdAt: ctx.now,
        updatedAt: ctx.now,
      };
      return ok(
        commit({ ...db, events: [...db.events, event] }, action.spaceId, "duplicateEvent", { name: event.title }, ctx),
      );
    }
    case "deleteEvent": {
      const event = db.events.find((item) => item.id === action.eventId && item.spaceId === action.spaceId);
      if (!event) return err("NOT_FOUND", { entity: "event" });
      if (event.status !== "draft") return err("IN_USE", { entity: "event", reason: "status" });
      if (db.attendance.some((item) => item.eventId === event.id)) {
        return err("IN_USE", { entity: "event", reason: "attendance" });
      }
      if (db.volunteering.some((item) => item.eventId === event.id)) {
        return err("IN_USE", { entity: "event", reason: "volunteering" });
      }
      const next = tombstone(
        { ...db, events: db.events.filter((item) => item.id !== event.id) },
        "event",
        event,
        event.id,
        ctx,
      );
      return ok(commit(next, action.spaceId, "deleteEvent", { name: event.title }, ctx));
    }
    case "setAttendance": {
      const event = db.events.find((item) => item.id === action.eventId && item.spaceId === action.spaceId);
      if (!event) return err("NOT_FOUND", { entity: "event" });
      if (event.status !== "scheduled" && event.status !== "completed") return err("ATTENDANCE_NOT_ALLOWED");
      const person = db.people.find((item) => item.id === action.personId && item.spaceId === action.spaceId);
      if (!person) return err("NOT_FOUND", { entity: "person" });
      if (!event.participantIds.includes(person.id)) return err("PERSON_NOT_PARTICIPANT");
      const note = action.note.trim();
      const current = db.attendance.find(
        (item) => item.eventId === event.id && item.personId === person.id,
      );
      if (current && current.state === action.state && current.note === note) return ok(db);
      const record: AttendanceRecord = current
        ? {
            ...current,
            state: action.state,
            note,
            updatedAt: ctx.now,
            history: [
              ...current.history,
              {
                at: ctx.now,
                actorId: ctx.actorId,
                previousState: current.state,
                nextState: action.state,
                previousNote: current.note,
                nextNote: note,
              },
            ],
          }
        : {
            id: ctx.newId(),
            spaceId: action.spaceId,
            eventId: event.id,
            personId: person.id,
            state: action.state,
            note,
            createdAt: ctx.now,
            updatedAt: ctx.now,
            history: [
              {
                at: ctx.now,
                actorId: ctx.actorId,
                previousState: null,
                nextState: action.state,
                previousNote: "",
                nextNote: note,
              },
            ],
          };
      const attendance = current
        ? db.attendance.map((item) => (item.id === record.id ? record : item))
        : [...db.attendance, record];
      return ok(
        commit(
          { ...db, attendance },
          action.spaceId,
          "setAttendance",
          { name: person.name, state: action.state },
          ctx,
        ),
      );
    }
    case "setVolunteerState": {
      const event = db.events.find((item) => item.id === action.eventId && item.spaceId === action.spaceId);
      if (!event) return err("NOT_FOUND", { entity: "event" });
      if (event.status === "cancelled") return err("VOLUNTEER_NOT_ALLOWED");
      const person = db.people.find((item) => item.id === action.personId && item.spaceId === action.spaceId);
      if (!person) return err("NOT_FOUND", { entity: "person" });
      const current = db.volunteering.find(
        (item) => item.eventId === event.id && item.personId === person.id,
      );
      const from = current?.state ?? null;
      if (!canTransitionVolunteer(from, action.state)) {
        return err("INVALID_TRANSITION", { from: from ?? "none", to: action.state });
      }
      const entering =
        CAPACITY_STATES.has(action.state) && (from === null || !CAPACITY_STATES.has(from));
      if (entering && event.volunteerCapacity !== null) {
        const used = consumingVolunteerCount(db, event.id, person.id);
        if (used + 1 > event.volunteerCapacity) {
          return err("CAPACITY_EXCEEDED", {
            capacity: String(event.volunteerCapacity),
            used: String(used),
          });
        }
      }
      const note = action.note.trim();
      if (current && current.state === action.state && current.note === note) return ok(db);
      const record: VolunteerRecord = current
        ? {
            ...current,
            state: action.state,
            note,
            updatedAt: ctx.now,
            history: [
              ...current.history,
              {
                at: ctx.now,
                actorId: ctx.actorId,
                previousState: current.state,
                nextState: action.state,
                previousNote: current.note,
                nextNote: note,
              },
            ],
          }
        : {
            id: ctx.newId(),
            spaceId: action.spaceId,
            eventId: event.id,
            personId: person.id,
            state: action.state,
            note,
            createdAt: ctx.now,
            updatedAt: ctx.now,
            history: [
              {
                at: ctx.now,
                actorId: ctx.actorId,
                previousState: null,
                nextState: action.state,
                previousNote: "",
                nextNote: note,
              },
            ],
          };
      const volunteering = current
        ? db.volunteering.map((item) => (item.id === record.id ? record : item))
        : [...db.volunteering, record];
      return ok(
        commit(
          { ...db, volunteering },
          action.spaceId,
          "setVolunteerState",
          { name: person.name, state: action.state },
          ctx,
        ),
      );
    }
    case "createTemplate": {
      const name = cleanName(action.name);
      if (!name.ok) return name;
      const elements = withIds(action.elements, ctx);
      const valid = validateElements(db, action.spaceId, elements, action.backgroundAssetId);
      if (!valid.ok) return valid;
      const template: DocumentTemplate = {
        id: ctx.newId(),
        spaceId: action.spaceId,
        name: name.value,
        description: action.description?.trim() ?? "",
        pageSize: action.pageSize,
        backgroundAssetId: action.backgroundAssetId,
        elements,
        createdAt: ctx.now,
        updatedAt: ctx.now,
      };
      return ok(
        commit({ ...db, templates: [...db.templates, template] }, action.spaceId, "createTemplate", { name: template.name }, ctx),
      );
    }
    case "updateTemplate": {
      const name = cleanName(action.name);
      if (!name.ok) return name;
      const current = db.templates.find((item) => item.id === action.templateId && item.spaceId === action.spaceId);
      if (!current) return err("NOT_FOUND", { entity: "template" });
      const elements = withIds(action.elements, ctx);
      const valid = validateElements(db, action.spaceId, elements, action.backgroundAssetId);
      if (!valid.ok) return valid;
      const template: DocumentTemplate = {
        ...current,
        name: name.value,
        description: action.description.trim(),
        pageSize: action.pageSize,
        backgroundAssetId: action.backgroundAssetId,
        elements,
        updatedAt: ctx.now,
      };
      return ok(
        commit(
          { ...db, templates: db.templates.map((item) => (item.id === template.id ? template : item)) },
          action.spaceId,
          "updateTemplate",
          { name: template.name },
          ctx,
        ),
      );
    }
    case "deleteTemplate": {
      const template = db.templates.find((item) => item.id === action.templateId && item.spaceId === action.spaceId);
      if (!template) return err("NOT_FOUND", { entity: "template" });
      const next = tombstone(
        { ...db, templates: db.templates.filter((item) => item.id !== template.id) },
        "template",
        template,
        template.id,
        ctx,
      );
      return ok(commit(next, action.spaceId, "deleteTemplate", { name: template.name }, ctx));
    }
    case "addAsset": {
      const name = cleanName(action.name);
      if (!name.ok) return name;
      if (!action.dataBase64.trim()) return err("INVALID_TEMPLATE");
      const asset: Asset = {
        id: ctx.newId(),
        spaceId: action.spaceId,
        name: name.value,
        mime: action.mime,
        dataBase64: action.dataBase64.trim(),
        createdAt: ctx.now,
        deletedAt: null,
      };
      return ok(commit({ ...db, assets: [...db.assets, asset] }, action.spaceId, "addAsset", { name: asset.name }, ctx));
    }
    case "deleteAsset": {
      const asset = db.assets.find((item) => item.id === action.assetId && item.spaceId === action.spaceId);
      if (!asset || asset.deletedAt) return err("NOT_FOUND", { entity: "asset" });
      const used = db.templates.some(
        (template) =>
          template.spaceId === action.spaceId &&
          (template.backgroundAssetId === asset.id ||
            template.elements.some((element) => element.type === "image" && element.assetId === asset.id)),
      );
      if (used) return err("ASSET_IN_USE");
      const next = {
        ...db,
        assets: db.assets.map((item) =>
          item.id === asset.id ? { ...item, deletedAt: ctx.now } : item,
        ),
      };
      return ok(commit(next, action.spaceId, "deleteAsset", { name: asset.name }, ctx));
    }
    case "resolveConflict": {
      const conflict = db.conflicts.find(
        (item) => item.id === action.conflictId && item.spaceId === action.spaceId,
      );
      if (!conflict || conflict.resolution !== "pending") return err("NOT_FOUND", { entity: "conflict" });
      if (action.resolution === "kept-local") {
        return ok(
          commit(
            finishConflict(db, conflict, "kept-local", null, ctx),
            action.spaceId,
            "resolveConflict",
            { resolution: "kept-local" },
            ctx,
          ),
        );
      }
      if (action.resolution === "kept-remote") {
        const applied = applyRemote(db, conflict, ctx);
        if (!applied.ok) return applied;
        return ok(
          commit(
            finishConflict(applied.value, conflict, "kept-remote", null, ctx),
            action.spaceId,
            "resolveConflict",
            { resolution: "kept-remote" },
            ctx,
          ),
        );
      }
      const copy = materialize(db, conflict, ctx);
      return ok(
        commit(
          finishConflict(copy.db, conflict, "kept-both", copy.materializedId, ctx),
          action.spaceId,
          "resolveConflict",
          { resolution: "kept-both" },
          ctx,
        ),
      );
    }
    default:
      return err("NOT_FOUND");
  }
}

function applyDemo(db: Database, ctx: ReduceContext): Result<Database> {
  const step = (current: Database, action: Action): Result<Database> => dispatch(current, action, ctx);
  let current = db;
  const must = (result: Result<Database>) => {
    if (!result.ok) throw new Error(result.error.code);
    current = result.value;
  };
  const beforeSpaces = new Set(current.spaces.map((space) => space.id));
  must(step(current, { type: "createSpace", name: "Demo" }));
  const spaceId = current.spaces.find((space) => !beforeSpaces.has(space.id))!.id;
  const addPerson = (name: string) => {
    must(step(current, { type: "createPerson", spaceId, name }));
    return current.people.find((person) => person.spaceId === spaceId && person.name === name)!;
  };
  const ada = addPerson("Ada");
  const ben = addPerson("Ben");
  const cia = addPerson("Cia");
  const dio = addPerson("Dio");
  must(
    step(current, {
      type: "updatePerson",
      spaceId,
      personId: dio.id,
      name: "Dio",
      email: "",
      notes: "",
      status: "inactive",
    }),
  );
  must(step(current, { type: "createGroup", spaceId, name: "Team" }));
  const groupId = current.groups.find((group) => group.spaceId === spaceId && group.name === "Team")!.id;
  must(step(current, { type: "addMembership", spaceId, groupId, personId: ada.id, startDate: "2026-01-01", endDate: null }));
  must(step(current, { type: "addMembership", spaceId, groupId, personId: ben.id, startDate: "2026-01-01", endDate: "2026-03-31" }));
  must(step(current, { type: "addMembership", spaceId, groupId, personId: cia.id, startDate: "2026-04-01", endDate: null }));
  must(step(current, { type: "createPeriod", spaceId, name: "Spring", startDate: "2026-01-01", endDate: "2026-06-30" }));
  must(step(current, { type: "createComponent", spaceId, name: "Service" }));
  const componentId = current.components.find((item) => item.spaceId === spaceId && item.name === "Service")!.id;
  must(step(current, { type: "createCategory", spaceId, componentId, name: "Kitchen" }));
  const categoryId = current.categories.find((item) => item.spaceId === spaceId && item.name === "Kitchen")!.id;
  const addEvent = (title: string, date: string, participantIds: string[], volunteerCapacity: number | null = null) => {
    must(
      step(current, {
        type: "createEvent",
        spaceId,
        title,
        date,
        componentId,
        categoryId,
        capacity: null,
        volunteerCapacity,
        countsForAttendance: true,
        participantIds,
      }),
    );
    return current.events.find((event) => event.spaceId === spaceId && event.title === title)!;
  };
  const feb = addEvent("February service", "2026-02-01", [ada.id, ben.id, cia.id]);
  const mar = addEvent("March service", "2026-03-01", [ada.id, ben.id]);
  const apr = addEvent("April service", "2026-04-01", [ada.id, ben.id]);
  const may = addEvent("May social", "2026-05-01", [ada.id]);
  const jun = addEvent("June service", "2026-06-01", [ada.id, cia.id], 2);
  for (const event of [feb, mar, apr, may, jun]) {
    must(step(current, { type: "setEventStatus", spaceId, eventId: event.id, status: "scheduled" }));
  }
  must(step(current, { type: "setEventStatus", spaceId, eventId: jun.id, status: "completed" }));
  const mayEvent = current.events.find((event) => event.id === may.id)!;
  must(
    step(current, {
      type: "updateEvent",
      spaceId,
      eventId: may.id,
      title: mayEvent.title,
      description: mayEvent.description,
      date: mayEvent.date,
      componentId: mayEvent.componentId,
      categoryId: mayEvent.categoryId,
      capacity: mayEvent.capacity,
      volunteerCapacity: mayEvent.volunteerCapacity,
      countsForAttendance: false,
    }),
  );
  const mark = (eventId: string, personId: string, state: AttendanceState) => {
    must(step(current, { type: "setAttendance", spaceId, eventId, personId, state, note: "" }));
  };
  mark(feb.id, ada.id, "present");
  mark(feb.id, ben.id, "absent");
  mark(feb.id, cia.id, "excused");
  mark(mar.id, ada.id, "present");
  mark(mar.id, ben.id, "pending");
  mark(apr.id, ada.id, "absent");
  mark(may.id, ada.id, "absent");
  mark(jun.id, ada.id, "present");
  mark(jun.id, cia.id, "present");
  must(step(current, { type: "setEventStatus", spaceId, eventId: apr.id, status: "cancelled" }));
  const volunteer = (personId: string, state: VolunteerState) => {
    must(step(current, { type: "setVolunteerState", spaceId, eventId: feb.id, personId, state, note: "" }));
  };
  volunteer(ada.id, "interested");
  volunteer(ada.id, "selected");
  volunteer(ada.id, "completed");
  volunteer(ben.id, "interested");
  volunteer(ben.id, "declined");
  return ok(current);
}

export function exportForTestSanitize(value: unknown): Result<Database> {
  return sanitizeDatabase(value);
}

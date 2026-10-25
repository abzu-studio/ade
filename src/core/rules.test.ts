import { describe, expect, it } from "vitest";
import { daysBetween } from "@/core/dates";
import { membersAt } from "@/core/groups";
import { planDocument } from "@/core/documents";
import { attendanceByPerson, computeAttendance } from "@/core/attendance";
import { createEmptyDatabase, dispatch, type Action } from "@/core/reduce";
import { toBackup, toSyncBundle } from "@/core/transfer";
import type { Database, ReduceContext } from "@/core/types";
import { VOLUNTEER_WEIGHTS } from "@/core/constants";
import { suggestVolunteers } from "@/core/volunteering";
import { sanitizeDatabase } from "@/core/validate";

function harness(now = "2026-06-15T15:00:00.000Z") {
  let serial = 0;
  const ctx: ReduceContext = {
    now,
    actorId: "actor-1",
    newId: () => `id-${++serial}`,
  };
  let db = createEmptyDatabase(ctx.actorId, ctx.now);
  const act = (action: Action) => {
    const result = dispatch(db, action, ctx);
    if (!result.ok) {
      throw new Error(`${action.type} ${result.error.code}`);
    }
    db = result.value;
    return db;
  };
  const fail = (action: Action) => {
    const result = dispatch(db, action, ctx);
    if (result.ok) throw new Error(`${action.type} should have failed`);
    return result.error;
  };
  return {
    ctx,
    act,
    fail,
    get db() {
      return db;
    },
    set db(next: Database) {
      db = next;
    },
  };
}

describe("attendance formula", () => {
  it("counts present over present plus absent and excludes the rest", () => {
    const app = harness();
    app.act({ type: "loadDemo" });
    const space = app.db.spaces[0];
    const period = app.db.periods[0];
    const ada = app.db.people.find((person) => person.name === "Ada")!;
    const ben = app.db.people.find((person) => person.name === "Ben")!;
    const cia = app.db.people.find((person) => person.name === "Cia")!;
    const adaStats = computeAttendance(app.db, {
      spaceId: space.id,
      periodId: period.id,
      personId: ada.id,
    });
    expect(adaStats.formula).toBe("present / (present + absent)");
    expect(adaStats.present).toBe(3);
    expect(adaStats.absent).toBe(0);
    expect(adaStats.percentage).toBe(1);
    expect(adaStats.excused).toBe(0);
    expect(adaStats.excludedCancelled).toBe(1);
    expect(adaStats.excludedNotCounting).toBe(1);

    const benStats = computeAttendance(app.db, {
      spaceId: space.id,
      periodId: period.id,
      personId: ben.id,
    });
    expect(benStats.present).toBe(0);
    expect(benStats.absent).toBe(1);
    expect(benStats.pending).toBe(1);
    expect(benStats.percentage).toBe(0);

    const ciaStats = computeAttendance(app.db, {
      spaceId: space.id,
      periodId: period.id,
      personId: cia.id,
    });
    expect(ciaStats.present).toBe(1);
    expect(ciaStats.excused).toBe(1);
    expect(ciaStats.denominator).toBe(1);
    expect(ciaStats.percentage).toBe(1);
  });

  it("does not invent an absence when a person is not on the list or has no mark", () => {
    const app = harness();
    app.act({ type: "createSpace", name: "Hall" });
    const spaceId = app.db.spaces[0].id;
    app.act({ type: "createPerson", spaceId, name: "Ada" });
    app.act({ type: "createPerson", spaceId, name: "Bea" });
    const ada = app.db.people.find((person) => person.name === "Ada")!;
    const bea = app.db.people.find((person) => person.name === "Bea")!;
    app.act({ type: "createComponent", spaceId, name: "Work" });
    const componentId = app.db.components[0].id;
    app.act({
      type: "createEvent",
      spaceId,
      title: "Shift",
      date: "2026-02-02",
      componentId,
      categoryId: null,
      capacity: null,
      volunteerCapacity: null,
      countsForAttendance: true,
      participantIds: [ada.id],
    });
    const eventId = app.db.events[0].id;
    app.act({ type: "setEventStatus", spaceId, eventId, status: "scheduled" });
    const open = computeAttendance(app.db, { spaceId, eventId, personId: ada.id });
    expect(open.unrecorded).toBe(1);
    expect(open.absent).toBe(0);
    expect(open.percentage).toBeNull();

    app.db = {
      ...app.db,
      attendance: [
        ...app.db.attendance,
        {
          id: "stray",
          spaceId,
          eventId,
          personId: bea.id,
          state: "present",
          note: "",
          history: [],
          createdAt: app.ctx.now,
          updatedAt: app.ctx.now,
        },
      ],
    };
    const stray = computeAttendance(app.db, { spaceId, eventId });
    expect(stray.present).toBe(0);
    expect(stray.lines.some((line) => line.personId === bea.id && line.reason === "not-participant")).toBe(true);
  });

  it("pools counts with the same formula instead of averaging percentages", () => {
    const app = harness();
    app.act({ type: "createSpace", name: "Hall" });
    const spaceId = app.db.spaces[0].id;
    app.act({ type: "createPerson", spaceId, name: "A" });
    app.act({ type: "createPerson", spaceId, name: "B" });
    const [a, b] = app.db.people;
    app.act({ type: "createComponent", spaceId, name: "Work" });
    const componentId = app.db.components[0].id;
    const dates = ["2026-01-01", "2026-01-02", "2026-01-03", "2026-01-04"];
    const ids = dates.map((date, index) => {
      app.act({
        type: "createEvent",
        spaceId,
        title: `E${index}`,
        date,
        componentId,
        categoryId: null,
        capacity: null,
        volunteerCapacity: null,
        countsForAttendance: true,
        participantIds: index === 0 ? [a.id] : [b.id],
      });
      const eventId = app.db.events.find((event) => event.title === `E${index}`)!.id;
      app.act({ type: "setEventStatus", spaceId, eventId, status: "scheduled" });
      return eventId;
    });
    app.act({ type: "setAttendance", spaceId, eventId: ids[0], personId: a.id, state: "present", note: "" });
    for (const eventId of ids.slice(1)) {
      app.act({ type: "setAttendance", spaceId, eventId, personId: b.id, state: "absent", note: "" });
    }
    const pooled = computeAttendance(app.db, { spaceId });
    expect(pooled.present).toBe(1);
    expect(pooled.absent).toBe(3);
    expect(pooled.percentage).toBe(0.25);
    const rows = attendanceByPerson(app.db, { spaceId });
    expect(rows.map((row) => row.breakdown.percentage)).toEqual([1, 0]);
  });

  it("uses group membership on the event date", () => {
    const app = harness();
    app.act({ type: "loadDemo" });
    const space = app.db.spaces[0];
    const period = app.db.periods[0];
    const group = app.db.groups[0];
    const cia = app.db.people.find((person) => person.name === "Cia")!;
    const stats = computeAttendance(app.db, {
      spaceId: space.id,
      periodId: period.id,
      groupId: group.id,
      personId: cia.id,
    });
    expect(stats.excludedNotMember).toBe(1);
    expect(stats.present).toBe(1);
    expect(stats.percentage).toBe(1);
    expect(membersAt(app.db, group.id, "2026-02-01").map((person) => person.name)).toEqual(["Ada", "Ben"]);
    expect(membersAt(app.db, group.id, "2026-05-01").map((person) => person.name)).toEqual(["Ada", "Cia"]);
  });

  it("rejects overlapping memberships and an end before the start", () => {
    const app = harness();
    app.act({ type: "createSpace", name: "Hall" });
    const spaceId = app.db.spaces[0].id;
    app.act({ type: "createPerson", spaceId, name: "Ada" });
    app.act({ type: "createGroup", spaceId, name: "Team" });
    const personId = app.db.people[0].id;
    const groupId = app.db.groups[0].id;
    app.act({ type: "addMembership", spaceId, groupId, personId, startDate: "2026-01-01", endDate: "2026-01-31" });
    expect(
      app.fail({
        type: "addMembership",
        spaceId,
        groupId,
        personId,
        startDate: "2026-01-31",
        endDate: null,
      }).code,
    ).toBe("OVERLAPPING_MEMBERSHIP");
    expect(
      app.fail({
        type: "addMembership",
        spaceId,
        groupId,
        personId,
        startDate: "2026-03-02",
        endDate: "2026-03-01",
      }).code,
    ).toBe("INVALID_DATE_RANGE");
    expect(daysBetween("2026-02-01", "2026-06-01")).toBe(120);
  });
});

describe("events, attendance entry, and history", () => {
  it("duplicates an event without copying attendance and can undo", () => {
    const app = harness();
    app.act({ type: "createSpace", name: "Hall" });
    const spaceId = app.db.spaces[0].id;
    app.act({ type: "createPerson", spaceId, name: "Ada" });
    app.act({ type: "createComponent", spaceId, name: "Work" });
    const personId = app.db.people[0].id;
    const componentId = app.db.components[0].id;
    app.act({
      type: "createEvent",
      spaceId,
      title: "Shift",
      date: "2026-02-02",
      componentId,
      categoryId: null,
      capacity: 1,
      volunteerCapacity: 1,
      countsForAttendance: true,
      participantIds: [personId],
    });
    const eventId = app.db.events[0].id;
    app.act({ type: "setEventStatus", spaceId, eventId, status: "scheduled" });
    app.act({ type: "setAttendance", spaceId, eventId, personId, state: "present", note: "on time" });
    app.act({ type: "setAttendance", spaceId, eventId, personId, state: "present", note: "late" });
    expect(app.db.attendance[0].history).toHaveLength(2);
    app.act({ type: "duplicateEvent", spaceId, eventId, titleSuffix: " (copy)" });
    const copy = app.db.events.find((event) => event.title === "Shift (copy)")!;
    expect(copy.status).toBe("draft");
    expect(copy.participantIds).toEqual([personId]);
    expect(copy.duplicatedFromId).toBe(eventId);
    expect(app.db.attendance.every((record) => record.eventId !== copy.id)).toBe(true);
    expect(app.fail({ type: "setAttendance", spaceId, eventId: copy.id, personId, state: "absent", note: "" }).code).toBe(
      "ATTENDANCE_NOT_ALLOWED",
    );
    expect(app.fail({ type: "setEventParticipants", spaceId, eventId, participantIds: [personId, personId] }).code).toBe(
      "DUPLICATE_PARTICIPANT",
    );
    app.act({ type: "renameSpace", spaceId, name: "Renamed" });
    app.act({ type: "undo", spaceId });
    expect(app.db.spaces[0].name).toBe("Hall");
    app.act({ type: "redo", spaceId });
    expect(app.db.spaces[0].name).toBe("Renamed");
    app.act({ type: "undo", spaceId });
    app.act({ type: "renameSpace", spaceId, name: "Other" });
    expect(app.fail({ type: "redo", spaceId }).code).toBe("NOTHING_TO_REDO");
    expect(app.db.spaces[0].name).toBe("Other");
  });

  it("undo of the first revision removes the space and redo restores it", () => {
    const app = harness();
    app.act({ type: "createSpace", name: "Hall" });
    const spaceId = app.db.spaces[0].id;
    app.act({ type: "undo", spaceId });
    expect(app.db.spaces).toHaveLength(0);
    app.act({ type: "redo", spaceId });
    expect(app.db.spaces.map((space) => space.name)).toEqual(["Hall"]);
  });
});

describe("volunteering", () => {
  it("ranks previous participation with an explicit score and never selects automatically", () => {
    const app = harness();
    app.act({ type: "loadDemo" });
    const event = app.db.events.find((item) => item.title === "June service")!;
    const before = app.db.volunteering.length;
    const ranked = suggestVolunteers(app.db, event.id);
    expect(app.db.volunteering.length).toBe(before);
    expect(ranked.map((item) => item.name)).toEqual(["Ada", "Cia", "Ben"]);
    expect(ranked.find((item) => item.name === "Dio")).toBeUndefined();
    const ada = ranked[0];
    expect(ada.score).toBe(
      VOLUNTEER_WEIGHTS.completed +
        VOLUNTEER_WEIGHTS.recentCompleted +
        VOLUNTEER_WEIGHTS.sameComponentCompleted +
        VOLUNTEER_WEIGHTS.attendancePresent * 2,
    );
    expect(ada.factors.map((factor) => factor.code)).toEqual([
      "completed",
      "recentCompleted",
      "sameComponentCompleted",
      "attendancePresent",
    ]);
    expect(ranked.find((item) => item.name === "Cia")?.factors[0].code).toBe("no-history");
    expect(ranked.find((item) => item.name === "Ben")?.score).toBe(VOLUNTEER_WEIGHTS.declined);

    const spaceId = event.spaceId;
    app.act({
      type: "setVolunteerState",
      spaceId,
      eventId: event.id,
      personId: app.db.people.find((person) => person.name === "Cia")!.id,
      state: "selected",
      note: "",
    });
    const benId = app.db.people.find((person) => person.name === "Ben")!.id;
    app.act({
      type: "setVolunteerState",
      spaceId,
      eventId: event.id,
      personId: benId,
      state: "selected",
      note: "",
    });
    app.act({
      type: "setVolunteerState",
      spaceId,
      eventId: event.id,
      personId: app.db.people.find((person) => person.name === "Ada")!.id,
      state: "interested",
      note: "",
    });
    expect(
      app.fail({
        type: "setVolunteerState",
        spaceId,
        eventId: event.id,
        personId: app.db.people.find((person) => person.name === "Ada")!.id,
        state: "selected",
        note: "",
      }).code,
    ).toBe("CAPACITY_EXCEEDED");
    app.act({
      type: "setVolunteerState",
      spaceId,
      eventId: event.id,
      personId: benId,
      state: "completed",
      note: "",
    });
    expect(
      app.fail({
        type: "setVolunteerState",
        spaceId,
        eventId: event.id,
        personId: benId,
        state: "declined",
        note: "",
      }).code,
    ).toBe("INVALID_TRANSITION");
  });
});

describe("collaboration", () => {
  it("keeps both versions of a conflicting edit and both versions of an attendance mark", () => {
    const app = harness();
    app.act({ type: "createSpace", name: "Hall" });
    const spaceId = app.db.spaces[0].id;
    app.act({ type: "createPerson", spaceId, name: "Ada" });
    app.act({ type: "createComponent", spaceId, name: "Work" });
    const person = app.db.people[0];
    const componentId = app.db.components[0].id;
    app.act({
      type: "createEvent",
      spaceId,
      title: "Shift",
      date: "2026-02-02",
      componentId,
      categoryId: null,
      capacity: null,
      volunteerCapacity: null,
      countsForAttendance: true,
      participantIds: [person.id],
    });
    const eventId = app.db.events[0].id;
    app.act({ type: "setEventStatus", spaceId, eventId, status: "scheduled" });
    app.act({ type: "setAttendance", spaceId, eventId, personId: person.id, state: "present", note: "" });

    let remote = structuredClone(app.db);
    let remoteSerial = 0;
    const remoteCtx: ReduceContext = {
      now: "2026-07-01T00:00:00.000Z",
      actorId: "actor-2",
      newId: () => `remote-${++remoteSerial}`,
    };
    const remoteDispatch = (action: Action) => {
      const result = dispatch(remote, action, remoteCtx);
      if (!result.ok) throw new Error(result.error.code);
      remote = result.value;
    };
    remoteDispatch({
      type: "updatePerson",
      spaceId,
      personId: person.id,
      name: "Ana",
      email: "",
      notes: "",
      status: "active",
    });
    remoteDispatch({
      type: "setAttendance",
      spaceId,
      eventId,
      personId: person.id,
      state: "absent",
      note: "remote",
    });
    remoteDispatch({ type: "createPerson", spaceId, name: "New" });
    app.act({
      type: "updatePerson",
      spaceId,
      personId: person.id,
      name: "Adela",
      email: "",
      notes: "",
      status: "active",
    });
    const bundle = toSyncBundle(remote, spaceId, remoteCtx.now);
    if (!bundle.ok) throw new Error("bundle");
    app.act({ type: "importSync", bundle: bundle.value });
    expect(app.db.people.find((item) => item.id === person.id)?.name).toBe("Adela");
    expect(app.db.people.some((item) => item.name === "New")).toBe(true);
    expect(app.db.attendance).toHaveLength(1);
    expect(app.db.attendance[0].state).toBe("present");
    const personConflict = app.db.conflicts.find((conflict) => conflict.entityType === "person");
    const attendanceConflict = app.db.conflicts.find((conflict) => conflict.entityType === "attendance");
    expect(personConflict?.resolution).toBe("pending");
    expect((personConflict?.remote as { name: string }).name).toBe("Ana");
    expect((personConflict?.local as { name: string }).name).toBe("Adela");
    expect((attendanceConflict?.remote as { state: string }).state).toBe("absent");
    expect((attendanceConflict?.local as { state: string }).state).toBe("present");

    app.act({
      type: "resolveConflict",
      spaceId,
      conflictId: personConflict!.id,
      resolution: "kept-both",
    });
    expect(app.db.people.some((item) => item.name === "Ana (conflict)")).toBe(true);
    expect(app.db.people.find((item) => item.id === person.id)?.name).toBe("Adela");
    app.act({
      type: "resolveConflict",
      spaceId,
      conflictId: attendanceConflict!.id,
      resolution: "kept-both",
    });
    expect(app.db.attendance).toHaveLength(1);
    expect(app.db.conflicts.find((conflict) => conflict.id === attendanceConflict!.id)?.resolution).toBe("kept-both");

    app.act({ type: "importSync", bundle: bundle.value });
    expect(app.db.conflicts.filter((conflict) => conflict.entityType === "person" && conflict.resolution === "pending")).toHaveLength(1);
  });

  it("applies a remote delete when the local record is unchanged, and keeps both when it changed", () => {
    const app = harness();
    app.act({ type: "createSpace", name: "Hall" });
    const spaceId = app.db.spaces[0].id;
    app.act({ type: "createPerson", spaceId, name: "Ada" });
    app.act({ type: "createPerson", spaceId, name: "Bea" });
    const ada = app.db.people.find((person) => person.name === "Ada")!;
    const bea = app.db.people.find((person) => person.name === "Bea")!;
    let remote = structuredClone(app.db);
    const remoteCtx: ReduceContext = {
      now: "2026-07-01T00:00:00.000Z",
      actorId: "actor-2",
      newId: () => "remote-tomb",
    };
    const deleted = dispatch(remote, { type: "deletePerson", spaceId, personId: bea.id }, remoteCtx);
    if (!deleted.ok) throw new Error(deleted.error.code);
    remote = deleted.value;
    const bundle = toSyncBundle(remote, spaceId, remoteCtx.now);
    if (!bundle.ok) throw new Error("bundle");
    app.act({
      type: "updatePerson",
      spaceId,
      personId: ada.id,
      name: "Ada P",
      email: "",
      notes: "",
      status: "active",
    });
    const remoteAda = structuredClone(remote);
    const removedAda = dispatch(
      remoteAda,
      { type: "deletePerson", spaceId, personId: ada.id },
      { ...remoteCtx, newId: () => "remote-ada", now: "2026-07-02T00:00:00.000Z" },
    );
    if (!removedAda.ok) throw new Error(removedAda.error.code);
    app.act({ type: "importSync", bundle: bundle.value });
    expect(app.db.people.some((person) => person.id === bea.id)).toBe(false);
    expect(app.db.tombstones.some((stone) => stone.entityId === bea.id)).toBe(true);
    const adaBundle = toSyncBundle(removedAda.value, spaceId, "2026-07-02T00:00:00.000Z");
    if (!adaBundle.ok) throw new Error("ada bundle");
    app.act({ type: "importSync", bundle: adaBundle.value });
    expect(app.db.people.some((person) => person.id === ada.id)).toBe(true);
    expect(
      app.db.conflicts.some(
        (conflict) => conflict.entityType === "person" && conflict.remoteDeleted && conflict.resolution === "pending",
      ),
    ).toBe(true);
  });
});

describe("documents and backup", () => {
  it("plans a multi-page document from live participation data", () => {
    const app = harness();
    app.act({ type: "loadDemo" });
    const spaceId = app.db.spaces[0].id;
    const periodId = app.db.periods[0].id;
    app.act({
      type: "createTemplate",
      spaceId,
      name: "Summary",
      pageSize: "letter",
      backgroundAssetId: null,
      elements: [
        {
          type: "text",
          x: 40,
          y: 40,
          width: 200,
          height: 20,
          text: "",
          binding: "space.name",
          fontSize: 12,
          align: "left",
        },
        {
          type: "columns",
          x: 40,
          y: 80,
          width: 200,
          height: 30,
          columns: 1,
          gap: 0,
          binding: "period.participation",
          fontSize: 12,
        },
      ],
    });
    const template = app.db.templates[0];
    const planned = planDocument(app.db, template, {
      spaceId,
      periodId,
      eventId: null,
      groupId: null,
      generatedAt: "2026-06-15T15:00:00.000Z",
    });
    if (!planned.ok) throw new Error(planned.error.code);
    expect(planned.value.length).toBeGreaterThan(1);
    expect(planned.value[0].items.some((item) => item.kind === "text" && item.text === "Demo")).toBe(true);
    const lines = planned.value.flatMap((page) =>
      page.items.filter((item) => item.kind === "text").map((item) => item.text),
    );
    expect(lines.some((line) => line.startsWith("Ada - 100.0% (3/3)"))).toBe(true);
    expect(lines.some((line) => line.startsWith("Ben - 0.0% (0/1)"))).toBe(true);

    const backup = toBackup(app.db, app.ctx.now);
    const restored = sanitizeDatabase(backup.database);
    expect(restored.ok).toBe(true);
    expect(dispatch(app.db, { type: "importBackup", backup: { format: "nope" } }, app.ctx).ok).toBe(false);
  });

  it("rejects a category from another component", () => {
    const app = harness();
    app.act({ type: "createSpace", name: "Hall" });
    const spaceId = app.db.spaces[0].id;
    app.act({ type: "createComponent", spaceId, name: "A" });
    app.act({ type: "createComponent", spaceId, name: "B" });
    const [a, b] = app.db.components;
    app.act({ type: "createCategory", spaceId, componentId: a.id, name: "Kitchen" });
    const categoryId = app.db.categories[0].id;
    expect(
      app.fail({
        type: "createEvent",
        spaceId,
        title: "Shift",
        date: "2026-02-02",
        componentId: b.id,
        categoryId,
        capacity: null,
        volunteerCapacity: null,
        countsForAttendance: true,
      }).code,
    ).toBe("CATEGORY_COMPONENT_MISMATCH");
  });
});

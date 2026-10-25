export const DATABASE_FORMAT = "ade-db-v1" as const;
export const SYNC_FORMAT = "ade-sync-v1" as const;
export const BACKUP_FORMAT = "ade-backup-v1" as const;

export type Locale = "en" | "es";
export type PersonStatus = "active" | "inactive";
export type EventStatus = "draft" | "scheduled" | "completed" | "cancelled";
export type AttendanceState = "present" | "absent" | "excused" | "pending";
export type VolunteerState =
  | "interested"
  | "selected"
  | "completed"
  | "declined"
  | "absent";
export type ExclusionReason =
  | "not-participant"
  | "not-member-on-date"
  | "cancelled"
  | "not-counting"
  | "unrecorded"
  | "pending"
  | "excused";
export type EntityType =
  | "space"
  | "person"
  | "group"
  | "membership"
  | "period"
  | "component"
  | "category"
  | "event"
  | "attendance"
  | "volunteering"
  | "template"
  | "asset";
export type AssetMime = "image/png" | "image/jpeg" | "application/pdf";
export type PageSize = "letter" | "a4";
export type TextAlign = "left" | "center" | "right";
export type ConflictResolution =
  | "pending"
  | "kept-local"
  | "kept-remote"
  | "kept-both";

export type TextBinding =
  | "space.name"
  | "period.name"
  | "period.range"
  | "event.title"
  | "event.date"
  | "event.component"
  | "event.category"
  | "event.status"
  | "group.name"
  | "generatedAt";

export type ListBinding =
  | "event.participants"
  | "event.attendance"
  | "event.volunteers"
  | "period.participation"
  | "group.members";

export interface Actor {
  id: string;
  name: string;
}

export interface Space {
  id: string;
  name: string;
  createdAt: string;
  updatedAt: string;
}

export interface Person {
  id: string;
  spaceId: string;
  name: string;
  email: string;
  notes: string;
  status: PersonStatus;
  createdAt: string;
  updatedAt: string;
}

export interface Group {
  id: string;
  spaceId: string;
  name: string;
  description: string;
  createdAt: string;
  updatedAt: string;
}

export interface GroupMembership {
  id: string;
  spaceId: string;
  groupId: string;
  personId: string;
  startDate: string;
  endDate: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface Period {
  id: string;
  spaceId: string;
  name: string;
  startDate: string;
  endDate: string;
  createdAt: string;
  updatedAt: string;
}

export interface ActivityComponent {
  id: string;
  spaceId: string;
  name: string;
  description: string;
  createdAt: string;
  updatedAt: string;
}

export interface Category {
  id: string;
  spaceId: string;
  componentId: string;
  name: string;
  description: string;
  createdAt: string;
  updatedAt: string;
}

export interface AdeEvent {
  id: string;
  spaceId: string;
  title: string;
  description: string;
  date: string;
  componentId: string;
  categoryId: string | null;
  participantIds: string[];
  capacity: number | null;
  countsForAttendance: boolean;
  status: EventStatus;
  volunteerCapacity: number | null;
  duplicatedFromId: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface AttendanceHistoryEntry {
  at: string;
  actorId: string;
  previousState: AttendanceState | null;
  nextState: AttendanceState;
  previousNote: string;
  nextNote: string;
}

export interface AttendanceRecord {
  id: string;
  spaceId: string;
  eventId: string;
  personId: string;
  state: AttendanceState;
  note: string;
  history: AttendanceHistoryEntry[];
  createdAt: string;
  updatedAt: string;
}

export interface VolunteerHistoryEntry {
  at: string;
  actorId: string;
  previousState: VolunteerState | null;
  nextState: VolunteerState;
  previousNote: string;
  nextNote: string;
}

export interface VolunteerRecord {
  id: string;
  spaceId: string;
  eventId: string;
  personId: string;
  state: VolunteerState;
  note: string;
  history: VolunteerHistoryEntry[];
  createdAt: string;
  updatedAt: string;
}

export interface TemplateTextElement {
  id: string;
  type: "text";
  x: number;
  y: number;
  width: number;
  height: number;
  text: string;
  binding: TextBinding | null;
  fontSize: number;
  align: TextAlign;
}

export interface TemplateImageElement {
  id: string;
  type: "image";
  x: number;
  y: number;
  width: number;
  height: number;
  assetId: string;
}

export interface TemplateColumnsElement {
  id: string;
  type: "columns";
  x: number;
  y: number;
  width: number;
  height: number;
  columns: number;
  gap: number;
  binding: ListBinding;
  fontSize: number;
}

export type TemplateElement =
  | TemplateTextElement
  | TemplateImageElement
  | TemplateColumnsElement;

export interface DocumentTemplate {
  id: string;
  spaceId: string;
  name: string;
  description: string;
  pageSize: PageSize;
  backgroundAssetId: string | null;
  elements: TemplateElement[];
  createdAt: string;
  updatedAt: string;
}

export interface Asset {
  id: string;
  spaceId: string;
  name: string;
  mime: AssetMime;
  dataBase64: string;
  createdAt: string;
  deletedAt: string | null;
}

export interface Tombstone {
  id: string;
  spaceId: string;
  entityType: EntityType;
  entityId: string;
  naturalKey: string;
  deletedAt: string;
  deletedBy: string;
  payload: unknown;
}

export interface ConflictRecord {
  id: string;
  spaceId: string;
  entityType: EntityType;
  key: string;
  localEntityId: string | null;
  remoteEntityId: string | null;
  local: unknown | null;
  remote: unknown | null;
  remoteDeleted: boolean;
  createdAt: string;
  resolvedAt: string | null;
  resolution: ConflictResolution;
  materializedId: string | null;
}

export interface SpaceSnapshot {
  space: Space;
  people: Person[];
  groups: Group[];
  memberships: GroupMembership[];
  periods: Period[];
  components: ActivityComponent[];
  categories: Category[];
  events: AdeEvent[];
  attendance: AttendanceRecord[];
  volunteering: VolunteerRecord[];
  templates: DocumentTemplate[];
  assets: Asset[];
  conflicts: ConflictRecord[];
  tombstones: Tombstone[];
}

export interface Revision {
  id: string;
  spaceId: string;
  at: string;
  actorId: string;
  action: string;
  params: Record<string, string>;
  snapshot: SpaceSnapshot;
}

export interface SpaceHistory {
  spaceId: string;
  revisionIds: string[];
  cursor: number;
}

export interface Database {
  format: typeof DATABASE_FORMAT;
  actor: Actor;
  locale: Locale;
  spaces: Space[];
  people: Person[];
  groups: Group[];
  memberships: GroupMembership[];
  periods: Period[];
  components: ActivityComponent[];
  categories: Category[];
  events: AdeEvent[];
  attendance: AttendanceRecord[];
  volunteering: VolunteerRecord[];
  templates: DocumentTemplate[];
  assets: Asset[];
  conflicts: ConflictRecord[];
  tombstones: Tombstone[];
  revisions: Revision[];
  histories: SpaceHistory[];
}

export interface SyncBundle {
  format: typeof SYNC_FORMAT;
  exportedAt: string;
  actor: Actor;
  snapshot: SpaceSnapshot;
  tombstones: Tombstone[];
}

export interface BackupFile {
  format: typeof BACKUP_FORMAT;
  exportedAt: string;
  database: Database;
}

export interface ReduceContext {
  now: string;
  actorId: string;
  newId: () => string;
}

export interface AttendanceLine {
  eventId: string;
  personId: string;
  outcome: "present" | "absent" | "excluded";
  reason: ExclusionReason | null;
  state: AttendanceState | null;
}

export interface AttendanceBreakdown {
  present: number;
  absent: number;
  excused: number;
  pending: number;
  unrecorded: number;
  excludedCancelled: number;
  excludedNotCounting: number;
  excludedNotParticipant: number;
  excludedNotMember: number;
  denominator: number;
  percentage: number | null;
  formula: "present / (present + absent)";
  lines: AttendanceLine[];
}

export interface AttendanceQuery {
  spaceId: string;
  periodId?: string | null;
  groupId?: string | null;
  componentId?: string | null;
  categoryId?: string | null;
  personId?: string | null;
  eventId?: string | null;
}

export type ScoreFactorCode =
  | "completed"
  | "recentCompleted"
  | "sameComponentCompleted"
  | "selected"
  | "priorInterested"
  | "interestedNow"
  | "declined"
  | "absent"
  | "attendancePresent"
  | "no-history";

export interface ScoreFactor {
  code: ScoreFactorCode;
  count: number;
  points: number;
}

export interface VolunteerSuggestion {
  personId: string;
  name: string;
  score: number;
  completedCount: number;
  eligible: boolean;
  factors: ScoreFactor[];
}

export interface DocumentLabels {
  unrecorded: string;
  attendance: Record<AttendanceState, string>;
  volunteer: Record<VolunteerState, string>;
  eventStatus: Record<EventStatus, string>;
  percent: (value: number | null) => string;
  counts: (present: number, absent: number) => string;
  separator: string;
}

export interface TemplateDataContext {
  spaceId: string;
  periodId: string | null;
  eventId: string | null;
  groupId: string | null;
  generatedAt: string;
}

export interface PlannedText {
  kind: "text";
  x: number;
  y: number;
  width: number;
  height: number;
  text: string;
  fontSize: number;
  align: TextAlign;
}

export interface PlannedImage {
  kind: "image";
  x: number;
  y: number;
  width: number;
  height: number;
  assetId: string;
}

export interface PlannedPage {
  width: number;
  height: number;
  backgroundAssetId: string | null;
  backgroundPageIndex: number;
  items: Array<PlannedText | PlannedImage>;
}

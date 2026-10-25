export type CoreErrorCode =
  | "NAME_REQUIRED"
  | "INVALID_DATE"
  | "INVALID_DATE_RANGE"
  | "NOT_FOUND"
  | "OVERLAPPING_MEMBERSHIP"
  | "CAPACITY_EXCEEDED"
  | "INVALID_CAPACITY"
  | "DUPLICATE_PARTICIPANT"
  | "CATEGORY_COMPONENT_MISMATCH"
  | "INVALID_TRANSITION"
  | "ATTENDANCE_NOT_ALLOWED"
  | "VOLUNTEER_NOT_ALLOWED"
  | "PERSON_NOT_PARTICIPANT"
  | "IN_USE"
  | "INVALID_TEMPLATE"
  | "INVALID_IMPORT"
  | "NOTHING_TO_UNDO"
  | "NOTHING_TO_REDO"
  | "ASSET_IN_USE"
  | "ASSET_NOT_FOUND"
  | "EVENT_LOCKED";

export interface CoreError {
  code: CoreErrorCode;
  params?: Record<string, string>;
}

export type Result<T> =
  | { ok: true; value: T }
  | { ok: false; error: CoreError };

export function ok<T>(value: T): Result<T> {
  return { ok: true, value };
}

export function err(
  code: CoreErrorCode,
  params?: Record<string, string>,
): Result<never> {
  return { ok: false, error: params ? { code, params } : { code } };
}

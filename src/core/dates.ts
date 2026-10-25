const DATE = /^(\d{4})-(\d{2})-(\d{2})$/;

export function isIsoDate(value: string): boolean {
  const match = DATE.exec(value);
  if (!match) return false;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const date = new Date(Date.UTC(year, month - 1, day));
  return (
    date.getUTCFullYear() === year &&
    date.getUTCMonth() === month - 1 &&
    date.getUTCDate() === day
  );
}

export function isIsoDateTime(value: string): boolean {
  if (!value) return false;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed);
}

/** Inclusive range. A null end means the range is still open. */
export function dateInRange(
  date: string,
  start: string,
  end: string | null,
): boolean {
  if (date < start) return false;
  if (end !== null && date > end) return false;
  return true;
}

export function rangesOverlap(
  aStart: string,
  aEnd: string | null,
  bStart: string,
  bEnd: string | null,
): boolean {
  const aStop = aEnd ?? "9999-12-31";
  const bStop = bEnd ?? "9999-12-31";
  return aStart <= bStop && bStart <= aStop;
}

export function daysBetween(earlier: string, later: string): number {
  const toUtc = (value: string) => {
    const [year, month, day] = value.split("-").map(Number);
    return Date.UTC(year, month - 1, day);
  };
  return Math.round((toUtc(later) - toUtc(earlier)) / 86_400_000);
}

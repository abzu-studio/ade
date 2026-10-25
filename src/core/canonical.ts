function sortValue(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(sortValue);
  if (value && typeof value === "object") {
    const source = value as Record<string, unknown>;
    const sorted: Record<string, unknown> = {};
    for (const key of Object.keys(source).sort()) {
      if (key === "updatedAt") continue;
      sorted[key] = sortValue(source[key]);
    }
    return sorted;
  }
  return value;
}

/** Stable comparison that ignores updatedAt so a touch is not a conflict. */
export function canonical(value: unknown): string {
  return JSON.stringify(sortValue(value));
}

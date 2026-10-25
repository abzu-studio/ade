"use client";

import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";
import { formatWhen } from "@/components/ade/labels";
import { useI18n } from "@/i18n";

export function RecordHistory({
  open,
  title,
  entries,
  onOpenChange,
}: {
  open: boolean;
  title: string;
  entries: Array<{
    at: string;
    previous: string | null;
    next: string;
    nextNote: string;
  }>;
  onOpenChange: (open: boolean) => void;
}) {
  const { t, locale } = useI18n();
  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent>
        <SheetHeader>
          <SheetTitle>{title}</SheetTitle>
          <SheetDescription>{t("attendance.history")}</SheetDescription>
        </SheetHeader>
        {entries.length === 0 ? (
          <p className="text-sm text-muted-foreground">{t("attendance.noHistory")}</p>
        ) : (
          <ul className="flex flex-col gap-3 px-4 text-sm">
            {entries.map((entry, index) => (
              <li key={`${entry.at}-${index}`} className="flex flex-col gap-1">
                <span className="text-muted-foreground">{formatWhen(entry.at, locale)}</span>
                <span>
                  {entry.previous ?? t("attendance.unrecorded")} → {entry.next}
                </span>
                {entry.nextNote ? <span>{entry.nextNote}</span> : null}
              </li>
            ))}
          </ul>
        )}
      </SheetContent>
    </Sheet>
  );
}

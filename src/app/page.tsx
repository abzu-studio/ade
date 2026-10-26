"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { useI18n } from "@/i18n";
import { isMacDesktop } from "@/lib/platform";
import { useApp } from "@/state/store";

export default function HomePage() {
  const { t } = useI18n();
  const { db, run } = useApp();
  const [name, setName] = useState("");
  const [mac, setMac] = useState<boolean | null>(null);
  useEffect(() => setMac(isMacDesktop()), []);
  const spaces = db.spaces.slice().sort((a, b) => a.name.localeCompare(b.name));

  return (
    <main className="ade-field min-h-screen p-3 md:p-4">
      <div className="ade-sheet mx-auto flex min-h-[calc(100vh-1.5rem)] max-w-3xl flex-col px-8 py-12 md:min-h-[calc(100vh-2rem)] md:px-12">
        <h1 className="ade-display text-[5.5rem] md:text-[8rem]">{t("app.name")}</h1>
        <p className="mt-4 max-w-md text-sm">{t("app.tagline")}</p>
        {mac === false ? (
          <div role="alert" className="mt-6 max-w-xl border-t border-[#e5c9b0] pt-3">
            <p className="ade-kicker">{t("app.name")}</p>
            <p className="mt-1 text-sm">{t("app.macNotice")}</p>
          </div>
        ) : null}
        <form
          className="mt-12 flex flex-wrap items-baseline gap-x-4 gap-y-2 border-b border-[#e5c9b0] py-3"
          onSubmit={(event) => {
            event.preventDefault();
            const result = run({ type: "createSpace", name }, t("common.saved"));
            if (result.ok) setName("");
          }}
        >
          <span className="ade-kicker">{t("spaces.create")}</span>
          <input
            className="ade-line min-w-48 flex-1"
            aria-label={t("common.name")}
            value={name}
            required
            onChange={(event) => setName(event.target.value)}
          />
          <button type="submit" className="ade-verb">
            {t("action.create")}
          </button>
        </form>
        {spaces.length === 0 ? (
          <p className="py-6 text-sm">{t("spaces.empty")}</p>
        ) : (
          <div>
            {spaces.map((space) => {
              const counts = spaceCounts(db, space.id, t);
              return (
                <div key={space.id} className="ade-row flex flex-wrap items-baseline gap-x-4 gap-y-2 py-3">
                  <span className="min-w-40 flex-1 text-lg">{space.name}</span>
                  {counts ? <span className="ade-kicker">{counts}</span> : null}
                  <Link href={`/space/${space.id}`} className="ade-verb">
                    {t("action.open")}
                  </Link>
                </div>
              );
            })}
          </div>
        )}
        <div className="mt-auto flex flex-col items-start gap-2 pt-10">
          <button type="button" className="ade-stamp" onClick={() => run({ type: "loadDemo" }, t("common.saved"))}>
            {t("spaces.demo")}
          </button>
          <p className="max-w-md text-sm">{t("spaces.demoHelp")}</p>
        </div>
      </div>
    </main>
  );
}

function spaceCounts(
  db: ReturnType<typeof useApp>["db"],
  spaceId: string,
  t: (key: "nav.people" | "nav.groups" | "nav.periods" | "taxonomy.component" | "nav.events" | "nav.documents") => string,
): string {
  const count = <T extends { spaceId: string }>(items: T[]) =>
    items.filter((item) => item.spaceId === spaceId).length;
  return (
    [
      [count(db.people), t("nav.people")],
      [count(db.groups), t("nav.groups")],
      [count(db.periods), t("nav.periods")],
      [count(db.components), t("taxonomy.component")],
      [count(db.events), t("nav.events")],
      [count(db.templates), t("nav.documents")],
    ] as const
  )
    .filter(([value]) => value > 0)
    .map(([value, label]) => `${label} ${value}`)
    .join(" · ");
}

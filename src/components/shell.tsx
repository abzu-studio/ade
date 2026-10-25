"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState, type ReactNode } from "react";
import { useSpaceData } from "@/components/ade/space";
import { useI18n } from "@/i18n";
import type { MessageKey } from "@/i18n/en";
import { isMacDesktop } from "@/lib/platform";
import { useApp } from "@/state/store";

const links: Array<{ href: string; key: MessageKey }> = [
  { href: "", key: "nav.overview" },
  { href: "/people", key: "nav.people" },
  { href: "/groups", key: "nav.groups" },
  { href: "/periods", key: "nav.periods" },
  { href: "/taxonomy", key: "nav.taxonomy" },
  { href: "/events", key: "nav.events" },
  { href: "/participation", key: "nav.participation" },
  { href: "/documents", key: "nav.documents" },
  { href: "/history", key: "nav.history" },
  { href: "/conflicts", key: "nav.conflicts" },
  { href: "/data", key: "nav.data" },
  { href: "/rules", key: "nav.rules" },
];

const sectionKey: Record<string, MessageKey> = {
  people: "nav.people",
  groups: "nav.groups",
  periods: "nav.periods",
  taxonomy: "nav.taxonomy",
  events: "nav.events",
  participation: "nav.participation",
  documents: "nav.documents",
  history: "nav.history",
  conflicts: "nav.conflicts",
  data: "nav.data",
  rules: "nav.rules",
};

export function Shell({ spaceId, children }: { spaceId: string; children: ReactNode }) {
  const pathname = usePathname();
  const { t, locale } = useI18n();
  const { run, storageError, resetStorage } = useApp();
  const { space, conflicts, groups, events, templates } = useSpaceData(spaceId);
  const [mac, setMac] = useState<boolean | null>(null);
  useEffect(() => {
    setMac(isMacDesktop());
  }, []);
  const pending = conflicts.filter((conflict) => conflict.resolution === "pending").length;

  if (!space) {
    return (
      <main className="ade-field min-h-screen p-8">
        <p className="text-sm">{t("error.NOT_FOUND")}</p>
        <Link href="/" className="ade-verb mt-4 inline-block">
          {t("nav.spaces")}
        </Link>
      </main>
    );
  }

  const base = `/space/${spaceId}`;
  const crumbs: Array<{ label: string; href?: string }> = [
    { label: t("nav.spaces"), href: "/" },
    { label: space.name, href: pathname === base ? undefined : base },
  ];
  const parts = pathname.startsWith(`${base}/`) ? pathname.slice(base.length + 1).split("/").filter(Boolean) : [];
  const section = parts[0];
  if (section && sectionKey[section]) {
    const sectionHref = `${base}/${section}`;
    crumbs.push({
      label: t(sectionKey[section]),
      href: parts.length > 1 ? sectionHref : undefined,
    });
    if (section === "groups" && parts[1]) {
      crumbs.push({ label: groups.find((item) => item.id === parts[1])?.name ?? t("error.NOT_FOUND") });
    } else if (section === "documents" && parts[1]) {
      crumbs.push({ label: templates.find((item) => item.id === parts[1])?.name ?? t("error.NOT_FOUND") });
    } else if (section === "events" && parts[1]) {
      const event = events.find((item) => item.id === parts[1]);
      const child = parts[2];
      if (child === "attendance" || child === "volunteers") {
        crumbs.push({
          label: event?.title ?? t("error.NOT_FOUND"),
          href: `${sectionHref}/${parts[1]}`,
        });
        crumbs.push({ label: t(child === "attendance" ? "attendance.title" : "volunteers.title") });
      } else {
        crumbs.push({ label: event?.title ?? t("error.NOT_FOUND") });
      }
    }
  }

  return (
    <div className="ade-field min-h-screen p-3 md:p-4">
      <div className="ade-sheet flex min-h-[calc(100vh-1.5rem)] md:min-h-[calc(100vh-2rem)]">
        <aside className="flex w-56 shrink-0 flex-col border-r border-[#e5c9b0]">
          <div className="flex flex-col gap-1 px-4 py-5">
            <Link href="/" className="ade-display text-4xl">
              {t("app.name")}
            </Link>
            <p className="truncate text-sm">{space.name}</p>
          </div>
          <nav className="flex flex-1 flex-col overflow-y-auto px-2 pb-4">
            {links.map((link, index) => {
              const href = `${base}${link.href}`;
              const active = link.href === "" ? pathname === href : pathname.startsWith(href);
              return (
                <Link
                  key={link.href}
                  href={href}
                  aria-current={active ? "page" : undefined}
                  data-active={active ? "true" : undefined}
                  className="ade-nav-link"
                >
                  <span className="ade-kicker w-7 shrink-0">{String(index + 1).padStart(2, "0")}</span>
                  <span>
                    {t(link.key)}
                    {link.key === "nav.conflicts" && pending > 0 ? ` (${pending})` : ""}
                  </span>
                </Link>
              );
            })}
          </nav>
        </aside>
        <div className="flex min-w-0 flex-1 flex-col">
          <header className="flex flex-wrap items-baseline gap-x-6 gap-y-2 border-b border-[#e5c9b0] px-6 py-3">
            <ol className="flex min-w-0 flex-1 flex-wrap items-baseline gap-x-2 gap-y-1">
              {crumbs.map((crumb, index) => (
                <li key={`${crumb.label}-${index}`} className="flex min-w-0 items-baseline gap-2">
                  {index > 0 ? (
                    <span aria-hidden="true" className="text-[#4a2a18]/40">
                      /
                    </span>
                  ) : null}
                  {crumb.href ? (
                    <Link href={crumb.href} className="ade-verb max-w-64 truncate">
                      {crumb.label}
                    </Link>
                  ) : (
                    <span className="max-w-64 truncate text-sm" aria-current="page">
                      {crumb.label}
                    </span>
                  )}
                </li>
              ))}
            </ol>
            <div className="ml-auto flex items-center gap-4">
              <button type="button" className="ade-verb" onClick={() => run({ type: "undo", spaceId })}>
                {t("action.undo")}
              </button>
              <button type="button" className="ade-verb" onClick={() => run({ type: "redo", spaceId })}>
                {t("action.redo")}
              </button>
              <div className="flex gap-1">
                <button
                  type="button"
                  className="ade-stamp"
                  aria-pressed={locale === "en"}
                  onClick={() => run({ type: "setLocale", locale: "en" })}
                >
                  EN
                </button>
                <button
                  type="button"
                  className="ade-stamp"
                  aria-pressed={locale === "es"}
                  onClick={() => run({ type: "setLocale", locale: "es" })}
                >
                  ES
                </button>
              </div>
            </div>
          </header>
          <main className="flex flex-col gap-6 p-6">
            {mac === false ? (
              <p role="alert" className="max-w-3xl border-b border-[#e5c9b0] pb-3 text-sm">
                <span className="ade-kicker mr-3">{t("app.name")}</span>
                {t("app.macNotice")}
              </p>
            ) : null}
            {storageError ? (
              <p role="alert" className="flex flex-wrap items-baseline gap-4 text-sm">
                <span>{t("app.storageError")}</span>
                <button type="button" className="ade-verb" onClick={resetStorage}>
                  {t("app.reset")}
                </button>
              </p>
            ) : null}
            {children}
          </main>
        </div>
      </div>
    </div>
  );
}

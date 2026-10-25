"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState, type ReactNode } from "react";
import { buttonVariants } from "@/components/ui/button";
import { Button } from "@/components/ui/button";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Separator } from "@/components/ui/separator";
import { useI18n } from "@/i18n";
import type { MessageKey } from "@/i18n/en";
import { isMacDesktop } from "@/lib/platform";
import { cn } from "@/lib/utils";
import { useApp } from "@/state/store";
import { useSpaceData } from "@/components/ade/space";

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

export function Shell({ spaceId, children }: { spaceId: string; children: ReactNode }) {
  const pathname = usePathname();
  const { t, locale } = useI18n();
  const { run, storageError, resetStorage } = useApp();
  const { space, conflicts } = useSpaceData(spaceId);
  const [mac, setMac] = useState<boolean | null>(null);
  useEffect(() => {
    setMac(isMacDesktop());
  }, []);
  const pending = conflicts.filter((conflict) => conflict.resolution === "pending").length;

  if (!space) {
    return (
      <main className="mx-auto flex max-w-xl flex-col gap-4 p-6">
        <p className="text-sm">{t("error.NOT_FOUND")}</p>
        <Link href="/" className={buttonVariants({ variant: "outline" })}>
          {t("nav.spaces")}
        </Link>
      </main>
    );
  }

  return (
    <div className="flex min-h-screen">
      <aside className="flex w-56 shrink-0 flex-col gap-3 border-r p-3">
        <div className="flex flex-col gap-1 px-2">
          <Link href="/" className="text-sm font-semibold">
            {t("app.name")}
          </Link>
          <p className="truncate text-sm text-muted-foreground">{space.name}</p>
        </div>
        <Separator />
        <ScrollArea className="h-[calc(100vh-8rem)]">
          <nav className="flex flex-col gap-1 pr-3">
            {links.map((link) => {
              const href = `/space/${spaceId}${link.href}`;
              const active = link.href === "" ? pathname === href : pathname.startsWith(href);
              return (
                <Link
                  key={link.href}
                  href={href}
                  className={cn(buttonVariants({ variant: active ? "secondary" : "ghost" }), "justify-start")}
                >
                  {t(link.key)}
                  {link.key === "nav.conflicts" && pending > 0 ? ` (${pending})` : ""}
                </Link>
              );
            })}
          </nav>
        </ScrollArea>
      </aside>
      <div className="flex min-w-0 flex-1 flex-col">
        <header className="flex flex-wrap items-center gap-2 border-b px-4 py-2">
          <Button type="button" variant="outline" onClick={() => run({ type: "undo", spaceId })}>
            {t("action.undo")}
          </Button>
          <Button type="button" variant="outline" onClick={() => run({ type: "redo", spaceId })}>
            {t("action.redo")}
          </Button>
          <div className="ml-auto flex gap-2">
            <Button
              type="button"
              variant={locale === "en" ? "secondary" : "ghost"}
              onClick={() => run({ type: "setLocale", locale: "en" })}
            >
              EN
            </Button>
            <Button
              type="button"
              variant={locale === "es" ? "secondary" : "ghost"}
              onClick={() => run({ type: "setLocale", locale: "es" })}
            >
              ES
            </Button>
          </div>
        </header>
        <main className="flex flex-col gap-6 p-6">
          {mac === false ? (
            <Alert>
              <AlertTitle>{t("app.name")}</AlertTitle>
              <AlertDescription>{t("app.macNotice")}</AlertDescription>
            </Alert>
          ) : null}
          {storageError ? (
            <Alert>
              <AlertTitle>{t("app.storageError")}</AlertTitle>
              <AlertDescription>
                <Button type="button" variant="outline" onClick={resetStorage}>
                  {t("app.reset")}
                </Button>
              </AlertDescription>
            </Alert>
          ) : null}
          {children}
        </main>
      </div>
    </div>
  );
}

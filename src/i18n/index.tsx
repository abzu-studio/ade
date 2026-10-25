"use client";

import { createContext, useContext, useMemo, type ReactNode } from "react";
import { en, type MessageKey } from "@/i18n/en";
import { es } from "@/i18n/es";
import type { Locale } from "@/core/types";

const dictionaries = { en, es };

function format(template: string, params?: Record<string, string>): string {
  if (!params) return template;
  return template.replace(/\{(\w+)\}/g, (match, key: string) => params[key] ?? match);
}

const I18nContext = createContext<{
  locale: Locale;
  t: (key: MessageKey, params?: Record<string, string>) => string;
} | null>(null);

export function I18nProvider({
  locale,
  children,
}: {
  locale: Locale;
  children: ReactNode;
}) {
  const value = useMemo(
    () => ({
      locale,
      t: (key: MessageKey, params?: Record<string, string>) =>
        format(dictionaries[locale][key], params),
    }),
    [locale],
  );
  return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>;
}

export function useI18n() {
  const value = useContext(I18nContext);
  if (!value) throw new Error("i18n missing");
  return value;
}

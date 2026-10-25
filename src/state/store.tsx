"use client";

import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { toast } from "sonner";
import { createEmptyDatabase, dispatch as reduce, type Action } from "@/core/reduce";
import type { CoreError, Result } from "@/core/result";
import type { Database } from "@/core/types";
import { sanitizeDatabase } from "@/core/validate";
import { I18nProvider, useI18n } from "@/i18n";
import type { MessageKey } from "@/i18n/en";
import { openRepository, type Repository } from "@/persistence/repository";

interface StoreValue {
  db: Database;
  dispatch: (action: Action) => Result<Database>;
  run: (action: Action, success?: string) => Result<Database>;
  storageError: boolean;
  resetStorage: () => void;
}

const StoreContext = createContext<StoreValue | null>(null);

function errorKey(error: CoreError): MessageKey {
  return `error.${error.code}` as MessageKey;
}

export function AppStore({ children }: { children: ReactNode }) {
  const [db, setDb] = useState<Database | null>(null);
  const [storageError, setStorageError] = useState(false);
  const dbRef = useRef<Database | null>(null);
  const repoRef = useRef<Repository | null>(null);
  const chain = useRef(Promise.resolve());

  const persist = useCallback((next: Database) => {
    const repo = repoRef.current;
    if (!repo) return;
    chain.current = chain.current
      .then(() => repo.save(next))
      .catch(() => undefined);
  }, []);

  const adopt = useCallback(
    (next: Database) => {
      dbRef.current = next;
      setDb(next);
      persist(next);
    },
    [persist],
  );

  useEffect(() => {
    let cancelled = false;
    openRepository()
      .then(async (repo) => {
        if (cancelled) return;
        repoRef.current = repo;
        const stored = await repo.load();
        if (cancelled) return;
        if (stored) {
          const parsed = sanitizeDatabase(stored);
          if (parsed.ok) {
            dbRef.current = parsed.value;
            setDb(parsed.value);
            return;
          }
          setStorageError(true);
        }
        const empty = createEmptyDatabase(crypto.randomUUID(), new Date().toISOString());
        dbRef.current = empty;
        setDb(empty);
        if (!stored) await repo.save(empty);
      })
      .catch(() => {
        const empty = createEmptyDatabase(crypto.randomUUID(), new Date().toISOString());
        dbRef.current = empty;
        setDb(empty);
        setStorageError(true);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const dispatch = useCallback((action: Action): Result<Database> => {
    const current = dbRef.current;
    if (!current) return { ok: false, error: { code: "NOT_FOUND" } };
    const result = reduce(current, action, {
      now: new Date().toISOString(),
      actorId: current.actor.id,
      newId: () => crypto.randomUUID(),
    });
    if (!result.ok) return result;
    dbRef.current = result.value;
    setDb(result.value);
    persist(result.value);
    return result;
  }, [persist]);

  const resetStorage = useCallback(() => {
    const empty = createEmptyDatabase(
      dbRef.current?.actor.id ?? crypto.randomUUID(),
      new Date().toISOString(),
      dbRef.current?.actor.name,
    );
    setStorageError(false);
    adopt(empty);
  }, [adopt]);

  if (!db) {
    return <p className="p-6 text-sm">Loading…</p>;
  }

  return (
    <I18nProvider locale={db.locale}>
      <StoreBridge
        db={db}
        dispatch={dispatch}
        storageError={storageError}
        resetStorage={resetStorage}
      >
        {children}
      </StoreBridge>
    </I18nProvider>
  );
}

function StoreBridge({
  db,
  dispatch,
  storageError,
  resetStorage,
  children,
}: Omit<StoreValue, "run"> & { children: ReactNode }) {
  const { t } = useI18n();
  useEffect(() => {
    document.documentElement.lang = db.locale;
  }, [db.locale]);
  const run = useCallback(
    (action: Action, success?: string) => {
      const result = dispatch(action);
      if (!result.ok) toast.error(t(errorKey(result.error), result.error.params));
      else if (success) toast.success(success);
      return result;
    },
    [dispatch, t],
  );
  const value = useMemo(
    () => ({ db, dispatch, run, storageError, resetStorage }),
    [db, dispatch, resetStorage, run, storageError],
  );
  return <StoreContext.Provider value={value}>{children}</StoreContext.Provider>;
}

export function useApp() {
  const value = useContext(StoreContext);
  if (!value) throw new Error("store missing");
  return value;
}

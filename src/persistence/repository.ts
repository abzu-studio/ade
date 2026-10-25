export interface Repository {
  load(): Promise<unknown | null>;
  save(value: unknown): Promise<void>;
}

const DB_NAME = "ade";
const STORE = "kv";
const KEY = "database";

export function openRepository(): Promise<Repository> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, 1);
    request.onupgradeneeded = () => {
      const database = request.result;
      if (!database.objectStoreNames.contains(STORE)) {
        database.createObjectStore(STORE);
      }
    };
    request.onerror = () => reject(request.error);
    request.onsuccess = () => {
      const database = request.result;
      resolve({
        load() {
          return new Promise((resolveLoad, rejectLoad) => {
            const transaction = database.transaction(STORE, "readonly");
            const get = transaction.objectStore(STORE).get(KEY);
            get.onsuccess = () => resolveLoad(get.result ?? null);
            get.onerror = () => rejectLoad(get.error);
          });
        },
        save(value) {
          return new Promise((resolveSave, rejectSave) => {
            const transaction = database.transaction(STORE, "readwrite");
            transaction.objectStore(STORE).put(value, KEY);
            transaction.oncomplete = () => resolveSave();
            transaction.onerror = () => rejectSave(transaction.error);
          });
        },
      });
    };
  });
}

# Adê

Adê is a local-first desktop app for spaces, people, events, attendance, volunteering, and documents. It is built for Mac. On another system the app stays usable and shows a short notice.

Business rules live in `src/core` and do not depend on React or the browser. The screens call that core. They use the default shadcn/ui components only.

## Run

```bash
npm install
npm run dev
```

Open http://localhost:3000. `npm test` runs the rule and PDF tests. `npm run build` builds the Next.js app.

## Layout

- `src/core` — domain types, attendance, volunteering, documents, history, and sync
- `src/persistence` — IndexedDB and file import/export
- `src/lib/pdf` — PDF rendering for a planned document
- `src/app` — screens for the activity cycle
- `src/i18n` — English and Spanish
- `docs/RULES.md` — the calculation and state rules
- `docs/ARCHITECTURE.md` — how the pieces fit

## Activity cycle

Create a space, add people, a component, and a category, then create an event. Schedule it, put people on the participant list, review volunteer suggestions, select volunteers by hand, record attendance, read participation, and generate a PDF.

The home screen can load a demo space with that cycle already filled in.

## Language and storage

The language switch writes the locale on this Mac. Data is stored in IndexedDB under the database name `ade`. History can undo, redo, and show an older revision. Data can export a full backup or one space. Importing a space keeps both versions when the same record changed in two places.

## shadcn

`.cursor/mcp.json` starts the shadcn MCP server (`npx shadcn@latest mcp`). Components were added from the `@shadcn` registry with the default neutral theme. Do not restyle that theme here; brand identity is applied later.

Magic MCP can help with later interface work. It is not required for these screens and is not configured.

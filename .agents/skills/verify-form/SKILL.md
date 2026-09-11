---
name: verify-form
description: Launch and drive FORM, the private mobile-web PWA in apps/web (browse wardrobe, upload/save/edit items, wishlist, archive, catalog images, reset), against disposable Postgres+MinIO fixtures and capture screenshots + ARIA snapshots. Reach for this to prove a real user path works end to end in the browser, not just that unit tests pass.
---

# Verify FORM (mobile-web PWA)

FORM is a single-user German-language wardrobe PWA. The client is static HTML/CSS/JS
in `apps/web/public` (`app.js` is the whole app, hash-routed). It talks same-origin to
the Hono API in `apps/api`. In verification mode the API pins a fixed personal account,
so there is **no login** — writes need no auth token.

The surface is the browser UI. There is also a JSON API (`/v1/...`) you can curl for
setup or side-effect checks, and a background worker (`apps/worker`) for AI image jobs
that is **not** started here — detection and catalog generation call OpenAI and are out
of scope for automated verification (see Gotchas).

## Launch

Verification runs against **disposable** Postgres + MinIO, never the personal
deployment. All commands run from the repo root with Node 24+.

```sh
# 1. Disposable services (idempotent; skip if doctor already sees ports 55432 + 9100)
npm run services:up          # docker compose postgres + object-storage, --wait
npm run services:migrate     # schema; prints "Database is current." when done

# 2. Fixture web server on loopback :18444 (resets fixtures on every boot)
node --env-file=.env.services.local --import tsx apps/web/e2e/serve.mjs
```

`.env.services.local` carries the disposable DB/S3 URLs and `FIXTURE_RESET_ALLOWED=true`.
The server is **ready** when it prints `PWA test server ready` and `GET /health/ready`
returns `{"status":"ready",...}` (usually <2s). It serves the static shell at `/` and
the API under `/v1`. It re-seeds fixtures on each start, so a fresh launch is a clean slate.

Run it in the background and capture its log, e.g.:

```sh
node --env-file=.env.services.local --import tsx apps/web/e2e/serve.mjs \
  > /tmp/form-verify-serve.log 2>&1 &
```

`services:up` needs Docker access. If `docker` gives "permission denied", the services
may already be running (this box keeps them up) — run the doctor before assuming you
must start them.

**Teardown:** see Cleanup. Only kill the `serve.mjs` you started; leave shared
Postgres/MinIO alone unless you started those too.

## Doctor

One read-only check before driving anything:

```sh
bash .agents/skills/verify-form/helpers/doctor.sh
```

It verifies Postgres (:55432) and MinIO (:9100) answer, `GET :18444/health/ready`
is `ready`, and at least one wardrobe item is seeded. It prints `DOCTOR OK: ...` or
`DOCTOR FAIL: <first unmet precondition>` and exits non-zero on failure. Run it first
whenever anything looks off; a failing doctor means fix the launch, don't drive.

## Drive

Browser automation uses Playwright's Chromium bindings with an **iPhone 13** context
(this is a mobile-first PWA — always emulate mobile). The system browser is at
`/usr/bin/chromium`; pass it via `PLAYWRIGHT_CHROMIUM_EXECUTABLE`. **Run node from the
repo root** so `@playwright/test` resolves.

Read-only smoke of any nav route (`owning`, `wanting`, `add`, `settings`):

```sh
PLAYWRIGHT_CHROMIUM_EXECUTABLE=/usr/bin/chromium \
  node .agents/skills/verify-form/helpers/drive.mjs owning wardrobe
```

It navigates to the hash route, waits for images, checks for horizontal overflow and
page/HTTP errors, writes an ARIA snapshot + full-page screenshot to `FORM_VERIFY_OUT`
(default `/tmp/form-verify`), prints a JSON report, and exits non-zero on overflow or errors.

For **mutating** flows, the repo ships authoritative drivers — run them, don't reinvent them:

```sh
# automatic upload → detect → select → import (stubs only the paid detection result):
PLAYWRIGHT_CHROMIUM_EXECUTABLE=/usr/bin/chromium \
  node --env-file=.env.services.local --import tsx apps/web/e2e/add-auto.test.mjs
# item edit → search → archive → restore → delete:
PLAYWRIGHT_CHROMIUM_EXECUTABLE=/usr/bin/chromium node apps/web/e2e/mobile.test.mjs
# catalog-image review / version restore (keeps a stub image; makes no OpenAI call):
PLAYWRIGHT_CHROMIUM_EXECUTABLE=/usr/bin/chromium node apps/web/e2e/review.test.mjs
```

Prefer **stable handles** over coordinates. The UI is German. Real handles:

- Nav buttons: `getByRole('button', { name: 'Schrank' | 'Wunschliste' | 'Hinzufügen' | 'Einstellungen', exact: true })`, or hash routes `#owning`, `#wanting`, `#add`.
- Item cards: `.item` (grid), each is a `<button>` whose accessible name includes the item name (e.g. `getByRole('button', { name: /Navy overshirt/ })`).
- Search box: `getByRole('searchbox')` (aria-label `Kleiderschrank durchsuchen`).
- Category chips: `[data-cat="jacket"]` etc. (`top jacket pants skirt dress shoes bag hat scarf`).
- Add screen inputs: `#library-input` (multi photo), `#camera-input`. Detected pieces: `[data-toggle-piece]`; import: `[data-import-detected]`; fallback form: `[data-manual-save]`.
- Detail dialog: opens as `dialog`; primary action `Änderungen speichern`; `Ins Archiv legen` / `Zurück in den Schrank`; `Stück endgültig löschen …` then confirm `Stück endgültig löschen`.
- Reset: Settings → `Kleiderschrank leeren …` → type `ALLES LÖSCHEN` → `Alles endgültig löschen`.

## Evidence

Proof artifacts go to `FORM_VERIFY_OUT` (default `/tmp/form-verify`); `mobile.test.mjs`
writes to `/tmp/form-pwa-qa`. A proof captures the **user action and the resulting
state**, not just a final screen:

- The full-page screenshot(s) with the FORM masthead / `NUR FÜR DICH` badge visible, so the artifact is self-identifying.
- The ARIA snapshot, which records the accessible structure independent of pixels.
- For a mutation, verify the **side effect**, not only the DOM: re-read via the API,
  e.g. `curl -s "http://127.0.0.1:18444/v1/wardrobe-items?collection=owning"` and confirm
  the new/edited/deleted item, or that an uploaded original exists via its asset download route.

Drive the **real user path** (nav → card → dialog buttons), not internal setters. Do not
point a proof at a test-only endpoint. The honest mocks are deterministic detection
proposals in `add-auto.test.mjs` and seeded shelf-image versions in `review.test.mjs`.
Neither calls OpenAI. Upload, selection, persistence, generation enqueue, review, and
restore still use real local paths.

## Cleanup

Kill only what this run started, and keep the evidence:

```sh
pkill -f "apps/web/e2e/serve.mjs"      # only if THIS run launched it
```

Never kill Postgres/MinIO unless you ran `services:up` yourself; if you did and want them
gone, `npm run services:down`. Leave `FORM_VERIFY_OUT` / `/tmp/form-pwa-qa` in place —
cleanup removes instances and scratch, never the proof. Because `serve.mjs` re-seeds on
boot, you do **not** need to undo fixture mutations; the next launch is clean.

## Helpers

- `helpers/doctor.sh` — read-only readiness check (invocation under **Doctor**).
- `helpers/drive.mjs` — parameterized read-only browser smoke (invocation under **Drive**).

Both are executable and self-contained. The repo's own `apps/web/e2e/add-auto.test.mjs`,
`mobile.test.mjs`, and `review.test.mjs` are the maintained mutating drivers.

## Feature map

`features/README.md` indexes the user-facing features with per-feature drive recipes and
proof end-states. A proof that only drives one convenient entry point is incomplete when
the map lists others — consult it and cover the mapped path you are verifying.

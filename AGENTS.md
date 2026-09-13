# Working in this repo

FORM is a private single-user wardrobe PWA. Static HTML/CSS/JS in `apps/web/public`
(`app.js` is the whole client, hash-routed), a Hono API in `apps/api`, a background
worker in `apps/worker`, shared code in `packages/`.

## What "done" means

A change is done when the code is written and checked at the cheapest level that
actually covers it. Match the check to the change — do not escalate past it:

| Change | Check |
| --- | --- |
| Copy, styling, a small `app.js` branch | Read the diff. Reload the dev server if it is running. |
| API handler, service logic, contracts | `npm run verify --workspace=@form/<pkg>` |
| Schema, storage, cross-package behaviour | `npm run test:integration` |
| A user path you genuinely can't reason about | the `verify-form` skill (browser) |

Browser e2e is the most expensive check here: Docker services, a fixture server, a
real Chromium. It is for proving a multi-step user flow works, not for confirming a
label changed. Reach for it when the change spans upload → detect → save → review, or
when something is visibly broken and you cannot tell why. Not otherwise, and not
unprompted on a one-line edit.

Stopping after the matching check and saying what you checked is a complete answer.

## Deploying

The production host `stargate` is **not** part of finishing a change. Deploy only when
asked to deploy, ship, release, or roll back — then use the `deploy-stargate` skill,
which carries the full procedure. Never ship as a follow-on to an edit, and do not
offer to on every turn.

Migrating, resetting, or deleting data — local or production — is always its own
explicit request.

## Local data

Two separate databases on the same local Postgres (`:55432`):

- **`form`** — your dev wardrobe. `npm run dev:*` uses it via `apps/api/.env.local`.
  Real state you may care about. Nothing automated may truncate it.
- **`form_fixtures`** — disposable, with its own `form-fixture-media` bucket.
  Everything under `.env.services.local` uses it: integration tests, `fixtures:reset`,
  and the browser fixture server, which re-seeds it on every boot.

`resetFixtures` TRUNCATEs every table and refuses any database whose name does not end
in `_fixtures` (`assertFixtureTarget` in `packages/service/src/fixtures.ts`). Do not
route around that guard; if a fixture run wants the dev database, the env file is wrong.

## Serving the dev app to a phone

Only when asked to reach the app from a device. Resolve the machine's current Tailscale
IPv4 rather than assuming a fixed address, point the client's public API URL and the
API's `WEB_ORIGIN` at that same host, restart the affected dev processes, and check
sign-in/CORS through the Tailscale address. Tailscale-specific values belong in ignored
local env files, never in tracked ones.

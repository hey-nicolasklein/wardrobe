# Working in this repo

FORM is a wardrobe app. The Flutter client lives in `apps/mobile`, a Hono API in
`apps/api`, a background worker in `apps/worker`, shared code in `packages/`. The
old PWA is retired. nginx still serves the privacy policy from `deploy/public`.

## What "done" means

A change is done when the code is written and checked at the cheapest level that
actually covers it. Match the check to the change — do not escalate past it:

| Change | Check |
| --- | --- |
| Copy, styling, a small widget branch | Read the diff. Hot reload if the app is running. |
| Mobile logic, blocs, repositories | `npm run verify:mobile` |
| API handler, service logic, contracts | `npm run verify --workspace=@form/<pkg>` |
| Schema, storage, cross-package behaviour | `npm run test:integration` |
| A user path you genuinely can't reason about | Run the app in a simulator against local services |

Stopping after the matching check and saying what you checked is a complete answer.

## Deploying

The production host `stargate` is **not** part of finishing a change. Deploy only when
asked to deploy, ship, release, or roll back — then use the `deploy-stargate` skill,
which carries the full procedure. Never ship as a follow-on to an edit, and do not
offer to on every turn.

Migrating, resetting, or deleting data — local or production — is always its own
explicit request.

For an explicitly requested iOS TestFlight release, use the `release-testflight`
skill in `.agents/skills/release-testflight/SKILL.md`. The local pipeline is
`npm run release:testflight -- --build-number N`. Choose N from App Store Connect,
then confirm processing and availability in FORM Internal. Mobile release and
backend deployment are separate requests.

## Local data

Two separate databases on the same local Postgres (`:55432`):

- **`form`** — your dev wardrobe. `npm run dev:*` uses it via `apps/api/.env.local`.
  Real state you may care about. Nothing automated may truncate it.
- **`form_fixtures`** — disposable, with its own `form-fixture-media` bucket.
  Everything under `.env.services.local` uses it: integration tests and `fixtures:reset`.

`resetFixtures` TRUNCATEs every table and refuses any database whose name does not end
in `_fixtures` (`assertFixtureTarget` in `packages/service/src/fixtures.ts`). Do not
route around that guard; if a fixture run wants the dev database, the env file is wrong.

## Serving the dev app to a phone

Only when asked to reach the local API from a physical phone. Resolve the machine's
current Tailscale IPv4 rather than assuming a fixed address, point the app's
`FORM_API_BASE_URL` in `apps/mobile/.env.tailscale.json` at it, restart the API, and
check sign-in through the Tailscale address. Tailscale-specific values belong in ignored
local env files, never in tracked ones.

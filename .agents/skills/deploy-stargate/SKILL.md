---
name: deploy-stargate
description: Ship FORM to the private stargate production host (https://stargate.stork-platy.ts.net:8443) and confirm the release went live. Use ONLY when explicitly asked to deploy, ship, release, or roll back — deploying is never part of finishing a code change.
---

# Deploy to stargate

The production instance runs on the `stargate` host at `https://stargate.stork-platy.ts.net:8443`,
reachable on the tailnet only. There are no users besides Nico.

**Deploying is an explicit request, never a follow-on.** Finishing a change means the code is
written and checked locally. Do not ship because a change "looks done", and do not offer to ship
on every turn. Migrating, resetting, or deleting production data is a separate request again —
it is never covered by "deploy".

## Ship it

```sh
deploy/ship.sh              # web api worker (default)
deploy/ship.sh api worker   # those, plus web — it always carries the version stamp
```

Always use `ship.sh` rather than calling Compose by hand. It stamps a fresh `FORM_VERSION`,
rebuilds, and blocks until `/version.json` reports that stamp. A bare
`docker compose --env-file .env.production -f compose.production.yaml up -d --build` leaves
`FORM_VERSION` unset, which bakes the literal `dev` into `version.json`; open clients then never
see the version change, never reload, and keep running the old `app.js`.

Rebuild only what carries the change:

| Changed path | Service |
| --- | --- |
| `apps/web/public` | `web` |
| `apps/api`, `packages/contracts` | `api` |
| `apps/worker`, `packages/service` (prompts, image processing) | `worker` |

Contracts changes touch `api` and `worker` both. Compose recreates `api` alongside `web` on its
own — that is expected, not a mistake. `web` is always rebuilt because it carries the stamp.

## Confirm

`ship.sh` exits non-zero if the new stamp never appears, so a zero exit is already the main proof.
Then:

```sh
docker compose -f compose.production.yaml ps          # read-only; services healthy
curl -s http://127.0.0.1:18081/<asset>                # serves the new bytes
```

Report the deployed state: the stamp that went live and which services were rebuilt.

## How the stack is wired

- A long-lived `form-production` Compose project from `compose.production.yaml`
  (`web`, `api`, `worker`, `postgres`, `object-storage`), all `restart: unless-stopped`.
- Tailscale Serve terminates HTTPS on `:8443` and proxies to `127.0.0.1:${FORM_WEB_PORT}`
  (default `18081`) — the `web` container, which proxies `/v1/` to the API.
  `tailscale serve status` shows the mapping.
- Runtime config lives in the git-ignored `.env.production` (`PUBLIC_WEB_ORIGIN`, `WEB_ORIGIN`,
  `S3_PUBLIC_ENDPOINT`, `PERSONAL_ACCOUNT_ID`). There is no login screen: `PERSONAL_ACCOUNT_ID`
  opens that account automatically.
- Web and API assets are baked into their images (`build.target`), so shipping needs a rebuild
  and recreate, not just a restart.
- `npm run services:migrate` runs only when the schema actually changed.
- `deploy/verify.sh` is a fuller post-deploy check (health, CORS, sign-in) for when a deploy
  looks wrong.

## Never without an explicit request

Fixture reset, `deploy/restore.sh`, or anything that drops production data. `deploy/backup.sh`
first if data is in play at all.

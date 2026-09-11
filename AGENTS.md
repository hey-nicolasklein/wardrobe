# Local development access

When starting the application locally, make it reachable through Tailscale as well as localhost.

- Resolve the machine's current Tailscale IPv4 address instead of assuming a fixed address.
- Configure the mobile client's public API URL and the API's allowed web origin to use the same Tailscale host or IP.
- Restart affected development processes after changing environment configuration.
- Verify the web app, API readiness, and browser sign-in/CORS through the Tailscale address.
- Always include the working Tailscale URL and local fixture credentials in the final response.
- Keep secrets out of tracked files; Tailscale-specific runtime values belong in ignored local environment files.

# Live deployment (stargate)

The production instance runs on the `stargate` host at `https://stargate.stork-platy.ts.net:8443` (tailnet only).

**Ship every finished change here without asking.** There are no users besides Nico, and the tailnet instance is expected to run the current version at all times. Once a change is implemented and verified, rebuild and recreate the affected services in the same turn, then report the deployed state. Migrating, resetting, or deleting data is *not* covered by this — those still need an explicit request.

- Rebuild only what carries the change: `web` for anything in `apps/web/public`, `api` for `apps/api` or `packages/contracts`, `worker` for `apps/worker` or `packages/service` (prompts and image processing live there). Contracts changes touch `api` and `worker` both. Compose recreates `api` alongside `web` on its own — that is expected, not a mistake.
- Deploy command: `deploy/ship.sh [services]` (default `web api worker`). Always use it
  instead of calling compose by hand. It stamps a fresh `FORM_VERSION`, rebuilds, and
  blocks until `/version.json` reports that stamp. A bare
  `docker compose --env-file .env.production -f compose.production.yaml up -d --build`
  leaves `FORM_VERSION` unset, which bakes the literal `dev` into `version.json`; open
  clients then never see the version change, never reload, and keep running the old
  `app.js`. `web` is always rebuilt because it carries the stamp.
- Confirm afterwards: `ps` shows the rebuilt services healthy, and `curl -s http://127.0.0.1:18081/<asset>` serves the new bytes.
- It runs as the long-lived `form-production` Docker Compose project from `compose.production.yaml` (`web`, `api`, `worker`, `postgres`, `object-storage`), all `restart: unless-stopped`.
- Tailscale Serve terminates HTTPS on `:8443` and proxies to `127.0.0.1:${FORM_WEB_PORT}` (default `18081`), the `web` container, which proxies `/v1/` to the API. `tailscale serve status` shows the mapping.
- Runtime config lives in the git-ignored `.env.production` (`PUBLIC_WEB_ORIGIN`, `WEB_ORIGIN`, `S3_PUBLIC_ENDPOINT`, `PERSONAL_ACCOUNT_ID`). No login screen: `PERSONAL_ACCOUNT_ID` opens that account automatically.
- Web and API assets are baked into their images (`build.target`), so shipping changes needs a rebuild and recreate, not just a restart. Run `npm run services:migrate` only when the schema changes.
- Status check (read-only): `docker compose -f compose.production.yaml ps`.

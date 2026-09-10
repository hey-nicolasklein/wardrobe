# Local development access

When starting the application locally, make it reachable through Tailscale as well as localhost.

- Resolve the machine's current Tailscale IPv4 address instead of assuming a fixed address.
- Configure the mobile client's public API URL and the API's allowed web origin to use the same Tailscale host or IP.
- Restart affected development processes after changing environment configuration.
- Verify the web app, API readiness, and browser sign-in/CORS through the Tailscale address.
- Always include the working Tailscale URL and local fixture credentials in the final response.
- Keep secrets out of tracked files; Tailscale-specific runtime values belong in ignored local environment files.

# Live deployment (stargate)

The production instance runs on the `stargate` host at `https://stargate.stork-platy.ts.net:8443` (tailnet only). This is the daily driver — do not rebuild, restart, migrate, or reset it unless explicitly asked.

- It runs as the long-lived `form-production` Docker Compose project from `compose.production.yaml` (`web`, `api`, `worker`, `postgres`, `object-storage`), all `restart: unless-stopped`.
- Tailscale Serve terminates HTTPS on `:8443` and proxies to `127.0.0.1:${FORM_WEB_PORT}` (default `18081`), the `web` container, which proxies `/v1/` to the API. `tailscale serve status` shows the mapping.
- Runtime config lives in the git-ignored `.env.production` (`PUBLIC_WEB_ORIGIN`, `WEB_ORIGIN`, `S3_PUBLIC_ENDPOINT`, `PERSONAL_ACCOUNT_ID`). No login screen: `PERSONAL_ACCOUNT_ID` opens that account automatically.
- Web and API assets are baked into their images (`build.target`), so shipping changes needs a rebuild and recreate, not just a restart: `docker compose -f compose.production.yaml up -d --build web api`. Run `npm run services:migrate` only when the schema changes.
- Status check (read-only): `docker compose -f compose.production.yaml ps`.

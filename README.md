# FORM wardrobe studio

FORM is becoming a private, persistent personal wardrobe for iPhone and web. The production code is an npm monorepo built around an Expo client and separate service boundaries.

## Production workspaces

| Workspace | Responsibility |
| --- | --- |
| `apps/mobile` | Expo SDK 57 universal client |
| `apps/api` | Standalone Hono HTTP boundary |
| `apps/worker` | Durable remote-image worker boundary |
| `packages/contracts` | Runtime-validated domain, request, response, event, and error contracts |
| `packages/service` | PostgreSQL migrations, private object storage, durable jobs, health, and fixtures |

The production destination and execution order live in [`docs/wayfinder/persistent-wardrobe/map.md`](docs/wayfinder/persistent-wardrobe/map.md). PostgreSQL, private object storage, durable jobs, authentication, and the product UI are owned by subsequent Wayfinder tickets.

## Set up

Use Node.js 24 and install once from the repository root:

```sh
npm install
```

Copy the relevant `.env.example` in each app to `.env.local`. Only `EXPO_PUBLIC_API_URL` enters the mobile bundle; never put credentials in an `EXPO_PUBLIC_*` variable.

For the disposable local PostgreSQL and S3-compatible services:

```sh
cp .env.services.example .env.services.local
npm run services:up
npm run services:migrate
npm run fixtures:reset
```

PostgreSQL binds only to `127.0.0.1:55432`; the private MinIO API and console bind only to `127.0.0.1:9100` and `127.0.0.1:9101`. The non-production credentials in `compose.yaml` match `.env.services.example`. The fixture reset is destructive to application rows and is hard-limited to local hosts.

## Development

```sh
npm run dev:api
npm run dev:worker
npm run dev:mobile
```

Or start all three production boundaries together:

```sh
npm run dev:production
```

The mobile app should be exercised in Expo Go first. The API exposes liveness at `/health/live` and dependency readiness at `/health/ready`. API and worker startup apply pending migrations, ensure the private versioned bucket exists, and fail startup when their required service configuration is invalid. The worker recovers expired leases; provider-specific handlers arrive with the catalog-worker ticket.

## Verification

```sh
npm run verify
npm exec --workspace=@form/mobile -- expo install --check
npm run test:integration
```

The first command typechecks every production workspace and runs unit/contract tests. The integration command requires the local services and validates migrations, repeatable fixture reset, database-enforced account ownership, idempotent enqueuing, concurrency limits, and abandoned-lease recovery against real PostgreSQL and MinIO.

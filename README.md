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

The production destination and execution order live in [`docs/wayfinder/persistent-wardrobe/map.md`](docs/wayfinder/persistent-wardrobe/map.md). The service foundation, authenticated app shell, persistent wardrobe model, catalog pipeline, offline-capable browsing, guided multi-item intake, and generation review/version workflows are implemented; deployment and release proof remain in subsequent Wayfinder tickets.

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

Administrators create accounts directly. Set `ADMIN_ACCOUNT_EMAIL` and
`ADMIN_ACCOUNT_PASSWORD` in the ignored `.env.services.local`, then run:

```sh
npm run accounts:create
```

Passwords must contain at least 12 characters. The API stores only salted scrypt
hashes and one-way hashes of opaque session tokens. Browser sessions use secure,
HTTP-only cookies; native session tokens are stored by the app in Expo SecureStore.
All private-media uploads and reads use short-lived signed URLs issued only after
an account ownership check.

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

The mobile app should be exercised in Expo Go first. The API exposes liveness at `/health/live` and dependency readiness at `/health/ready`. API and worker startup apply pending migrations, ensure the private versioned bucket exists, and fail startup when their required service configuration is invalid. For local cookie sessions, keep `SESSION_COOKIE_SECURE=false`; deployed HTTPS environments must use the default `true`. The worker recovers expired leases, renews active leases, and runs detection and Shelf Image jobs. Configure an OpenAI key plus an explicit dated standard-rate snapshot before worker startup; routine verification uses replay providers and never makes paid calls.

## Verification

```sh
npm run verify
npm exec --workspace=@form/mobile -- expo install --check
npm run test:integration
```

The first command typechecks every production workspace and runs unit/contract tests. The integration command requires the local services and validates migrations, repeatable fixture reset, database-enforced account ownership, idempotent enqueuing, concurrency limits, abandoned-lease recovery, and the replay catalog pipeline against real PostgreSQL and MinIO.

A deliberate paid smoke test is available separately and is never part of routine verification:

```sh
OPENAI_API_KEY=... npm run test:openai-smoke
```

It calls both the live strict vision and `gpt-image-2` edit endpoints, checks returned usage, and validates the generated chroma output.

# FORM wardrobe studio

FORM is becoming a private, persistent personal wardrobe for iPhone and web. The production code is an npm monorepo built around an Expo client and separate service boundaries.

## Production workspaces

| Workspace | Responsibility |
| --- | --- |
| `apps/mobile` | Expo SDK 57 universal client |
| `apps/api` | Standalone Hono HTTP boundary |
| `apps/worker` | Durable remote-image worker boundary |
| `packages/contracts` | Runtime-validated domain, request, response, event, and error contracts |

The production destination and execution order live in [`docs/wayfinder/persistent-wardrobe/map.md`](docs/wayfinder/persistent-wardrobe/map.md). PostgreSQL, private object storage, durable jobs, authentication, and the product UI are owned by subsequent Wayfinder tickets.

## Set up

Use Node.js 24 and install once from the repository root:

```sh
npm install
```

Copy the relevant `.env.example` in each app and `packages/service` to `.env.local`. Only `EXPO_PUBLIC_API_URL` enters the mobile bundle; never put credentials in an `EXPO_PUBLIC_*` variable.

Start disposable PostgreSQL and private S3-compatible storage, apply migrations, and load the two deterministic fixture accounts:

```sh
npm run services:up
npm run db:migrate
npm run fixtures:reset
```

The development containers keep data in named volumes. `npm run services:down` stops them without deleting data.

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

The mobile app should be exercised in Expo Go first. The API exposes liveness at `/health/live` and checks PostgreSQL plus object storage at `/health/ready`. The worker owns database-safe job claiming and abandoned-lease recovery; provider handlers arrive with the GPT catalog ticket.

The normal verification suite is infrastructure-free. To also prove the real PostgreSQL and S3-compatible boundary:

```sh
npm run services:up
npm run test:service-integration
```

## Verification

```sh
npm run verify
npm exec --workspace=@form/mobile -- expo install --check
```

The first command typechecks every production workspace and runs the shared contract tests.

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

Copy the relevant `.env.example` in each app to `.env.local`. Only `EXPO_PUBLIC_API_URL` enters the mobile bundle; never put credentials in an `EXPO_PUBLIC_*` variable.

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

The mobile app should be exercised in Expo Go first. The API currently exposes only a workspace marker at `http://localhost:4143/`, and the worker intentionally has no queue consumer until the durable service-foundation ticket.

## Verification

```sh
npm run verify
npm exec --workspace=@form/mobile -- expo install --check
```

The first command typechecks every production workspace and runs the shared contract tests.

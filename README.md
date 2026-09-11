# FORM wardrobe studio

FORM is a private mobile website for using your own wardrobe. Open it in Safari or Chrome and add it to the iPhone Home Screen. The PWA client lives in `apps/web`.

The private deployment opens a configured existing account automatically. It must stay behind Tailscale Serve or an equivalent private network boundary. `PERSONAL_ACCOUNT_ID` is a server-only setting in the ignored `.env.production`. Do not expose this mode to the public internet.

## Everyday workflow

Upload one or several photos, name each piece, and save it directly. Photo-only intake, browsing, search, editing, wishlist, and archive make no AI requests. Optional detection proposes metadata and can split a photo into multiple pieces. Optional low-quality catalog generation remains available with keep, reject, and restore history. Settings can clear the shared private wardrobe after a typed confirmation. Active uploads and image jobs block that reset.

The PWA caches only its static shell. Wardrobe browsing and changes require a connection to the server. Photos and personal records are not stored in the service worker cache. Unfinished photo draft metadata is saved in the browser; uploaded originals stay on the server.

## Deployment

Use Node.js 24 and `npm ci` for development. Persistent PostgreSQL and MinIO data remain outside the repository. To rebuild the dedicated application services:

```sh
deploy/ship.sh              # web, api and worker
deploy/ship.sh api worker   # those plus web, which carries the version stamp
```

The script stamps `FORM_VERSION` and waits until `/version.json` reports it.
Calling Compose directly leaves that variable unset, bakes the literal `dev`
into the web image, and open clients then never notice the release.

The web image contains static HTML, CSS and JavaScript served by nginx. It proxies the existing Hono API and uses same-origin requests. No Expo export or app-store build is involved. Keep the loopback web port behind the existing private HTTPS proxy. Read `docs/mobile-web.md` for the pivot, cost findings and verification.

## Verification

```sh
npm run verify --workspace=@form/api
npm run verify --workspace=@form/service
npm run verify --workspace=@form/contracts
npm run verify --workspace=@form/web
```

Database integration and browser tests require disposable services. Never run fixture reset against the personal deployment.

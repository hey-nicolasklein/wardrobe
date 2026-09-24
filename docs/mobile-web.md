# Personal mobile web pivot

## Scope

Use the existing wardrobe service through the mobile-first PWA. The legacy Expo and app-store client has been removed. Keep the existing account and all wardrobe records. `PERSONAL_ACCOUNT_ID` chooses that account on the server, and Tailscale provides the private access boundary. No login or password screen appears in the web client. The old authenticated API mode remains available when that setting is absent.

The website provides batch photo intake, editable saved drafts, optional multi-item detection, a searchable category-filtered wardrobe, wishlist and archive, item editing, original photos, optional catalog images, review and version restoration, permanent item deletion and a confirmed wardrobe reset. It uses native document scrolling, safe-area padding, 16px form inputs, accessible dialogs and reduced-motion support. Offline mode can open the shell and explains that the server connection is required. Saved outfit generation is outside this pivot because it was not implemented in the existing service.

## Cost findings

The deployed image pricing configuration used `1` for every microdollar-per-million rate. Existing generation costs therefore are not trustworthy. Historical ledgers are left intact and the UI labels the old tiny totals as invalid.

The official pricing page, checked on 2026-09-23, lists GPT Image 2.5 at $5 per million text input tokens, $8 per million image input tokens and $30 per million image output tokens. GPT-5.6 Luna costs $0.20 per million uncached input tokens, $0.02 per million cached input tokens and $1.20 per million output tokens; cache writes cost 1.25 times the uncached input rate. Runtime configuration captures these rates with every paid request. Sources: https://developers.openai.com/api/docs/pricing and https://developers.openai.com/api/docs/models/gpt-5.6-luna

Applying the image rates to older saved usage yielded $0.011413 to $0.018946 per low-quality image. This is a retrospective estimate, not an invoice reconciliation or a guaranteed future price. New garment detections store their complete Responses usage, captured rate card and component costs. The weekly cost view includes feed images, catalog images and garment detection. Photo-only intake has no provider cost; detection and generation each require an explicit user action.

## Verification

Unit and contract suites cover the existing service. `apps/api/src/personal.test.ts` exercises personal access, idempotent photo intake, real thumbnail creation, cross-origin write rejection, quality restriction, reset confirmation, active-job protection and account isolation against disposable PostgreSQL and MinIO. Run together with the existing integration tests, sequentially, using `FORM_RUN_SERVICE_INTEGRATION=true` and a test-only environment file.

`apps/web/e2e/serve.mjs` starts the fixture API and static website on loopback port 18444. It requires `FIXTURE_RESET_ALLOWED=true` and resets the disposable fixture data. Start with Node 24, `--env-file` pointing at the disposable services and `--import tsx`. `apps/web/e2e/mobile.test.mjs` uses Playwright Chromium with an iPhone viewport to verify upload, save, edit, search, archive, restore and deletion, and checks browser errors and horizontal overflow. `PLAYWRIGHT_CHROMIUM_EXECUTABLE` optionally selects an installed Chromium. Screenshots go to `/tmp/form-pwa-qa`.

Physical iPhone camera, Safari keyboard behavior and Home Screen installation require a device check. The automated browser run emulates an iPhone viewport; it is not a physical-device test.

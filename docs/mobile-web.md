# Personal mobile web pivot

## Scope

Use the existing wardrobe service through the mobile-first PWA. The legacy Expo and app-store client has been removed. Keep the existing account and all wardrobe records. `PERSONAL_ACCOUNT_ID` chooses that account on the server, and Tailscale provides the private access boundary. No login or password screen appears in the web client. The old authenticated API mode remains available when that setting is absent.

The website provides batch photo intake, editable saved drafts, optional multi-item detection, a searchable category-filtered wardrobe, wishlist and archive, item editing, original photos, optional catalog images, review and version restoration, permanent item deletion and a confirmed wardrobe reset. It uses native document scrolling, safe-area padding, 16px form inputs, accessible dialogs and reduced-motion support. Offline mode can open the shell and explains that the server connection is required. Saved outfit generation is outside this pivot because it was not implemented in the existing service.

## Cost findings

The deployed image pricing configuration used `1` for every microdollar-per-million rate. Existing generation costs therefore are not trustworthy. Historical ledgers are left intact and the UI labels the old tiny totals as invalid.

The official pricing page, checked on 2026-09-06, lists GPT Image 2 at $5 per million text input tokens, $8 per million image input tokens and $30 per million image output tokens. The corrected runtime values are 5000000, 8000000 and 30000000 microdollars per million tokens. Source: https://developers.openai.com/api/docs/pricing

Applying those rates to the existing saved usage yields $0.011413 to $0.018946 per low-quality image. This is a retrospective estimate at current standard rates, not an invoice reconciliation or a guaranteed future price. It excludes separate detection calls. The private API rejects higher-quality requests. Photo-only intake has no provider cost. Detection and generation each require an explicit user action; uploading does not enqueue either.

## Verification

Unit and contract suites cover the existing service. `apps/api/src/personal.test.ts` exercises personal access, idempotent photo intake, real thumbnail creation, cross-origin write rejection, quality restriction, reset confirmation, active-job protection and account isolation against disposable PostgreSQL and MinIO. Run together with the existing integration tests, sequentially, using `FORM_RUN_SERVICE_INTEGRATION=true` and a test-only environment file.

`apps/web/e2e/serve.mjs` starts the fixture API and static website on loopback port 18444. It requires `FIXTURE_RESET_ALLOWED=true` and resets the disposable fixture data. Start with Node 24, `--env-file` pointing at the disposable services and `--import tsx`. `apps/web/e2e/mobile.test.mjs` uses Playwright Chromium with an iPhone viewport to verify upload, save, edit, search, archive, restore and deletion, and checks browser errors and horizontal overflow. `PLAYWRIGHT_CHROMIUM_EXECUTABLE` optionally selects an installed Chromium. Screenshots go to `/tmp/form-pwa-qa`.

Physical iPhone camera, Safari keyboard behavior and Home Screen installation require a device check. The automated browser run emulates an iPhone viewport; it is not a physical-device test.

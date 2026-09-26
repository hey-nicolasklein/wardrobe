# Accounts, credits, and billing

Status as of 2026-09-26. Target: a few thousand users at most, a few hundred in
the first months. Build what holds at that size, and keep every step replaceable.

## Decisions

| Topic | Decision | Why |
| --- | --- | --- |
| Identity | Keep our own sessions. Add Apple and Google as sign-in methods by verifying their ID tokens. | No auth vendor, no per-user fees, and no identity data outside our database. |
| Providers | Sign in with Apple and Google. Password stays for CLI/admin accounts. | Apple requires its own sign-in once Google is offered (App Review 4.8). |
| Dev sign-in | `POST /v1/auth/dev` behind `DEV_SIGN_IN=true`, button only in Flutter debug builds. | Simulators never go through Apple or Google. |
| Metering | Credits in an append-only ledger. Plans and packs only grant credits. | Pricing stays data. The backend only asks "enough credits?". |
| Private deployment | Existing accounts are `metered = false`. `PERSONAL_ACCOUNT_ID` mode keeps working unchanged. | stargate keeps running without credits. |
| Rate limits | In-memory per IP on auth routes. At most 5 active jobs per metered account. | Enough for one API instance. |

## What is built

**Schema** (`packages/service/migrations/017_identities_and_credits.sql`)
- `account_identities`: `(provider, subject)` is unique. Providers are `apple`, `google`, `dev`.
- `accounts.password_hash` is now nullable. New `accounts.metered` column.
- `credit_ledger`: the balance is `SUM(delta)`. Reasons are `signup`, `grant`, `job`, `refund`. Each job gets at most one charge and one refund.

**Identity** (`packages/service/src/auth.ts`)
- `createIdentityTokenVerifier` checks tokens against Apple's and Google's public keys (JWKS), issuer, audience, and a verified email.
- `signInWithIdentity` finds or creates the account. A verified email that matches an existing account links the identity to it. New accounts are metered and get `signupCredits` (40).

**Credits** (`packages/service/src/credits.ts`, `jobs.ts`)
- Charges happen in `enqueueJob`. Every generation passes through it, so there is one enforcement point.
- A replayed idempotency key is not charged again.
- A job that ends in `failed` is refunded in `failJob` and `recoverExpiredLeases`. Retries of the same job cost nothing extra.
- Costs are `jobCreditCost`: detection 0, shelf image 1, look 2, character sheet 2.

**API** (`apps/api/src/app.ts`)
- `POST /v1/auth/apple`, `POST /v1/auth/google` with `{ idToken, transport }`.
- `POST /v1/auth/dev` with `{ email, transport }`, only when `DEV_SIGN_IN=true`.
- `GET /v1/credits` returns `{ metered, balance }`.
- `DELETE /v1/account` deletes all records and S3 objects. Returns 403 in personal mode, 409 while a job is running.
- Errors: `402 insufficient-credits`, `429 too-many-active-jobs`, `429 rate-limited` (10 auth POSTs per IP and minute).
- Config: `APPLE_CLIENT_IDS`, `GOOGLE_CLIENT_IDS`, `DEV_SIGN_IN`.

**Flutter** (`apps/mobile`)
- `SessionStore` keeps the token in Keychain/Keystore. `FormApi` attaches it as a Bearer header, only for our own API host.
- `SignInPage` is shown by the connection gate on `missingSession`. It offers Apple (iOS), Google (if client IDs are set), and the dev sign-in in debug builds.
- The Settings account section has sign-out and account deletion. The wardrobe reset stays hidden for signed-in accounts.

## Developing without Apple

1. Set `DEV_SIGN_IN=true` in `apps/api/.env.local`, then restart `npm run dev:api`.
2. Run the app in debug and tap **Sign in without password**. The email field chooses the account, so `a@form.local` and `b@form.local` are two separate test users.
3. To test running out of credits, use SQL for now:
   `INSERT INTO credit_ledger (id, account_id, delta, reason) VALUES (gen_random_uuid(), '<id>', -40, 'grant');`

Never set `DEV_SIGN_IN` on a reachable host. The API logs a warning at startup when it is on.

## Setup still needed for real sign-in

**Apple**
- In Xcode, go to Runner → Signing & Capabilities and add **Sign in with Apple** for both flavors. Automatic signing registers the capability.
- `APPLE_CLIENT_IDS=de.nicolasklein.form,de.nicolasklein.form.dev`.
- An Apple Services ID is only needed later, for web or Android Apple sign-in.

**Google** (Google Cloud Console, free)
- Create OAuth clients: one iOS (bundle ID), one Android (package plus SHA-1 per signing key), and one Web ("server client").
- iOS: add the reversed iOS client ID as a URL scheme in `ios/Runner/Info.plist`.
- App config: `GOOGLE_IOS_CLIENT_ID` and `GOOGLE_SERVER_CLIENT_ID` in `.env.<flavor>.json`.
- API: `GOOGLE_CLIENT_IDS=<ios client id>,<web client id>`. Android tokens carry the web client ID as their audience.

## Unit economics (estimate from the rate cards)

| Action | Cost |
| --- | --- |
| Detection (gpt-5.4-mini) | ~$0.001–0.003 |
| Shelf image (gpt-image-2.5-flare, 1536 output tokens) | ~$0.06 |
| Look 768×960 with references | ~$0.08–0.12 |

- Onboarding (30 items): ~$2 once. Active user: ~$2.50/month. Heavy user: $10+.
- Credit value today: 1 credit ≈ $0.05–0.06 of API cost.
- Check this against `/v1/generation-costs` before fixing prices.

## Pricing proposal (not built)

- **Free**: 40 credits once at sign-up. One grant per Apple/Google identity.
- **Pro**: €7.99/month for 150 credits. At €5.99 the margin only holds if people leave credits unused.
- **Pack**: 100 credits for €4.99.
- Apple and Google take 15% under their small business programs. Prices include VAT.

## Next steps (not started)

1. **Credit visibility in the app.** Show the balance from `/v1/credits` in Settings and the composer, and map 402 to a clear upgrade message.
2. **RevenueCat.** Store purchases on iOS and Android. It is free up to $2.5k monthly tracked revenue, then 1%.
   - New `entitlements` table (account_id, plan, period_end, store, original_transaction_id).
   - A webhook `POST /v1/billing/revenuecat` books `grant` entries: the monthly allowance on each renewal, and packs on purchase.
   - Use our account ID as the RevenueCat app user ID.
   - Add Stripe only if a web checkout becomes necessary.
3. **Public host.** stargate stays private. For real users:
   - Hetzner VPS (~€10–20/month) with Docker Compose (API, worker, web), managed or backed-up Postgres, and S3-compatible storage (Cloudflare R2 or Hetzner Object Storage, ~€5/month).
   - Caddy for TLS. Offsite nightly `pg_dump`.
   - Reverse proxy must set `X-Forwarded-For`, because the rate limiter trusts it.
4. **Legal.** Privacy policy, imprint, terms, and a data processing agreement with OpenAI. Photos of people are personal data under GDPR. Account deletion is already built.
5. **Email fallback.** If users ask for it, use one-time email codes rather than passwords, sent through Resend (free up to 3k/month). This avoids password reset flows.
6. **Hardening when traffic grows.**
   - Add a `nonce` to Apple and Google sign-in against token replay.
   - Move rate limits to Postgres or Redis once there are several API instances.
   - Expire old `sessions` rows.
   - Add an admin CLI for `grant` credits.

## Fixed costs

| Item | Cost |
| --- | --- |
| Apple Developer Program | $99/year |
| Google Play Console | $25 once |
| Hosting (next step 3) | ~€20–30/month |
| RevenueCat, Resend, Google OAuth | €0 at this size |

The real variable cost is the OpenAI API, and credits cap it per user.

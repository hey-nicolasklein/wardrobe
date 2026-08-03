# `@form/service`

This server-only package owns the persistence boundary shared by the API and remote-image worker.

- Ordered SQL migrations model accounts, sessions, private assets, Source Photos, Wardrobe Items, proposals, attempts, immutable Shelf Image Versions, idempotent commands, and remote-image jobs.
- Database triggers reject cross-account relationships even if an application query is wrong.
- The private object-store adapter creates a versioned bucket and issues short-lived upload and download URLs. It never makes the bucket or an object public.
- Queue claims use row locks, transaction-scoped account locks, global/per-account limits, leases, bounded retries, and abandoned-lease recovery.
- Health checks distinguish process liveness from PostgreSQL and object-storage readiness.

Migration files are immutable after release. `migrateDatabase` records each applied filename and runs each pending migration in its own transaction.

## Deterministic local scenarios

`npm run fixtures:reset` deletes every application row in the configured **local** database and replaces only the `fixtures/` object prefix. It refuses remote hostnames and also requires `FIXTURE_RESET_ALLOWED=true`.

The reset is repeatable and creates:

- `owner@example.test`: ready, needs-review, queued, failed, archived, and multiple-version records;
- `empty@example.test`: a second empty account for empty-state and cross-account-denial checks;
- private one-pixel fixture media under account-owned asset records;
- queued and terminal-failure durable jobs.

Fixture password hashes are intentional placeholders until the authentication ticket owns the credential implementation. No fixture credential can authenticate yet.

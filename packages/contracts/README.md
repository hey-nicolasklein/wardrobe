# `@form/contracts`

This package is the runtime-validation boundary shared by native, web, API, and worker code.

- Parse untrusted values with the exported Zod schemas before treating them as contract types.
- Import inferred TypeScript types from the same schema source; do not maintain parallel interfaces.
- Keep wire payloads strict and additive changes backwards-compatible within `contractVersion`.
- Require idempotency keys on commands that the outbox or network layer may replay.
- Keep secrets, signed URL persistence, database records, and provider-specific payloads out of this package.

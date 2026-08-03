---
title: Model the persistent wardrobe and its lifecycle
label: wayfinder:task
status: closed
assignee: hey-nicolasklein
parent: ../map.md
github_issue: https://github.com/hey-nicolasklein/wardrobe/issues/2
blocked_by:
  - ./03-build-the-durable-service-foundation.md
  - ./04-enforce-accounts-and-private-media.md
---

## Question

Implement Source Photos, detections, Wardrobe Items, editable metadata, Wanting/Owning/Archive transitions, Shelf Image versions, immutable generation attempts, and explicit permanent deletion with stable IDs and idempotent API commands.

## Resolution

Added one account-scoped wardrobe module for Source Photo detections, Wardrobe Item creation and reads, editable metadata, reversible Wanting/Owning/Archive state, immutable generation attempts, explicit Keep and version restoration, and permanent deletion. Detection proposals retain their original provider suggestion while corrected Item Metadata becomes authoritative on the durable item; generation attempts snapshot those reviewed inputs before any paid work begins.

Every replayable command now uses an account-scoped idempotency key and request fingerprint. Item edits and destructive actions additionally enforce optimistic record versions, so duplicate offline replays return their original response while stale or reused commands fail without silently overwriting newer state. The Hono API exposes runtime-validated list, detail, detection, creation, edit, generation, Keep, and deletion boundaries without leaking another account's records.

Database triggers protect account provenance and immutable detection, generation-input, and Shelf Image Version history. Permanent deletion removes an item's jobs and history, retains a shared Source Photo while another item depends on it, and removes every version of dependent private objects after the final item is gone. Contract tests and serialized PostgreSQL/MinIO integration scenarios prove state continuity, replay behavior, stale-write conflicts, Keep history, cross-account denial, and final-source cleanup.

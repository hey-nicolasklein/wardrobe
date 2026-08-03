---
title: Build the durable service foundation
label: wayfinder:task
status: closed
assignee: hey-nicolasklein
parent: ../map.md
github_issue: https://github.com/hey-nicolasklein/wardrobe/issues/12
blocked_by:
  - ./02-establish-the-production-workspace.md
---

## Question

Implement the Hono service, PostgreSQL schema and migrations, private S3-compatible asset storage, PostgreSQL-backed durable jobs, health checks, and deterministic local fixture reset needed by every product flow.

## Resolution

Added `@form/service` as the shared durable-infrastructure boundary for the API and worker. Ordered, advisory-locked PostgreSQL migrations establish account ownership, private asset metadata, fixture scenarios, and one remote-image job queue. The queue provides account-scoped idempotency, `FOR UPDATE SKIP LOCKED` claiming, configurable concurrency, bounded transient retries, heartbeats, and abandoned-lease recovery without Redis.

Private S3-compatible storage now uses account-prefixed object keys and short-lived signed upload and download URLs. Upload completion verifies stored content metadata, reads require an account-owned available record, buckets remain anonymous-read denied, and fixture reset deletes only known fixture-account prefixes before recreating two stable cross-account test identities.

The Hono API runs migrations at startup and exposes separate liveness and PostgreSQL/object-storage readiness probes. The worker runs the shared leased consumer boundary ready for later GPT handlers. Disposable PostgreSQL and MinIO services, migration/reset commands, unit coverage, and a real-service integration test prove idempotent jobs, private media isolation, and restart recovery.

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

Added the shared server-only `@form/service` boundary with transactional ordered PostgreSQL migrations for accounts, sessions, private assets, Source Photos, Wardrobe Items, proposals, generation attempts and costs, immutable Shelf Image Versions, replay records, and durable remote-image jobs. Database triggers reject cross-account relationships across every persisted association rather than relying only on application queries.

Private S3-compatible storage now creates a versioned, non-public bucket and provides narrow signed upload/download operations. The durable queue uses row locking, transaction-scoped account locks, configurable global and per-account concurrency, bounded attempts, leases, ownership-checked completion, retry scheduling, and abandoned-lease recovery. API liveness is independent of dependencies while readiness checks PostgreSQL and object storage; API and worker startup apply migrations and verify their service boundary.

Pinned local PostgreSQL and MinIO containers, environment examples, migration commands, and a remote-host-restricted fixture reset make development repeatable. The reset creates empty, populated, queued, failed, needs-review, archived, multiple-version, and cross-account-denial scenarios without retaining prior fixture object versions. Unit tests, real PostgreSQL/MinIO integration tests, API health requests, worker startup, and the monorepo verification suite prove the foundation.

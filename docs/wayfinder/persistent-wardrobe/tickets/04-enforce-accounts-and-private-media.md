---
title: Enforce lightweight accounts and private media
label: wayfinder:task
status: closed
assignee: hey-nicolasklein
parent: ../map.md
github_issue: https://github.com/hey-nicolasklein/wardrobe/issues/6
blocked_by:
  - ./03-build-the-durable-service-foundation.md
---

## Question

Implement administrator-created credentials, cookie and native-token sessions, centralized ownership checks, authorized upload/read flows, secure native credential storage, and cross-account denial tests.

## Resolution

Added administrator-only account creation with normalized emails and salted scrypt password hashes. Browser and native authentication now share one database-backed session model: the API issues secure HTTP-only SameSite cookies for web and opaque tokens for native, stores only HMAC token hashes, restores and revokes sessions, and rejects expired or disabled-account credentials. The Expo client keeps native tokens in SecureStore while web JavaScript never receives its cookie credential.

Private Source Photo ingestion now creates account-owned pending assets and short-lived signed upload URLs after authentication. Completion validates the uploaded byte count, decoded file type, and pixel dimensions before making an asset ready, persists an idempotent Source Photo record, and returns no cross-account data. Authenticated asset reads perform the same centralized owner resolution before issuing short-lived signed download URLs; object keys and buckets remain private.

Two fixture accounts now use real credential hashes. Contract, password, cookie, token, upload, download, replay, and cross-account denial coverage runs through the monorepo verification suite and serialized PostgreSQL/MinIO integration tests using actual signed PUT and GET requests.

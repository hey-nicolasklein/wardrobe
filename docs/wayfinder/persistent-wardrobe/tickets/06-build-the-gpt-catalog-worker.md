---
title: Build the durable GPT wardrobe-ingestion pipeline
label: wayfinder:task
status: closed
assignee: hey-nicolasklein
parent: ../map.md
github_issue: https://github.com/hey-nicolasklein/wardrobe/issues/3
blocked_by:
  - ./05-model-the-persistent-wardrobe.md
---

## Question

Implement current server-side GPT vision detection with strict boxes and metadata, reviewed target crops, Low-quality 816 × 816 `gpt-image-2` edits, chroma validation/removal, usage accounting, durable job recovery, retry classification, and replay providers.

## Resolution

Built one leased remote-image worker that runs server-side strict GPT vision detection and reviewed-target `gpt-image-2` edits through replaceable OpenAI and replay providers. Source Photos are orientation-normalized, reviewed normalized boxes become 18%-padded references, and generation uses the versioned laid-flat prompt with explicit Low/Medium/High quality and the 816 × 816 default.

Provider output now passes inferred-corner chroma validation and narrow-edge feathering before the transparent Shelf Image is written. Raw keyed output, transparent output, and reference crops remain private versioned assets. Completed attempts enter `needs-review` only after a complete immutable ledger records split token usage, dated rate snapshots, service tier, request ID, component costs, total cost, resolved chroma key, and raw provider usage.

The worker renews leases, recovers abandoned work, retries one transient connection/timeout/rate-limit/provider-server failure with backoff, and makes validation, conversion, moderation, authentication, quota, accounting, and chroma failures terminal. Routine unit and PostgreSQL/MinIO integration coverage uses private-safe replay/synthetic fixtures; no paid call is part of verification.

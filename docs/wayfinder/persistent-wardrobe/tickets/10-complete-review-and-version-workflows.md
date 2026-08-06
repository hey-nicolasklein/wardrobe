---
title: Complete review, version, and lifecycle workflows
label: wayfinder:task
status: closed
assignee: hey-nicolasklein
parent: ../map.md
github_issue: https://github.com/hey-nicolasklein/wardrobe/issues/7
blocked_by:
  - ./08-build-browsing-details-and-offline-state.md
  - ./09-build-the-guided-add-flow.md
---

## Question

Implement Keep, Regenerate, Reject, version history and restore, visible costs and provenance, failed-job recovery, Wanting-to-Owning transitions, Archive, and explicit permanent deletion across native and web clients.

## Resolution

Wardrobe Item details now carry the persistent wardrobe loop through its explicit review and lifecycle decisions on iPhone and web. A completed Shelf Image can be kept, rejected, or rejected-and-regenerated; Reject is an optimistic, idempotent service transition that preserves an already-kept current image. Ready and transiently failed items can start another durable paid attempt, while non-retryable failures direct the person back to the editable inputs.

Every immutable generation attempt exposes its reviewed metadata, model, prompt version, output settings, provider request, usage, captured rate date, component costs, total cost, terminal state, and failure category. Kept Shelf Image Versions remain browsable and can be restored without destroying newer history. Collection controls cover Wanting, Owning, and Archive, and permanent deletion is available only from Archive after typing the exact item name; the existing service cleanup retains a shared Source Photo until its final derived item is removed.

The account-scoped integration suite proves Reject idempotency, optimistic concurrency, current-version preservation, Keep, regeneration, restore-compatible edits, collection transitions, and permanent media cleanup against PostgreSQL and MinIO. The Tailscale browser smoke proves the review, provenance, and deletion surfaces in desktop and iPhone-sized Expo Web layouts.

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

Item details now expose the complete connected review loop. A generated Shelf Image awaiting review includes its private preview, model, quality, output size, and recorded cost, with explicit Keep and Reject actions. Items can queue another default generation, failed attempts expose their failure category and a Retry Generation action, and active durable work remains visibly in progress after leaving the screen.

Kept Shelf Images remain immutable history. Every version has a private fullscreen preview and can be restored as the current image without creating new paid work; the current version is visibly distinguished. All review and restore commands are account-scoped, optimistic, and idempotent, and the shared API contract advances to version 4 for the new reject and restore commands.

Owning, Wanting, and Archive remain reversible lightweight edits, while permanent deletion is an online-only destructive action with a platform-appropriate confirmation and explicit warning about item history and unshared media. Native and web clients share the same authenticated command surface and refresh their cached detail/list state after lifecycle actions.

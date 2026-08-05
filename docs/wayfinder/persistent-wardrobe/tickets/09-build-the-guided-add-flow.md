---
title: Build the guided multi-item Add flow
label: wayfinder:task
status: closed
assignee: hey-nicolasklein
parent: ../map.md
github_issue: https://github.com/hey-nicolasklein/wardrobe/issues/4
blocked_by:
  - ./06-build-the-gpt-catalog-worker.md
  - ./07-build-the-native-app-shell.md
---

## Question

Implement camera/gallery ingestion, HEIC normalization, explicit analysis, synchronized bounding-box and proposal selection, separate editable metadata review, one batch confirmation, immediate draft persistence, and understandable per-item job states.

## Resolution

Add now opens a four-step, full-height native form sheet that accepts either a new camera photo or one chosen from the photo library. The client normalizes the selected image to an orientation-correct quality-92 JPEG before preview or upload, including HEIC and HEIF inputs, then uses the authenticated private upload-intent boundary rather than embedding image data in an API request. Upload, detection, and generation controls explain and enforce their online-only boundary.

Analysis remains an explicit action. Once requested, the screen polls the durable detection attempt and distinguishes queued, processing, succeeded, failed, and empty-result outcomes. The authenticated detection response now includes the latest account-scoped attempt beside its proposals, so reconnecting clients can display real server state instead of treating an empty proposal list as progress. Contract version 3 records that response change.

Successful analysis presents the normalized Source Photo with proposal bounding boxes synchronized to the focused proposal card. Supported items begin selected, unsupported wearables are visibly excluded, and the user can include or omit every proposal. A separate metadata step edits each selected item's name, strict category, colors, manual notes, and Owning or Wanting destination; unsupported proposals cannot proceed until assigned a supported category.

One final confirmation creates every selected Wardrobe Item and then enqueues exactly one default Low-quality 816 × 816 generation per saved draft. Per-item feedback distinguishes saving, durably saved, generation queued, and needs-attention outcomes, including the partial-success case where a draft persists even if generation enqueue fails. The wardrobe cache refreshes after the batch, while the server-owned jobs continue independently of the Add screen.

Focused tests cover supported and unsupported proposal initialization plus reviewed-metadata validation. Repository verification passes all workspace typechecks and unit suites under Node 24 and successfully exports the Expo web application.

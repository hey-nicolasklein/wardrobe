# Slice 3: clothing intake

## Outcome

Deliver durable camera and photo-library intake from local selection through
detected or manual wardrobe creation and automatic catalog-image enqueueing.

Read [`stage-1-spec.md`](stage-1-spec.md). This slice owns every `I3` item in
[`parity-checklist.md`](parity-checklist.md).

## Dependencies

Slices 1 and 2 are complete. Reuse their API, cache, media, wardrobe refresh,
error mapping, and connectivity boundaries.

## Ownership

Primary code lives in:

- `apps/mobile/lib/features/intake`
- source-photo, detection, and draft repositories
- intake DTOs, domain models, Drift tables, and protected draft files
- narrowly shared image preparation utilities

## Work

1. Implement camera capture and multi-photo library selection with point-of-use
   permissions and clear denied-permission recovery.
2. Validate the original file, correct orientation, decode HEIC/HEIF, and write
   baseline-compatible JPEG output at quality 0.92 and a 2,400-pixel maximum
   long edge.
3. Create each durable local draft before network work begins. Keep its logical
   command keys stable across retries and process restarts.
4. Upload photos sequentially through upload intent, object upload, and source
   completion. Represent progress and individual failure without losing other
   drafts.
5. Start detection after completion and poll while foregrounded. Resume status
   checks after route return or app foregrounding.
6. Render normalized detection boxes and cropped proposal previews from the same
   source geometry. Support selection and batch or per-item ownership state.
7. Save selected proposals idempotently, enqueue each default catalog image
   once, refresh Wardrobe, and retain any partially completed draft accurately.
8. Implement the validated manual path for failed or empty detection.
9. Implement explicit discard and protected-file cleanup.
10. Unit-test all state transitions and resolve the owned checklist items.

## Unit tests

- file limit and output-dimension calculations
- normalized bounding-box conversion and crop calculations
- draft persistence and restoration for every phase
- stable idempotency keys across retry and restart
- sequential upload success, partial failure, retry, and cancellation decisions
- detection polling lifecycle and foreground resumption
- proposal selection and batch versus per-item ownership
- partial item creation and automatic-generation enqueue state
- manual fallback validation
- Intake Bloc event ordering and state transitions

## Completion criteria

- Every `I3` checklist item is checked.
- Killing and reopening the app preserves every unfinished draft and never
  duplicates a completed logical server command.
- Leaving intake never owns the lifetime of server jobs.
- Offline intake shows saved drafts while all upload, analysis, and save actions
  remain disabled.
- Successful completion refreshes the Wardrobe cache and removes only finished
  draft files.
- `fvm flutter analyze` and `fvm flutter test` pass.

## Exclusions

Share extensions, document import, background upload, background polling, push
notifications, and offline wardrobe creation remain outside Stage 1.


# Slice 5: character references

## Outcome

Deliver complete personal-reference management from one to four local photos to
the exact reviewed active collage, including history, activation, replacement,
detail, pending or failed states, and deletion.

Read [`stage-1-spec.md`](stage-1-spec.md). This slice owns every `C5` item in
[`parity-checklist.md`](parity-checklist.md) and closes the missing-reference Feed
route left by Slice 4.

## Dependencies

Slices 1 through 4 are complete. Reuse intake image preparation, protected local
files, upload boundaries, cached media, and app lifecycle refresh.

## Ownership

Primary code lives in:

- character-reference modules under `apps/mobile/lib/features/settings`
- character-reference repository write operations and cached detail
- reusable crop and collage utilities justified by both current and future use

## Work

1. Implement one-to-four photo selection and baseline-compatible normalization.
2. Implement per-photo pan and zoom crop with deterministic crop geometry and a
   low-resolution warning.
3. Assemble the baseline collage layout locally and show the exact final image
   before upload. Preserve edits when moving backward and forward.
4. Persist the optional note, upload the reviewed collage, and create the active
   ready character reference with one stable idempotency key.
5. Render active, historical, pending, and failed references from cached and
   refreshed server state.
6. Implement reference detail, activation, replacement collage creation, and
   confirmed deletion of eligible inactive references.
7. Connect the missing-reference Feed action directly to setup and return to the
   refreshed Feed after successful creation.
8. Style every new screen and state to PWA parity with the FORM components,
   following [`visual-guide.md`](visual-guide.md). Add missing components to
   the shared set rather than styling locally.
9. Unit-test crop, collage, repository, and state logic. Resolve the owned
   checklist items.

## Unit tests

- crop bounds, pan clamping, zoom, and output-resolution warning
- deterministic one-to-four-photo collage geometry
- exact preview-to-upload byte source selection
- stable idempotency through upload retry
- reference state sorting and active selection
- activation, replacement, and deletion eligibility
- cached refresh and foreground state transitions
- Character Reference Bloc and Cubit transitions

## Completion criteria

- Every `C5` checklist item is checked.
- The uploaded reference is the exact locally reviewed collage rather than a
  newly rendered derivative.
- A new collage becomes active and Feed refreshes against it.
- Historical activation and eligible deletion update cache only after server
  success.
- Pending and failed records remain understandable after process restart.
- Every new screen and state has a PWA screenshot pair with no unexplained
  difference.
- `fvm flutter analyze` and `fvm flutter test` pass.

## Exclusions

Server refinement was removed in `11ead56`. The current contract has no
refinement endpoint or field. Stage 1 creates replacement collages through the
current PWA flow. See the C5 contract decisions and remaining screenshot
acceptance in [`parity-checklist.md`](parity-checklist.md).


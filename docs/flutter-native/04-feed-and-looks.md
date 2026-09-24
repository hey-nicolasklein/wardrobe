# Slice 4: feed and looks

## Outcome

Deliver the cached inspiration feed and the complete look lifecycle, including
composition, generated states, Worn and Flat exploration, variations, sharing,
Photo saving, retry, and deletion.

Read [`stage-1-spec.md`](stage-1-spec.md). This slice owns every `L4` item in
[`parity-checklist.md`](parity-checklist.md), except the final setup destination
behind a missing character reference, which closes with Slice 5.

## Dependencies

Slices 1 through 3 are complete. Use the Wardrobe repository as the only source
of eligible garment domain models and private item media.

## Ownership

Primary code lives in:

- `apps/mobile/lib/features/feed`
- look and character-reference read repositories
- look DTOs, domain models, Drift tables, and cached preview files
- shared Flat layout logic and native share or Photo-save services

## Work

1. Implement strict look DTOs and a cached stale-while-refresh feed repository.
2. Render empty, planning, generating, ready, failed, stale, and offline states.
3. Implement look composition with item search, category filters, selected-only
   mode, reset, Flat selection preview, occasions, wardrobe completion, and
   optional category constraints.
4. Submit one stable idempotent create command and show its durable feed state.
5. Implement ready Worn and Flat views. Reveal positioned garments from server
   bounding boxes and route every available garment to item detail.
6. Finish the Wardrobe cross-links for ready-look appearances and preselected
   inspiration.
7. Persist liked and saved markings locally while online. Render them read-only
   from cache while offline.
8. Implement variations, same-piece composition, supported quality upgrades,
   detail, retry, and confirmed deletion.
9. Implement native sharing and point-of-use Photo saving for both Worn and Flat
   output. Preserve full-quality output and localized captions.
10. Style every new screen and state to PWA parity with the FORM components,
    following [`visual-guide.md`](visual-guide.md). Add missing components to
    the shared set rather than styling locally.
11. Unit-test non-visual logic and resolve every owned checklist item that does
    not depend on the Slice 5 setup route.

## Unit tests

- look DTO parsing, domain mapping, and cached ordering
- state rendering decisions for planning through failure
- eligible-item search, filtering, selected-only mode, and reset
- create, retry, variation, recombination, and upgrade request construction
- idempotency-key reuse
- deterministic Flat layout and Worn garment-position calculations
- local liked and saved persistence plus offline read-only behavior
- share and Photo-save source selection
- Feed and Composer Bloc transitions and polling lifecycle

## Completion criteria

- Every independently completable `L4` checklist item is checked.
- Cached ready looks and media remain browseable offline without mutations.
- Every server-owned look state survives route changes and foreground refresh.
- Worn and Flat sharing and Photo saving select the representation currently
  requested by the user.
- Item-to-look and look-to-item navigation is complete.
- The missing-reference action reaches the route boundary Slice 5 will fulfill.
- Every new screen and state has a PWA screenshot pair with no unexplained
  difference.
- `fvm flutter analyze` and `fvm flutter test` pass.

## Exclusions

Character-reference creation is Slice 5. Background polling, push
notifications, remote liked or saved synchronization, and social features
remain outside Stage 1.


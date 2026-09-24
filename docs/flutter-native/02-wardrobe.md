# Slice 2: wardrobe browsing and item lifecycle

## Outcome

Deliver the complete daily wardrobe slice: cached browsing, discovery, item
details, online editing, catalog-image lifecycle, archive, and deletion.

Read [`stage-1-spec.md`](stage-1-spec.md) and the completed foundation handoff.
This slice owns every `W2` item in
[`parity-checklist.md`](parity-checklist.md). Items tagged `L4` stay open for the
Feed and Looks slice.

## Dependencies

Slice 1 is complete. The API and service remain the authorities for item state,
record versions, generation jobs, and private media.

## Ownership

Primary code lives in:

- `apps/mobile/lib/features/wardrobe`
- wardrobe, generation, and media repositories
- wardrobe DTOs, domain models, and Drift tables
- shared media widgets justified by this slice

Backward-compatible API and contract changes are allowed when a real native gap
is demonstrated.

## Work

1. Map baseline list and detail payloads into explicit DTOs, domain models, and
   cached records. Preserve record versions and immutable asset identity.
2. Implement stale-while-refresh list loading, thumbnail prefetch, bounded media
   caching, pull-to-refresh, and read-only offline browsing.
3. Implement the active collection grid, All/Owning/Wanting state filters,
   category filters, color-family filters, search, counts, and empty states.
4. Implement item detail with current catalog image, source photo, metadata,
   cached offline state, and online editing.
5. Implement catalog generation and improvement with quality, feedback,
   durable progress, manual refresh, auto-adoption, version history, and restore.
6. Implement archive, archived browsing, restore, and confirmed permanent item
   deletion. Apply cache changes only after server success.
7. Implement the media-cache clear primitive used later by Settings while
   protecting drafts and active-operation files.
8. Unit-test all non-visual logic and resolve the owned checklist items.

## Unit tests

- strict item and detail DTO parsing and serialization
- DTO-to-domain and domain-to-cache mapping
- recency sorting, text search, category filtering, and color-family filtering
- combined and reset filter behavior
- stale refresh success and failure
- generation state reduction and idempotency-key reuse
- record-version command construction
- media-cache indexing, access updates, eviction, and protected files
- Wardrobe and Item Cubit or Bloc transitions

## Completion criteria

- Every `W2` checklist item is checked.
- A previously synchronized wardrobe and item detail remain browseable without
  a server connection, with every mutation disabled.
- Every successful online mutation refreshes the authoritative item and cache.
- Failed refreshes preserve usable cached content.
- The PWA continues working against any API changes.
- `fvm flutter analyze` and `fvm flutter test` pass.

## Exclusions

Look appearances and preselected inspiration are completed in Slice 4. Offline
editing, an outbox, conflict UI, background jobs, and push notifications remain
outside Stage 1.


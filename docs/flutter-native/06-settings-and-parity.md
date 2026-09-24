# Slice 6: settings and parity closure

## Outcome

Complete Settings, close every remaining parity edge, and prepare the iOS app
for Nico's physical-device acceptance without expanding Stage 1 scope.

Read [`stage-1-spec.md`](stage-1-spec.md). This slice owns every `S6` item in
[`parity-checklist.md`](parity-checklist.md) and audits every earlier ownership
tag.

## Dependencies

Slices 1 through 5 are complete and their checklist items contain evidence or a
specific unresolved note.

## Ownership

This slice may change any Stage 1 Flutter feature to close a verified parity
gap. It owns Settings presentation, preference repositories, generation-cost
presentation, local cache controls, application information, and full reset.

## Work

1. Implement immediate persisted German and English selection.
2. Implement independent persisted default quality for Feed and Wardrobe.
3. Implement generation-cost loading and the baseline total, counts, average,
   character-reference contribution, and visual split.
4. Complete Settings composition for character references, archive entry,
   private-server details, app version, and downloaded-cache clearing.
5. Evolve full reset additively so Flutter validates a localized typed phrase
   and sends a locale-independent confirmation while the PWA's German value
   continues to work.
6. Clear matching local account cache, drafts, files, and obsolete look markings
   only after successful reset. Preserve language and default-quality settings.
7. Style Settings, cost presentation, and reset to PWA parity following
   [`visual-guide.md`](visual-guide.md).
8. Audit every screen for generated localization keys, English completeness,
   error-code translation, visual parity with the PWA, portrait behavior, and
   offline mutation guards.
9. Walk every checklist item against the baseline source. Close it with code and
   unit tests or record an explicit scope decision approved by Nico.
10. Run final local verification and confirm Android remains buildable.
11. Hand the iOS build and concise manual verification notes to Nico.

## Unit tests

- locale and quality preference persistence
- cost aggregation and display-model calculations
- cache-clear protection for drafts and active files
- localized full-reset phrase validation
- locale-independent reset request and legacy PWA compatibility
- successful and failed reset local-state behavior
- every non-trivial gap fixed during the parity audit

## Completion criteria

- Every checklist item is checked or carries an explicit Nico-approved scope
  note.
- German and English contain no hard-coded user-facing copy or placeholders.
- Every Stage 1 API error code has localized production copy.
- Full reset preserves PWA compatibility and clears local state only after
  server success.
- Every screen matches the PWA visually or carries a recorded intended
  deviation.
- `fvm flutter analyze` and `fvm flutter test` pass with unit tests only.
- Android remains buildable as the secondary target.
- The complete iOS app is ready for Nico's physical-device acceptance.

## Exclusions

Store delivery, accounts, monetization, public backend exposure, telemetry,
dark mode, landscape, tablet polish, dedicated accessibility work, hosted CI,
and broader automated test types remain later work.

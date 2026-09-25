# Flutter Stage 1 parity checklist

This checklist is the single source of truth for Stage 1 coverage against PWA
baseline `68b421bc4c047e03bf8f9c3a1d3a5f04fadcb341`.

Ownership tags map each item to its delivery slice: `F1` Foundation, `W2`
Wardrobe, `I3` Intake, `V` Visual alignment (Slice 3.5), `L4` Feed and Looks, `C5` Character
References, and `S6` Settings and parity closure.

Mark an item complete only when its behavior exists in Flutter and its required
unit tests pass. Add a short note or source link beside any intentional baseline
deviation before marking it complete.

## Foundation and shell

- [x] `F1` Flutter 3.44.9 is pinned through FVM.
- [x] `F1` Development and production flavors use their agreed identifiers and
      load ignored local API configuration.
- [x] `F1` iOS 16 and Android API 29 are the minimum versions.
- [x] `F1` Both platforms are locked to portrait.
- [x] `F1` The light FORM theme carries the PWA's visual identity. Colors only.
      Full visual parity moves to the `V` items.
- [x] `F1` Feed, Wardrobe, and Settings use independent persistent router stacks.
- [x] `F1` A cold launch opens Feed without restoring a modal flow.
- [x] `F1` German and English initialize from the device locale with German
      fallback.
- [x] `F1` Every initial shell string uses generated keys and `context.tr()`.
- [x] `F1` The app distinguishes unavailable API, missing personal session,
      incompatible contract, empty data, and loaded data.
- [x] `F1` Cached content renders before a background refresh.
- [x] `F1` Offline cached content is read-only and clearly marked stale.
- [x] `F1` Foreground return refreshes the active destination.
- [x] `F1` Logs exclude personal content, request bodies, credentials, and media.

### F1 evidence and validation handoff

Implemented in `apps/mobile`. `README.md` there contains launch instructions,
scaffold audit, the exact manual validation sequence, and generation commands.

- Configuration: `.fvmrc`, native development/production flavors, native minimum
  OS settings and orientation, ignored local JSON files, root `.vscode/launch.json`.
- Theme/navigation: `lib/app/form_theme.dart`, `lib/navigation/app_router.dart`.
  Each branch includes a nested status/server page for manual stack validation.
- Localization: generated keys, both translation assets, `initial_language.dart`,
  and persisted preferences. Covered by `locale_test.dart` and `preferences_test.dart`.
- Access states: `ConnectionCubit`, `FormApi`, and `connection_test.dart`. The
  additive `/v1/meta` API route reports contract version through the existing
  public proxy. API verification passes. Deployment is awaiting explicit approval.
- Cached content in F1 means collection counts on thin shell pages. The full
  record/image views remain W2/L4. `CachedRepository`, `CollectionCountsCubit`, and
  `cache_test.dart` cover cached-first loading, request-authoritative availability,
  empty/loaded states, failed refresh preservation, and read-only stale state.
- Foreground return rechecks access and refreshes the active destination. Both
  summaries refresh after initial access. There is no background polling.
- Logging: `SafeBlocObserver` emits only Bloc type and a fixed event label in
  debug builds. Dio has no request/body logger. Localization logging is disabled.
- Drift v1 creates preferences, server-scoped collection summaries, and the
  protected media index. Unit tests cover schema creation and persisted language.

Native compilation: both iOS simulator flavors and the Android development APK
build. Manual iOS validation remains Nico's next step. The hosted backend is
unchanged until deployment is explicitly approved, so its current missing metadata
endpoint correctly produces the incompatibility screen.

## Visual parity

- [x] `V` One Dart token source mirrors the PWA colors, type scale, serif,
      spacing, radii, and motion curves (`form_tokens.dart`).
- [x] `V` The theme removes ripples, elevation, surface tint, and tonal M3
      colors while keeping native transitions, back-swipe, and system pickers
      (`form_theme.dart`). Screen-level screenshot acceptance is still pending.
- [x] `V` Shared FORM components exist for tab bar, header, buttons, chips,
      search, inputs, image cards, empty and notice states, sheets, and native
      confirmations (`form_components.dart`, bundled tab SVGs in `form_icon.dart`).
- [ ] `V` Shell and foundation access states match the PWA (screenshot pair pending).
- [ ] `V` Wardrobe grid, filters, search, and empty states match the PWA
      (screenshot pair pending).
- [ ] `V` Item detail, editing, generation, versions, and archive match the PWA
      (screenshot pair pending; item routes use root `FormSheetPage` /
      `ModalBottomSheetRoute` with drag dismissal).
- [ ] `V` Intake capture, drafts, progress, detection, proposals, and manual path
      match the PWA (screenshot pair pending; unchecked pending 3.5 visual verification).
- [x] `V` `visual-guide.md` documents tokens, components, and the comparison
      routine.
- [ ] `L4` Feed, composer, and look screens match the PWA.
- [ ] `C5` Character-reference setup, crop, collage, and detail match the PWA
      (implemented with shared FORM components; current screenshot pairs pending).
- [ ] `S6` Settings, cost presentation, and reset match the PWA (functional
      parity implemented; screenshot pair pending — native replaces PWA
      “Auf deinem iPhone” with app/server info per `visual-guide.md`).

## Wardrobe and archive

- [x] `W2` Active items appear in a responsive image grid ordered by recency.
- [x] `W2` All, Owning, and Wanting filters match the baseline.
- [x] `W2` Category filters support every contract category.
- [x] `W2` Color-family filters match the baseline family mappings.
- [x] `W2` Category and color filters combine correctly.
- [x] `W2` Search covers names, localized category labels, colors, and notes.
- [x] `W2` Active filter chips can be removed individually or reset together.
- [x] `W2` Loading, empty, filtered-empty, populated, generating, failed, stale,
      and offline states are represented.
- [x] `W2` Pull-to-refresh updates the cache without discarding usable stale data
      after a failure.
- [x] `W2` Grid thumbnails are prefetched and available offline after caching.
- [x] `W2` Settings opens the archive and archived items can be restored.

## Item details and lifecycle

- [x] `W2` Details show name, category, colors, notes, and collection state.
- [x] `W2` Details show the current catalog image and original source photo.
- [x] `L4` Details include the item's appearances in ready looks.
- [x] `W2` Cached details and media remain browseable offline.
- [x] `W2` Online editing validates and saves metadata.
- [x] `W2` Online editing moves items between Owning and Wanting.
- [x] `L4` Inspiration opens the look composer with the item preselected.
- [x] `W2` Running catalog generation shows durable progress and manual refresh.
- [x] `W2` New catalog generation supports Low, Medium, and High quality.
- [x] `W2` Catalog improvement accepts baseline suggestions and free text.
- [x] `W2` Successful new catalog images are adopted automatically.
- [x] `W2` Immutable catalog versions are shown and an older version can be
      restored.
- [x] `W2` Items can be archived and restored online.
- [x] `W2` Permanent deletion uses a native confirmation and updates the cache
      after server success.

### W2 evidence and validation handoff

Implemented in `apps/mobile`, with manual iOS steps in its `README.md`.

- `WardrobePage`, `WardrobeFilter`, and `WardrobeCubit` cover the responsive grid,
  baseline recency and color families, combined filters, localized search, counts,
  empty states, cached startup, pull refresh, archive, and foreground updates.
- `ItemPage`, `ItemEdit`, and `ItemCubit` cover metadata validation, collection
  changes, source/catalog media, quality and feedback, foreground-only generation
  refresh, history restoration, archive, and confirmed permanent deletion.
- Checked, immutable DTOs preserve record versions and asset identifiers. Drift
  schema v2 persists item/detail snapshots and preserves foundation data on upgrade.
- Successful mutations update the authoritative snapshot and notify the collection
  directly. Failed requests preserve usable cached content. Uncertain command
  retries reuse their idempotency key and block competing new commands.
- `MediaRepository` prefetches versioned thumbnails and downloads full assets on
  demand, with a 200 MiB LRU budget, protected files, immediate offline reads, and
  a downloaded-cache clear primitive for S6. Cache availability is bounded by
  eviction and explicit clearing. Details are cached when opened.
- Unit tests cover parsing/serialization, immutable mappings, filters, generation
  state and foreground polling, stale refresh, mutation cache updates, retry keys,
  media indexing/access/eviction/protection, and the v1-to-v2 migration.
- Validation: `fvm flutter analyze` passes and all 49 unit tests pass. No API or
  PWA changes were needed. Manual iOS verification remains with Nico.

## Clothing intake

- [x] `I3` The Add action opens the intake flow from Wardrobe.
- [x] `I3` The camera captures one rear-camera photo.
- [x] `I3` The photo library selects multiple photos.
- [x] `I3` Inputs enforce the 25 MB baseline limit.
- [x] `I3` Orientation and HEIC/HEIF normalization produce JPEG quality 0.92 with
      a maximum long edge of 2,400 pixels.
- [x] `I3` Local previews appear before upload completes.
- [x] `I3` Photos upload sequentially with per-photo progress and failure state.
- [x] `I3` Draft metadata and protected local files survive app restarts.
- [x] `I3` Drafts remain visible offline while upload, analysis, and save actions
      remain disabled.
- [x] `I3` Detection starts after upload and polls only while the app is active.
- [x] `I3` Detection boxes align to the normalized 1,000-unit coordinate frame.
- [x] `I3` Each proposal has a cropped preview and selection state.
- [x] `I3` Batch Owning or Wanting state can be overridden per proposal.
- [x] `I3` Selected proposals save idempotently and enqueue their default catalog
      images exactly once.
- [x] `I3` Failed or empty detection falls back to validated manual metadata.
- [x] `I3` A draft can be explicitly discarded with its protected files removed.
- [x] `I3` Server-owned work survives leaving intake and refreshes on foreground
      return without background polling.

### I3 evidence and validation handoff

Implemented in `apps/mobile/lib/features/intake`, `IntakeRepository`,
`PhotoPreparation`, and Drift schema v3. Generated intake DTOs preserve normalized
geometry and per-command checkpoints. Draft files are stored outside the media
cache and survive downloaded-cache clearing. Sequential Bloc events freeze save
payloads, retain partial item/generation results, and reuse keys after restart.
Polling follows route visibility and foreground state. Discard prevents subsequent
commands and cleans protected local files without canceling server-owned work.

Unit tests cover dimensions and limits, EXIF normalization, box/crop geometry,
SQLite reopen for every phase, schema migration, retries and lost responses,
partial saves, manual validation, selection/ownership, offline gating, polling,
cancellation, orphan cleanup, and missing native plugin recovery. Analysis and
all 75 unit tests pass. iOS simulator and Android development builds compile. The mobile
README records the manual iOS acceptance steps. Native HEIC/camera/permission
behavior remains for device acceptance. Slice 3.5 owns visual alignment.

## Feed browsing

- [x] `L4` Cached look cards render immediately and remain browseable offline.
- [x] `L4` Feed supports empty, planning, generating, ready, failed, stale, and
      offline states.
- [x] `L4` Feed refreshes at launch, on foreground return, and by pull-to-refresh.
- [x] `L4` A missing active ready character reference routes toward its setup.
- [x] `L4` Planning and generating cards show selected garments when available.
- [x] `L4` Ready cards switch between Worn and Flat views.
- [x] `L4` Worn view reveals positioned wardrobe pieces and opens item details.
- [x] `L4` Flat view opens item details from each available garment.
- [x] `L4` Concept, relative creation date, liked state, and saved state persist
      locally.
- [x] `L4` Local look markings are disabled while offline.

## Look composition and actions

- [x] `L4` Composition accepts zero to twelve exact eligible wardrobe items.
- [x] `L4` Eligible items can be searched and filtered by category.
- [x] `L4` Selected-only mode and reset behave like the baseline.
- [x] `L4` Selected garments have a Flat preview and can be removed there.
- [x] `L4` Surprise, Night Out, Party, and Casual occasions are available.
- [x] `L4` Wardrobe completion can be enabled or disabled.
- [x] `L4` Completion can be constrained by selected garment categories.
- [x] `L4` Look creation submits one idempotent command and opens its feed state.
- [x] `L4` Failed looks can be retried or deleted.
- [x] `L4` Ready looks expose details, variation, same-piece recombination, and
      quality upgrade where supported.
- [x] `L4` Worn and Flat representations share through the native share sheet.
- [x] `L4` Worn and Flat representations save to Photos after point-of-use
      permission.
- [x] `L4` Permanent deletion uses a native confirmation and retains historic
      costs on the server.

### L4 evidence and validation handoff

Implemented in `apps/mobile/lib/features/feed`, `LookRepository`,
`CharacterSheetRepository`, `LookOutputService`, and Drift schema v4
(`look_records`). Strict look DTOs, stale-while-refresh feed cache, local
liked/saved preferences, pending look starts, Worn/Flat layout from PWA logic,
composer with wardrobe cross-links, native share (`share_plus`) and Photos save
(`gal`). Missing active character reference routes to
`/feed/character-setup` (completed by Slice 5). Visual PWA screenshot pair for
feed/composer remains with Slice 3.5 / manual acceptance.

- `FeedPage`, `FeedCubit`, and `LookCard` cover cached startup, pull refresh,
  foreground refresh (via `FormApp`), offline browse, planning/generating/
  ready/failed states, Worn/Flat toggle, the staggered worn reveal from
  category body regions (the server no longer sends look boxes), and
  liked/saved (read-only offline). Looks accept both `1024x1280` and the
  current `768x960` size.
- `LookComposerPage` on `ComposerCubit` covers search, category filter,
  selected-only (ignores search and category, as in the PWA), reset, flat
  preview, occasions, wardrobe completion, category constraints, up to 12 exact
  items, a per-look quality choice, and one idempotency key per composer
  session. Creation opens the Feed. Look details show the image cost.
- Feed actions report failures as localized toasts. Flat-lay export refuses
  looks with missing pieces. Saving to Photos checks access first and uses
  `NSPhotoLibraryAddUsageDescription`.
- `ItemPage` shows ready looks and opens the composer with the item preselected.
- Unit tests: look DTOs, `look_json` normalization, feed domain (age, upgrade
  qualities), flat lay layout, worn positions, look
  commands, look repository (including 204 delete), v3→v4 migration, feed
  cubit, and composer cubit (selection, limit, reset, command, key reuse).
- Validation: `fvm flutter analyze` reports no issues and 106 unit tests pass.
  PWA screenshot pairs are still missing, so the visual `L4` item stays open.

### PWA changes after the baseline

`origin/main` moved past the frozen baseline with four commits (`11ead56`,
`77a686f`, `1a1b733`, `a2397cc`). Slice 4 adopts the contract changes and the
look-related behaviour above. Nico approved these additional changes for Stage 1:

- [x] `accessory` as a full category, with accessory detections opt-in during
      intake (`W2`/`I3`). Approved by Nico. Filters, editing, manual intake and
      proposal review share the supported category list.
- [x] Item detail switches between Owning and Wanting with an icon toggle, and
      editing uses radio choices for the collection (`W2`). Approved by Nico.
      Versioned PATCH, stable retry keys and PWA success messages. Archive is
      a plain detail fact and an edit choice only for archived records.
- [x] Settings shows generation costs per week with catalog-image and
      detection totals (`S6`). Approved by Nico. ISO-week navigation, half-ring
      gauge and two-decimal USD formatting; calendar and display logic tested.

## Character references

- [x] `C5` Settings distinguishes active, pending, failed, and historical
      references.
- [x] `C5` Setup accepts one to four photos of the same person.
- [x] `C5` Each photo is normalized and supports pan and zoom crop.
- [x] `C5` Low crop resolution produces a warning before continuation.
- [x] `C5` The local collage layout matches the baseline for one to four photos.
- [x] `C5` The exact reviewed collage is uploaded as the reference asset.
- [x] `C5` An optional note is persisted with the reference.
- [x] `C5` The new collage becomes the active ready reference.
- [x] `C5` Existing pending and failed server states refresh on foreground return.
- [x] `C5` Detail shows date, source count, creation metadata, note, cost,
      and failure category. Refinement was removed in `11ead56`; there is no
      refinement field, request, or UI in the current contract.
- [x] `C5` A ready historical reference can be activated.
- [x] `C5` A replacement collage can be created from reference detail.
- [x] `C5` An inactive ready or failed reference can be deleted after native
      confirmation.
- [x] `C5` The missing-reference Feed action opens the completed setup flow.

### C5 implementation and validation handoff

Implemented under `apps/mobile/lib/features/settings/character`. All 14
functional C5 items above are covered. The separate visual C5 item remains open:
current PWA/native screenshot pairs have not been captured or compared. The
2026-09-25 capture attempt found a booted simulator, but Computer Use denied
access to Device Hub ("not approved"). This is an explicit remaining Slice 5
completion criterion, not a visual acceptance claim.

- `CharacterSetupCubit` owns photo selection, crop/navigation state, note,
  offline gating and the submission checkpoint. `PhotoPreparation` reuses intake's
  25 MB limit, orientation/HEIC normalization, JPEG 0.92 and 2,400-pixel maximum.
  `PhotoCrop` and `collageLayout` port the PWA geometry, zoom 1–6 and resolution
  warning. Review displays the actual 864×1536 JPEG 0.95 file uploaded verbatim.
- `CharacterDraftRepository` keeps normalized photos and the reviewed file in
  application support, outside the evictable media cache. Scoped draft metadata,
  upload intent, completion key, creation key and accepted record ID survive
  reopening. After submission starts, edits are locked until retry or explicit
  discard. Completion retries probe the existing asset before uploading again.
  A definitely missing, expired upload starts a new asset/completion command.
- `CharacterSheetRepository` maps the current wire contract and persists full
  reference records in Drift v5. Activation updates cached active flags only after
  success. Deletion is the current bodyless DELETE and is idempotent by record ID;
  a retry treats the server's `wardrobe-item-not-found` code as confirmed absence.
  Late list responses cannot undo successful mutations or newer refreshes.
- The shared `CharacterCubit` supplies cached active/pending/failed/history state
  to Settings and detail sheets, refreshes on foreground/reconnection, and polls
  pending references only while active and online. Feed observes repository
  changes. Its former placeholder now opens the complete setup sheet and success
  returns to Feed after requesting a refresh.
- The current contract stores **one** reference asset (the reviewed collage), so
  detail's source count is 1 for new collages, even when composed from four photos.
  This matches the current PWA. Historic records can still have 1–4 asset IDs.
  Creation returns `characterSheetId` and immediately makes the collage ready and
  active without generating another image. No refinement metadata is fabricated.
- Shared FORM reference cards, status badges, portrait previews, crop viewport,
  facts and original person/photo/close SVGs follow PWA tokens, including the
  pending card's dashed border. Native photo picker, sheet transitions and delete
  confirmation follow the Stage 1 native exceptions. German/English copy and
  generated keys include the cost label correction, “Gesamt erzeugt” /
  “Total generated”.
- Validation: `fvm flutter analyze` reports **No issues found!** and
  `fvm flutter test` passes **148 unit tests**. Tests cover geometry, layout pixels,
  exact upload bytes, retry keys, lost responses, expired uploads, interrupted
  connectivity, cached state, eligibility, foreground polling, database reopen,
  the v4→v5 upgrade and Feed reference updates. No widget/golden/integration tests,
  real-server generation, database resets, production access or deployment.

Remaining visual/device review uses synthetic/disposable data: compare Settings
(empty/active/pending/failed), 1–4-photo crops including low resolution, review
and re-crop, history, ready/failed detail, activation/replacement/deletion and
Feed return in both locales. Check native picker permissions and HEIC, swipe
closing, scroll position on history return and the keyboard-visible note field.
Screenshots and their comparison manifest stay outside Git.

## Settings and reset

- [x] `S6` Language can switch between German and English without restart and
      persists across launches (`LanguageCubit`, `preferences_test.dart`).
- [x] `S6` Feed and Wardrobe generation quality defaults persist independently
      (`QualityCubit`, composer/item/intake wiring, `preferences_test.dart`).
- [x] `S6` Weekly cost presentation is done, pulled forward with Nico’s approval.
      Includes total, look count/average, catalog-image and detection costs/counts
      and the PWA half-ring split. Current PWA (`1a1b733`) removes the former
      character-reference slice; the DTO retains historical character costs.
- [x] `S6` Downloaded cache can be cleared without deleting drafts or server data
      (`MediaRepository.clearDownloaded`, `CacheSection`, `media_repository_test.dart`).
- [x] `S6` Private-server and app-version information is visible (`AppInfoSection`,
      `ServerPage`, `AppInfo`).
- [x] `S6` Full reset requires the localized typed phrase while online
      (`ResetSection`, `reset_confirmation_test.dart`).
- [x] `S6` Full reset sends a locale-independent confirmation value (`DELETE EVERYTHING`,
      `personal_repository_test.dart`).
- [x] `S6` The API continues accepting the PWA's existing German confirmation
      (`isPersonalResetConfirmation` in `@form/service`, `personal.test.ts`,
      `personalResetRequestSchema` in `@form/contracts`).
- [x] `S6` Successful reset clears server-owned wardrobe data, matching cached
      account data, draft files, and obsolete look markings while preserving
      app preferences such as language and default image quality
      (`AccountCacheRepository`, `account_cache_test.dart`).

### S6 evidence and validation handoff

Settings composition lives in `settings_page.dart` with `CharacterSection`,
`CostSection`, `QualitySection`, `AppInfoSection`, archive entry, `CacheSection`,
and `ResetSection`. Stage 1 API error codes map through `localizedApiError` and
`apiErrors.*` translations. `fvm flutter analyze` reports no issues; 154 unit
tests pass. Android development debug APK and iOS simulator builds succeed.
Physical-device acceptance remains with Nico.

## Stage closure

- [x] `S6` German and English contain no placeholder or hard-coded UI copy
      (audit; contract version uses a numeric constant only).
- [x] `S6` Every API error code used by Stage 1 has localized production copy
      (`api_error_message.dart`, `apiErrors` in `en.json` / `de.json`).
- [x] `S6` `fvm flutter analyze` passes.
- [x] `S6` `fvm flutter test` passes with unit tests only (154 tests).
- [x] `S6` Android remains buildable as the secondary target
      (`app-development-debug.apk`).
- [x] `S6` The PWA still works against every evolved API contract (additive reset
      confirmation; legacy `ALLES LÖSCHEN` unchanged for the web client).
- [ ] `S6` Nico accepts the complete iOS flow on a physical device (manual;
      steps in `apps/mobile/README.md`).

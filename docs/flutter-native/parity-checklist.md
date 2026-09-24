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

- [ ] `V` One Dart token source mirrors the PWA colors, type scale, serif,
      spacing, radii, and motion curves.
- [ ] `V` The theme removes ripples, elevation, surface tint, and tonal M3
      colors while keeping native transitions, back-swipe, and system pickers.
- [ ] `V` Shared FORM components exist for tab bar, header, buttons, chips,
      search, inputs, image cards, empty and error states, sheets, and dialogs.
- [ ] `V` Shell and foundation access states match the PWA.
- [ ] `V` Wardrobe grid, filters, search, and empty states match the PWA.
- [ ] `V` Item detail, editing, generation, versions, and archive match the PWA.
- [ ] `V` Intake capture, drafts, progress, detection, proposals, and manual path
      match the PWA.
- [ ] `V` `visual-guide.md` documents tokens, components, and the comparison
      routine.
- [ ] `L4` Feed, composer, and look screens match the PWA.
- [ ] `C5` Character-reference setup, crop, collage, and detail match the PWA.
- [ ] `S6` Settings, cost presentation, and reset match the PWA.

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
- [ ] `L4` Details include the item's appearances in ready looks.
- [x] `W2` Cached details and media remain browseable offline.
- [x] `W2` Online editing validates and saves metadata.
- [x] `W2` Online editing moves items between Owning and Wanting.
- [ ] `L4` Inspiration opens the look composer with the item preselected.
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

- [ ] `I3` The Add action opens the intake flow from Wardrobe.
- [ ] `I3` The camera captures one rear-camera photo.
- [ ] `I3` The photo library selects multiple photos.
- [ ] `I3` Inputs enforce the 25 MB baseline limit.
- [ ] `I3` Orientation and HEIC/HEIF normalization produce JPEG quality 0.92 with
      a maximum long edge of 2,400 pixels.
- [ ] `I3` Local previews appear before upload completes.
- [ ] `I3` Photos upload sequentially with per-photo progress and failure state.
- [ ] `I3` Draft metadata and protected local files survive app restarts.
- [ ] `I3` Drafts remain visible offline while upload, analysis, and save actions
      remain disabled.
- [ ] `I3` Detection starts after upload and polls only while the app is active.
- [ ] `I3` Detection boxes align to the normalized 1,000-unit coordinate frame.
- [ ] `I3` Each proposal has a cropped preview and selection state.
- [ ] `I3` Batch Owning or Wanting state can be overridden per proposal.
- [ ] `I3` Selected proposals save idempotently and enqueue their default catalog
      images exactly once.
- [ ] `I3` Failed or empty detection falls back to validated manual metadata.
- [ ] `I3` A draft can be explicitly discarded with its protected files removed.
- [ ] `I3` Server-owned work survives leaving intake and refreshes on foreground
      return without background polling.

## Feed browsing

- [ ] `L4` Cached look cards render immediately and remain browseable offline.
- [ ] `L4` Feed supports empty, planning, generating, ready, failed, stale, and
      offline states.
- [ ] `L4` Feed refreshes at launch, on foreground return, and by pull-to-refresh.
- [ ] `L4` A missing active ready character reference routes toward its setup.
- [ ] `L4` Planning and generating cards show selected garments when available.
- [ ] `L4` Ready cards switch between Worn and Flat views.
- [ ] `L4` Worn view reveals positioned wardrobe pieces and opens item details.
- [ ] `L4` Flat view opens item details from each available garment.
- [ ] `L4` Concept, relative creation date, liked state, and saved state persist
      locally.
- [ ] `L4` Local look markings are disabled while offline.

## Look composition and actions

- [ ] `L4` Composition accepts zero to twelve exact eligible wardrobe items.
- [ ] `L4` Eligible items can be searched and filtered by category.
- [ ] `L4` Selected-only mode and reset behave like the baseline.
- [ ] `L4` Selected garments have a Flat preview and can be removed there.
- [ ] `L4` Surprise, Night Out, Party, and Casual occasions are available.
- [ ] `L4` Wardrobe completion can be enabled or disabled.
- [ ] `L4` Completion can be constrained by selected garment categories.
- [ ] `L4` Look creation submits one idempotent command and opens its feed state.
- [ ] `L4` Failed looks can be retried or deleted.
- [ ] `L4` Ready looks expose details, variation, same-piece recombination, and
      quality upgrade where supported.
- [ ] `L4` Worn and Flat representations share through the native share sheet.
- [ ] `L4` Worn and Flat representations save to Photos after point-of-use
      permission.
- [ ] `L4` Permanent deletion uses a native confirmation and retains historic
      costs on the server.

## Character references

- [ ] `C5` Settings distinguishes active, pending, failed, and historical
      references.
- [ ] `C5` Setup accepts one to four photos of the same person.
- [ ] `C5` Each photo is normalized and supports pan and zoom crop.
- [ ] `C5` Low crop resolution produces a warning before continuation.
- [ ] `C5` The local collage layout matches the baseline for one to four photos.
- [ ] `C5` The exact reviewed collage is uploaded as the reference asset.
- [ ] `C5` An optional note is persisted with the reference.
- [ ] `C5` The new collage becomes the active ready reference.
- [ ] `C5` Existing pending and failed server states refresh on foreground return.
- [ ] `C5` Detail shows date, source count, creation metadata, note, refinement
      metadata when present, cost, and failure category.
- [ ] `C5` A ready historical reference can be activated.
- [ ] `C5` A replacement collage can be created from reference detail.
- [ ] `C5` An inactive ready or failed reference can be deleted after native
      confirmation.
- [ ] `C5` The missing-reference Feed action opens the completed setup flow.

## Settings and reset

- [ ] `S6` Language can switch between German and English without restart and
      persists across launches.
- [ ] `S6` Feed and Wardrobe generation quality defaults persist independently.
- [ ] `S6` Cost presentation includes total look cost, successful look count,
      average successful-look cost, character-reference cost, and visual split.
- [ ] `S6` Downloaded cache can be cleared without deleting drafts or server data.
- [ ] `S6` Private-server and app-version information is visible.
- [ ] `S6` Full reset requires the localized typed phrase while online.
- [ ] `S6` Full reset sends a locale-independent confirmation value.
- [ ] `S6` The API continues accepting the PWA's existing German confirmation.
- [ ] `S6` Successful reset clears server-owned wardrobe data, matching cached
      account data, draft files, and obsolete look markings while preserving
      app preferences such as language and default image quality.

## Stage closure

- [ ] `S6` German and English contain no placeholder or hard-coded UI copy.
- [ ] `S6` Every API error code used by Stage 1 has localized production copy.
- [ ] `S6` `fvm flutter analyze` passes.
- [ ] `S6` `fvm flutter test` passes with unit tests only.
- [ ] `S6` Android remains buildable as the secondary target.
- [ ] `S6` The PWA still works against every evolved API contract.
- [ ] `S6` Nico accepts the complete iOS flow on a physical device.

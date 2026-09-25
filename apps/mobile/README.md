# FORM mobile, slices 1–5

Flutter 3.44.9, iOS 16+, Android 10+. The app includes the native shell, connection gate, language selection, persistent
tab stacks, the wardrobe lifecycle, durable clothing intake, and the cached
inspiration feed with look composition, Worn/Flat views, share, and Photo save.
Slice 5 adds personal photo collages, crop/review, reference history, activation,
replacement and deletion. Its functional checks pass; screenshot acceptance
remains open in `docs/flutter-native/parity-checklist.md`.

## Run here

Open the repository root in VS Code, select an iPhone or simulator, choose
**FORM · Development** in Run and Debug, then press F5. **FORM · Production**
uses the production identifier. Both launch profiles currently have ignored local
configuration targeting the existing private server. Tailscale must be connected.

The app requires the new `GET /v1/meta` endpoint before it opens the shell. A
server without that endpoint shows the incompatibility state. Deployment of this
backward-compatible API addition is separate from building the app.

For another checkout:

```sh
cd apps/mobile
fvm use 3.44.9
fvm flutter pub get
cp .env.example .env.development.json
cp .env.example .env.production.json
# Set FORM_API_BASE_URL in each local JSON file.
fvm flutter run --flavor development --dart-define-from-file=.env.development.json
```

For physical iOS devices, copy `ios/Flutter/Signing.example.xcconfig` to
`ios/Flutter/Signing.local.xcconfig` and enter the Apple development team. This
machine already has that ignored signing file. The flavor determines the bundle
identifier and environment. Production requires HTTPS. Development permits a
local HTTP API. Configuration contains only the API URL, never a password.

## Validate wardrobe on iOS

1. Launch online and open Wardrobe. Check the recency order, Owning/Wanting,
   category and color combinations, localized search, counts, and filter reset.
2. Open an item and let its images load. Edit metadata and collection state.
   Return to the grid and verify the server's result appears.
3. Request a catalog image, select quality, and add improvement feedback when
   an image exists. Refresh to see durable server progress and automatic adoption.
   Leave/reopen the item while processing. Restore an older image afterward.
4. Archive an item. Open Settings → Archive and restore it to Owning or Wanting.
   Confirm deletion only with an item you intend to delete.
5. After synchronization, disconnect the server. Cached grid items, opened
   details, and downloaded media remain available. Mutations are disabled.
   Refresh failure preserves the saved content. Reconnect and refresh to resume.
6. Switch German/English and restart. Check persisted language and the Feed
   cold-start destination. Independent branch stacks survive tab switches.

Nico performs device validation. Automated coverage remains unit tests only.
Checks use in-memory SQLite and synthetic HTTP responses, without wardrobe data
or a running API. No production access is needed.

## Wardrobe implementation

`WardrobeRepository` owns versioned item/detail snapshots and authoritative
commands. `WardrobeCubit` coordinates the shared active/archive collection and
startup/foreground refresh. Item state is route-scoped in `ItemCubit`.
A failed uncertain command retains its key for an explicit retry after a successful
refresh. Generation runs on the server and refreshes every three seconds while work is
running and the app is in the foreground, manually, or on foreground return.
Polling stops when the app leaves the foreground.

Media uses the existing preview endpoint for the grid and signed asset downloads
for full images. The 200 MiB file cache has server-scoped identities, access-time
indexing, LRU eviction, and a protection flag for drafts/active operations.
`MediaRepository.clearDownloaded()` is the primitive for the later Settings UI.
Previously downloaded bytes can be read offline until evicted or cleared.

## Local checks and generation

From the repository root: `npm run verify:mobile`.

```sh
cd apps/mobile
fvm dart run easy_localization:generate -S assets/translations -f keys -o locale_keys.g.dart
fvm dart run build_runner build
fvm flutter analyze
fvm flutter test
```

Commit generated DTOs, Drift code, localization keys, and `pubspec.lock` together
with their sources. Schema version 2 adds server-scoped item/detail snapshots to the foundation
tables. The migration preserves existing preferences, summaries, and protected
media. DTOs are generated with required fields and checked parsing.

Repositories own network and cache access. `CachedRepository` emits cached values
before refreshing and preserves them only on availability failures. Authentication
and contract failures hide cached content. Request outcomes determine connectivity.
The two top-level summaries share `CollectionCountsCubit` for startup and foreground
coordination. Feature-specific state will remain route-scoped in later slices.

The flavor setup follows [Flutter's native flavor configuration](https://docs.flutter.dev/deployment/flavors-ios).
SQLite runs through [Drift's native background database](https://drift.simonbinder.eu/platforms/vm/).

## Scaffold audit

At the start of this work, `apps/mobile` was ignored and contained only abandoned
Expo artifacts, an Expo environment file, and its iOS directory. There was no
Flutter package, Dart source, FVM pin, or Android project to evolve. Those files
were moved intact to a local temporary backup before generating Flutter platforms.
No Expo code was used as a behavior or implementation reference.

The repository specifications arrived under `docs/flutter-native` during the
implementation. The implementation was reconciled with `01-foundation.md`,
including cache primitives, media index, safe Bloc observation, and F1 evidence.

## Clothing intake

Wardrobe → Add opens camera or multi-photo library selection. Native plugin changes
require stopping and rebuilding the app. Hot reload and hot restart cannot link new
photo plugins. A missing plugin now displays a dedicated rebuild message.

Schema v3 adds server-scoped intake records without replacing wardrobe snapshots.
Prepared JPEGs live in application support, outside the downloaded-media LRU cache.
The iOS support directory is excluded from backup and Android backup is disabled.
Each draft is persisted before network work. Completion, detection, item creation,
and catalog generation retain command keys and frozen save payloads on retry.
Expired upload intents are replaced only after completion confirms missing bytes.

The shared intake Bloc serializes commands and survives route changes. It stops
issuing work in the background and polls detection only on the visible intake route.
Discard stops further commands after an in-flight request settles. Existing items
and server jobs remain. Partial saves retain item and generation checkpoints.
Finished drafts are removed after wardrobe refresh succeeds. Startup cleans orphan
files and resumes interrupted local deletion. Automatic images default to Low,
with the persisted `wardrobe-quality` preference reserved for Settings in slice 6.

Manual device checks for Nico:

1. Fully rebuild and launch Development. Select multiple photos, including an
   oriented JPEG and an HEIC. Capture a rear-camera photo on a physical iPhone.
2. Confirm local previews, sequential progress, aligned boxes, cropped proposals,
   batch ownership, individual overrides, and selection before saving.
3. Deny camera permission and follow the Settings recovery. Try an oversized or
   invalid file alongside valid photos and confirm valid drafts remain.
4. Interrupt upload and save, kill/reopen the app, then retry. Confirm saved items
   and image jobs are not duplicated. Leave intake and return during detection.
5. Disconnect networking. Existing drafts remain visible and server actions are
   disabled. Reconnect and retry. Discard a draft and check other drafts remain.
6. Exercise empty/failed detection and validated manual entry. Confirm successful
   saves appear in Wardrobe with automatic catalog generation.

Unit coverage uses synthetic photos, fake API responses, and temporary SQLite.
iOS simulator and Android development builds compile. HEIC decoding, camera,
permission prompts, and end-to-end device behavior still need manual acceptance.
Presentation alignment for slices 1–3 belongs to slice 3.5.

# FORM mobile, slice 1

Flutter 3.44.9, iOS 16+, Android 10+. This slice contains the native shell,
connection gate, language selection, persistent tab stacks, and cached collection
counts. Clothing, images, looks, and editing arrive in the following slices.

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

## Validate this slice

1. Launch online. Feed and Wardrobe show empty or loaded counts from your server.
2. Open **Data status** in each tab and **Private server** in Settings. Switch
   between tabs and verify that each nested page stays open.
3. Change the language in Settings. Restart and verify it persists and opens Feed.
4. After a successful load, disconnect Tailscale and return to the app. Cached
   counts stay visible with a read-only stale indicator. Reconnect and pull to
   refresh. A first launch without cache shows a blocking connection state.
5. Verify that no item creation, edit, deletion, or reset controls exist yet.

No automated widget, integration, golden, or end-to-end tests are included.

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
with their sources. The schema is version 1: preferences, server-scoped collection
summaries, and a media index with immutable asset identity, byte size, access time,
and protection flag. Actual media downloads and eviction belong to slice 2.

Repositories own network and cache access. `CachedRepository` emits cached values
before refreshing and preserves them only on availability failures. Authentication
and contract failures hide cached content. Request outcomes determine connectivity.
The two top-level summaries share `OverviewCubit` for startup and foreground
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

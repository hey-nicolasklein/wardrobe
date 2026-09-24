# FORM native Flutter app: Stage 1 specification

## Objective

Build a native Flutter version of FORM for iOS and Android. Stage 1 reaches
feature parity with the existing PWA while preserving the PWA as a supported
client. The Flutter app becomes the primary mobile client once Nico accepts the
iOS build.

Stage 1 is a private, passwordless app for the existing personal FORM server.
Store distribution, accounts, and monetization are later product stages. Keep
the architecture open to those stages without building dormant UI or services.

## Frozen baseline

The Stage 1 behavior baseline is repository commit
`68b421bc4c047e03bf8f9c3a1d3a5f04fadcb341`.

Use these sources in priority order:

1. `apps/web/public/app.js`, `style.css`, and `index.html` define the parity
   behavior and FORM visual identity.
2. `packages/contracts/src` defines the wire contract. The baseline contract
   version is 5.
3. `apps/api/src/app.ts` and `packages/service/src` define server behavior and
   ownership boundaries.
4. `/Users/nicolasklein/development/wuppertal-stadt-app/wuppertal_stadt_app`
   provides the Flutter conventions for app structure, routing, Bloc, and
   localization.

The removed Expo client and its git history are excluded as references.

Features merged into the PWA after the baseline enter Stage 1 only through an
explicit scope decision. Back-end fixes and required contract changes continue
to apply.

## Product boundaries

- Target iOS and Android only. The PWA owns browser and desktop use.
- Treat iOS as the design and runtime authority for Stage 1.
- Keep Android buildable with platform-safe dependencies. Android-specific QA
  and polish follow the accepted iOS release.
- Support phones in portrait orientation only.
- Minimum versions are iOS 16 and Android 10/API 29.
- Use a light-only FORM theme in Stage 1.
- Preserve FORM's identity, terminology, information architecture, and
  behavior. The Flutter app looks like the PWA running as a native app. See
  "Visual parity".
- Maintain one widget tree and one implementation of each screen. Material is
  the implementation base only. FORM components replace its default visual
  language.
- Support German and English. Follow the device language on first launch,
  fall back to German, and persist an immediate language override in Settings.
- Use `context.tr()` for every user-facing string.
- Accessibility-specific acceptance work is outside Stage 1. Standard Flutter
  controls and their existing semantics are sufficient for this phase.
- Include no analytics, tracking, or remote crash reporting. Logs must exclude
  personal wardrobe metadata, images, request bodies, and credentials.

## Application identity and environments

- Display name: `FORM`
- URL scheme: `form`
- Production application identifier: `de.nicolasklein.form`
- Development application identifier: `de.nicolasklein.form.dev`
- Pin Flutter 3.44.9 with FVM.
- Provide `development` and `production` flavors.
- Development targets a locally configured FORM API.
- Production targets the private stargate API over Tailscale HTTPS.
- Read base URLs from ignored local configuration. Commit safe example files.
- Keep secrets, personal host values, credentials, and media out of Git.

The production server uses `PERSONAL_ACCOUNT_ID`, so Stage 1 has no login or
logout UI. Successful access opens the configured account directly. A missing
session, incompatible server, unavailable server, and empty account are four
distinct app states.

## Technical architecture

Create one Flutter package at `apps/mobile`. Do not create a Dart workspace or
extract packages during Stage 1.

Follow the Wuppertal project's feature-oriented shape at an appropriate FORM
scale:

```text
apps/mobile/
  lib/
    app/
    features/
      feed/
      intake/
      settings/
      wardrobe/
    generated/
    models/
    navigation/
    repository/
    services/
    utils/
    widgets/
```

Use these foundations:

- `go_router` with `StatefulShellRoute` for persistent tab stacks
- `bloc` and `flutter_bloc`
- `easy_localization` with generated localization keys
- Dio behind a small FORM API client
- Drift over SQLite for structured cached data and draft metadata
- `json_serializable` for immutable transport DTOs
- `very_good_analysis`

Sort Dart imports alphabetically. Keep generated files out of manual style
work. Prefer explicit data flow and small feature-scoped units.

### State ownership

- Repositories own remote access, cache reads and writes, and DTO-to-domain
  mapping.
- Cubits own simple page and preference state.
- Blocs own workflows that benefit from explicit events or concurrency control,
  especially intake and server-owned generation jobs.
- Route-scoped providers own feature state unless multiple top-level
  destinations genuinely share it.
- Widgets render state and dispatch intent. They do not contain business rules
  or direct Dio and Drift access.

### API contract

- Keep Zod schemas as the server source of truth.
- Keep Dart transport DTOs separate from cached domain models when their needs
  differ.
- Check the API contract version at startup and present a dedicated
  incompatibility screen.
- Translate stable API error codes in Flutter. Use server messages only as a
  development fallback.
- Attach field errors to their form fields where possible.
- Generate a fresh idempotency key once per logical command and reuse it for a
  retry of that command.
- API and contract changes are allowed when the native client exposes a genuine
  gap. Keep them backward-compatible with the PWA and place business rules in
  the service layer.

### Local data and offline behavior

Offline mode is read-only:

- Render cached wardrobe items, item details, feed entries, and cached media.
- Treat wardrobe and feed content as read-only. Disable server mutations and
  local look markings while offline.
- Do not build an edit outbox, optimistic offline writes, conflict resolution,
  or background synchronization.
- Persist unfinished intake drafts locally across restarts. They cannot upload,
  analyze, or save while offline.

Use stale-while-refresh behavior while online:

- Render cached Wardrobe and Feed content immediately.
- Refresh both in the background at launch.
- Refresh the active destination when the app returns to the foreground.
- Provide pull-to-refresh on Feed and Wardrobe.
- Update the cache after every successful mutation.
- Preserve cached content after refresh failures and show a non-blocking stale
  or offline indicator.
- Show a blocking connection state only when no relevant cache exists.

Media policy:

- Prefetch wardrobe grid thumbnails and feed previews after synchronization.
- Fetch full source photos and generated assets when opened.
- Store bytes as managed files and references as Drift records.
- Use a size-bounded least-recently-used cache for derived media.
- Protect draft files and files referenced by active operations from eviction.
- Add a Settings action that clears downloaded cache without touching server
  data or unfinished drafts.
- Rely on the application sandbox and native device data protection. Exclude
  cached personal data from cloud backup where practical. Stage 1 adds no
  application-level encryption.

## Navigation

Use three bottom destinations with independent stacks:

1. Feed
2. Wardrobe
3. Settings

Wardrobe owns its prominent Add action. Push item and reference details onto
the relevant stack. Present short creation, editing, selection, and destructive
flows as native-feeling modal sheets or dialogs.

Use stable semantic paths and record identifiers. Universal links and Android
app links are outside Stage 1. Preserve each tab stack while the process runs.
After a cold start, open Feed and never restore a modal or destructive flow.

## Parity requirements

[`parity-checklist.md`](parity-checklist.md) is the single source of truth for
feature parity. Every checkbox must be resolved before Stage 1 acceptance.
Slice documents own implementation order and completion criteria.

## Visual parity

The PWA is the visual reference. Each Flutter screen matches its PWA
counterpart at phone width in color, typography, spacing, radii, iconography,
component shape, and motion. Build screens from the shared FORM components and
tokens described in [`visual-guide.md`](visual-guide.md).

Keep native behavior where the operating system owns the interaction: page
transitions, back-swipe, scroll physics, keyboards, system pickers, permission
prompts, and the share sheet. Record any other deviation from the PWA look as
an intended deviation in the parity checklist.

Slice 3.5 builds the design system and restyles Slices 1 to 3. From Slice 4 on,
every slice styles its own screens to PWA parity before it counts as complete.

## Destructive actions

- Use a standard native confirmation for deleting one item, look, or inactive
  character reference.
- Use a localized typed phrase for clearing the full wardrobe.
- Require connectivity for every destructive action.
- Refresh affected repositories and caches only after server success.

## Verification

Automated coverage is limited to unit tests. Do not add widget tests,
integration tests, golden tests, or Flutter-driven end-to-end tests in Stage 1.

Unit-test the logic whose failure could corrupt state or misrepresent server
data:

- DTO parsing and serialization with representative contract fixtures
- API error mapping and contract-version handling
- repository cache behavior and stale refresh behavior
- media-cache indexing and protected-file eviction rules
- search, category filtering, color-family filtering, and sorting
- intake state transitions, idempotency-key reuse, and resumable draft state
- generation and look polling state transitions
- localized preference persistence
- each non-trivial Bloc and Cubit transition

Provide a local mobile verification command that runs:

```sh
fvm flutter analyze
fvm flutter test
```

Visual parity is checked with PWA and Flutter screenshot pairs at the same
phone width, following [`visual-guide.md`](visual-guide.md). Screenshots stay
out of Git.

Nico performs manual iOS verification. Keep Android compile-compatible during
Stage 1, then run the Android-specific QA and polish phase after iOS acceptance.
Hosted CI and automated native builds are outside Stage 1.

## Delivery sequence

Execute these slices in order. Each file is the task brief for one bounded
implementation pass:

1. [`01-foundation.md`](01-foundation.md)
2. [`02-wardrobe.md`](02-wardrobe.md)
3. [`03-intake.md`](03-intake.md)
4. [`03.5-visual-alignment.md`](03.5-visual-alignment.md)
5. [`04-feed-and-looks.md`](04-feed-and-looks.md)
6. [`05-character-references.md`](05-character-references.md)
7. [`06-settings-and-parity.md`](06-settings-and-parity.md)

Finish the active slice's completion criteria and update the shared parity
checklist before starting the next slice.

## Stage 1 exclusions

- Flutter web and desktop
- App Store, TestFlight, and Play Store delivery
- Public backend exposure
- Account onboarding, login, logout, recovery, and multi-account UI
- Monetization, subscriptions, and purchases
- Push notifications and background polling
- Offline mutations and edit synchronization
- Universal links and Android app links
- Dark mode
- Tablet-specific and landscape layouts
- Analytics and remote crash reporting
- Application-level database or media encryption
- Dedicated accessibility acceptance work
- Widget, integration, golden, and end-to-end tests
- Hosted CI

## Final acceptance

Stage 1 is ready for acceptance when:

1. Every frozen PWA capability in the parity checklist exists in Flutter.
2. Every screen matches its PWA counterpart visually or carries a recorded
   intended deviation.
3. German and English are complete and all UI copy uses `context.tr()`.
4. Online mutations are idempotent and cached offline views are read-only.
5. The PWA still works against any evolved API contracts.
6. Flutter analysis and unit tests pass.
7. Android remains buildable as the secondary target.
8. Nico accepts the complete iOS flow on a physical device.

# FORM visual guide

The phone PWA (`apps/web/public/style.css` and `app.js`) is the reference for
native presentation. Business state, repositories and commands do not belong in
this design layer.

## Tokens

`apps/mobile/lib/app/form_tokens.dart` owns the palette, typography, spacing,
radii, category and occasion tints, and motion constants. `form_theme.dart`
applies them to Flutter controls without Material ripples, elevated surfaces or
seed-generated tonal colors. Native page transitions and scrolling remain.

| Token | PWA source |
| --- | --- |
| `paper`, `ink`, `green`, `muted`, `line`, `chrome` | `:root`, `body` |
| `surface`, `field`, `dangerTint`, `uploadTint` | inputs, `.secondary`, `.danger`, `.upload-area` |
| `display`, `heading`, `body`, `small`, `eyebrow`, `wordmark` | `h1`, `h2`, `.muted`, `.note`, `.eyebrow`, `.wordmark` |
| `numerals` | tabular number presentation |
| `gutter` (22), input (12), card (14), panel (18), sheet (25) radii | `.shell`, inputs, `.photo`, `.panel`, `dialog` |
| `pop`, `easeOut`, `sheetCurve`, `sheetDuration` | `--pop`, `--ease-out`, `dialog` transition |
| `category`, `colorSwatches`, `occasions` | `.category-*`, `wardrobeColors`, `.composer-presets` |

UI text uses the platform sans serif. Display text bundles Libre Baskerville
under the SIL Open Font License in `assets/fonts/OFL.txt`. This is a documented
cross-platform substitute for the PWA's platform-dependent `ui-serif` / Georgia.
It is not a claim of identical glyph metrics. Keep the bundled font offline.

## Components

Shared widgets are in `lib/widgets/form_components.dart`. The theme supplies
standard button, text-input, chip, progress, card and native-dialog styling.
Use the existing component before adding another wrapper.

| Flutter | PWA selector / behavior |
| --- | --- |
| `FormPageHeader` | `.masthead`, `.wordmark`, page headings |
| `FormTabBar`, `FormIcon` | `.nav`; original feed, closet, settings SVG paths from `app.js` |
| `FilledButton`, `OutlinedButton`, `TextButton` | `.primary`, `.secondary`, `.text-button` |
| `FilterChip`, `FormChoiceChips` | `.chip`, `.wardrobe-status` |
| `FormSearchField`, themed `TextFormField` | `.search`, `input`, `textarea` |
| `FormImageCard` | `.photo` (3:4), `.detail-photo` (square) |
| `FormEmptyState`, `FormNotice` | `.empty`, `.note`, `.offline` |
| `FormPanel` | `.panel` |
| `showFormSheet`, `FormSheet` | `dialog`, `.sheet-head`, `.sheet-body`, `.sheet-grip` |
| `FormSheetPage` in `app_router.dart` | Routable item detail over the current tab; drag handle, swipe dismissal, close |
| `showAdaptiveDialog`, `AlertDialog.adaptive` | Native destructive confirmation required by Stage 1 |

Sheet content must remain scrollable with the keyboard visible. Detail routes
use the root navigator so the scrim covers the tab bar. Keep item identifiers in
the route and preserve the underlying wardrobe or archive stack on dismissal.
Icon-only actions need a localized tooltip or semantic label. Custom controls
must expose selected/toggled and disabled states. Display category and color
names remain localized; do not derive labels by slicing unrelated translations.

## Comparison routine

1. Build the development iOS app with FVM and an explicitly chosen environment.
   Use the simulator, leaving the physical device and production deployment alone.
2. Capture the reference PWA at the simulator's logical phone width. The iPhone
   16 Pro used here is 402 logical pixels wide (1206 screenshot pixels at 3x).
   Compare content after accounting for iOS status and home-indicator safe areas.
3. Match locale, selected collection, category/color filters, query, item and
   scroll position. Use existing data read-only. Opening sheets is fine; do not
   upload, generate, save, restore, archive, delete or reset live data for pictures.
4. Capture wardrobe, expanded filters, search/empty results, detail, editing,
   generation options, version strip, archive, intake entry and existing drafts,
   Settings, and foundation/access states. Use synthetic/disposable data for
   unavailable transient states, with the required authorization for any reset.
5. Keep screenshots and a manifest outside Git. Record viewport, build, state,
   source, filename and concrete differences. A screenshot of an old binary or a
   system prompt does not count as evidence for the current screen.
6. Compare composition, type, spacing, colors, icon paths, image fit and corners.
   Check sheet swipe dismissal and keyboard scrolling in the native app. Fix
   differences or document them below; screenshot existence alone is not a pass.
7. Run `fvm flutter analyze` and `fvm flutter test`. Existing unit tests remain
   unchanged. No golden, widget or automated UI tests are introduced.

## Capture status (2026-09-25)

Task A (checklist verification) complete: V intake visual item unchecked (lacks
screenshot pairs). Task B (PWA vs Flutter screenshot pairs) blocked: Docker
daemon unavailable (Postgres/object-storage services needed), backend API
unavailable (looks data required), PWA dev server unavailable (402 px
reference capture). Flutter build prepared on iOS simulator (iPhone 16 Pro Fresh,
booted) but cannot run without backend connection. No screenshot pairs captured.
Recommend: defer to local development environment where infrastructure can be
provisioned.

## Explicit deviations and acceptance

- Native safe areas, keyboard, system pickers, scrolling, route transitions and
  destructive dialogs follow iOS/Android, as required by Stage 1.
- Libre Baskerville replaces the platform-dependent web display serif.
- Flutter bottom sheets use native drag/settling physics with the PWA's duration
  and corner styling. Token curves remain available for later in-content motion.
- Feed is the existing foundation placeholder. Full Feed and later Settings and
  character workflows belong to slices 4–6.
- Intake's upload panel uses a solid border in place of the CSS dashed border.
- Native archive restoration keeps both existing Owning and Wanting targets.

Visual acceptance is tracked in `parity-checklist.md`. Do not check a screen's
visual item until its current screenshots have been compared. Unavailable live
states and Nico's physical-device review remain explicit acceptance work.

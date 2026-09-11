# FORM verification map

This directory is the maintained source for verifying the user-facing behavior of FORM,
the private mobile-web wardrobe PWA (`apps/web`). Read this index before driving the app,
then use the matching feature file as the recipe. The parent `SKILL.md` covers launch,
doctor, the drive harness, and cleanup.

## Baseline preconditions

- Launch the fixture server on `http://127.0.0.1:18444` per `SKILL.md` → Launch. It
  re-seeds disposable fixtures on every boot, so each launch is a clean, known state.
- Run `bash ../helpers/doctor.sh` and require `DOCTOR OK` before driving anything.
- Drive the browser as an emulated **iPhone 13** with `/usr/bin/chromium` via
  `PLAYWRIGHT_CHROMIUM_EXECUTABLE`, running node from the repo root.
- Never drive an instance this run did not start, and never run any of this against the
  personal deployment (`PERSONAL_ACCOUNT_ID` / real Tailscale host).

## Seeded fixtures (what you start with)

- `owning`: **Navy overshirt** (jacket, ready), **Black trousers** (pants).
- `wanting`: **Canvas tote** (bag, needs-review) — has seeded shelf-image versions for review.
- `archived`: **Red scarf** (scarf).

## Driving conventions

- Start every recipe from the baseline unless its preconditions say otherwise.
- Prefer ARIA roles and accessible names (the UI is **German**) over CSS position/coordinates.
  Stable handles are listed in `SKILL.md` → Drive.
- Read-only smokes go through `../helpers/drive.mjs`. Mutating flows go through the repo's
  `apps/web/e2e/mobile.test.mjs` (lifecycle) and `apps/web/e2e/review.test.mjs` (catalog images).
- Verify side effects via the API (`GET /v1/wardrobe-items?collection=<owning|wanting|archived>`),
  not only the DOM.

## Proof and skip reporting

- Capture the user action and the resulting state, plus a self-identifying screenshot
  (FORM masthead / `NUR FÜR DICH` visible) and the ARIA snapshot.
- Mutation proof includes a read-only second view (API re-read) of the changed record.
- Record the feature ID and the entry point used. Report an unreachable path with the
  attempted command and the unmet precondition. Do not report a skipped entry point as
  verified through a different path.

## Features

- [Browse & search wardrobe](./browse-search.md) — collections, category filter, live search.
- [Photo intake & save](./photo-intake.md) — upload, automatic detection, selection, import, and fallback.
- [Item lifecycle](./item-lifecycle.md) — edit, archive, restore, permanent delete.
- [Catalog image review](./catalog-image-review.md) — keep/use-original/restore versions; paid-generation confirm.
- [Reset wardrobe](./reset-wardrobe.md) — typed-confirmation destructive clear, with active-job guard.

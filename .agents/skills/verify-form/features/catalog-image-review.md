# Catalog image review

Each piece can have generated "catalog" shelf images. From an item's detail you can keep
a pending draft, switch back to the original photo, restore an older saved version, and
view the source photo. Generation itself is a paid OpenAI call gated behind an explicit
confirmation — verification stops at that confirmation.

## Sub-features

- `keep-version`: accept a pending catalog image draft (`Bild verwenden`).
- `use-original`: `Originalfoto im Schrank verwenden` reverts the shelf image to the photo.
- `restore-version`: pick an older saved version (`Dieses Bild verwenden`) to make it current.
- `view-source`: `Originalfoto ansehen` / `Zurück zum Stück` inspects the source photo.
- `generation-confirm`: `Katalogbild erstellen …` → paid-request confirmation showing the cost estimate.

## How to get to it (user POV)

- Open an item that has catalog versions (the seeded **Canvas tote** in `Wunschliste` does).
- In its detail dialog, use the `Gespeicherte Bilder` versions and the
  `Originalfoto im Schrank verwenden` / `Originalfoto ansehen` buttons.
- `Katalogbild erstellen …` opens the paid-generation confirmation.

## Driving it with review.test.mjs / Playwright

Preconditions: doctor OK. Use the shipped driver — it exercises this exact path against
the seeded item and **stops before any provider call**:

- `PLAYWRIGHT_CHROMIUM_EXECUTABLE=/usr/bin/chromium node apps/web/e2e/review.test.mjs`
  → opens `#wanting` → Canvas tote → keeps the pending image, uses original, restores a
  version, views source, opens `Katalogbild erstellen …`, asserts the cost line
  `1,1–1,9 US-Cent` is visible, then clicks `Bei meinem Foto bleiben` to decline.
  Prints `PASS: keep catalog image, use original, restore version, view source, generation confirmation`.

Proof: the driver's assertions are the proof (current-version toggles, cost text visible).
For a durable artifact, add `page.screenshot({ path: '/tmp/form-verify/catalog-confirm.png' })`
at the confirmation step. Read-side check: `GET /v1/wardrobe-items/<id>` shows the changed
`currentShelfImageVersionId` after keep/restore/use-original.

## Gotchas

- **Do not** click `Ein kostenpflichtiges Bild anfordern` / `Katalogbild erstellen` to
  completion — that enqueues a real OpenAI GPT Image generation. Verify only up to the
  confirmation dialog and then decline (`Bei meinem Foto bleiben`).
- Cost lines on *old* ledgers are labelled invalid (historic misconfigured rates); the
  trustworthy estimate is the one on a new draft's confirmation. Assert the confirmation
  text, not historical totals.
- Version buttons for the current image are `disabled` (labelled `Aktuelles Bild`); a
  switchable version is labelled `Dieses Bild verwenden`.

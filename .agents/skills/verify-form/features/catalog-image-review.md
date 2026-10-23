# Catalog image review

Each new catalog image is applied automatically. From an item's detail, the person can
restore an older generated version and view the source photo. Manual generation remains
a paid OpenAI call gated behind an explicit confirmation.

## Sub-features

- `restore-version`: pick an older saved version (`Dieses Bild verwenden`) to make it current.
- `view-source`: `Originalfoto ansehen` / `Zurück zum Stück` inspects the source photo.
- `generation-confirm`: `Katalogbild erstellen …` → paid-request confirmation showing the cost estimate.

## How to get to it (user POV)

- Open an item that has catalog versions (the seeded **Navy overshirt** does).
- In its detail dialog, use the `Katalogbilder` row or `Originalfoto ansehen`.
- The last tile in that row (`Katalogbild erstellen …`) opens the paid-generation confirmation.

## Driving it with review.test.mjs / Playwright

Preconditions: doctor OK. Use the shipped driver — it exercises this exact path against
the seeded item and **stops before any provider call**:

- `PLAYWRIGHT_CHROMIUM_EXECUTABLE=/usr/bin/chromium node apps/web/e2e/review.test.mjs`
  → verifies that draft-review controls are absent, restores an older version, views the
  source, checks the generation cost confirmation, and clicks `Abbrechen`.

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

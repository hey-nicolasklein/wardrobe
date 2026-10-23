# Reset wardrobe

The destructive "start over" action in Settings: it permanently clears the entire shared
private wardrobe — items, photos, and image history — across all devices, behind a typed
confirmation. Active uploads or image jobs block it.

## Sub-features

- `reset-dialog`: `Kleiderschrank leeren …` opens a confirmation asking you to type a phrase.
- `reset-confirm`: typing `ALLES LÖSCHEN` and submitting clears the wardrobe.
- `reset-guard`: an in-flight upload or generation job blocks the reset (active-job protection).

## How to get to it (user POV)

- Tap `Einstellungen` in the bottom nav.
- Under `Noch einmal von vorn`, tap `Kleiderschrank leeren …`.
- Type `ALLES LÖSCHEN` into the confirmation field, then `Alles endgültig löschen`.

## Driving it with Playwright / API

Preconditions: doctor OK. This wipes fixture data — acceptable because the next
`serve.mjs` boot re-seeds; **never** run it against the personal deployment.

- UI path: `Einstellungen` → `page.getByRole('button', { name: 'Kleiderschrank leeren …' }).click()`
  → `page.locator('#reset-form').getByRole('textbox').fill('ALLES LÖSCHEN')`
  → `page.getByRole('button', { name: 'Alles endgültig löschen' }).click()`.
- Proof: the closet grid is empty afterward (`.item` count 0) and
  `GET /v1/wardrobe-items?collection=owning` returns an empty list.
- The underlying endpoint is `POST /v1/personal/reset` with body `{"confirmation":"ALLES LÖSCHEN"}`.
  Prefer driving the real UI for the proof; use the endpoint only for a read-side/side-effect check.

## Gotchas

- The confirmation phrase is exact and case-sensitive: `ALLES LÖSCHEN`. A wrong phrase is rejected.
- Reset is blocked while an upload or image job is active — if you just ran an intake or a
  generation, that guard may (correctly) refuse the reset; wait for jobs to settle.
- After a real reset the seeded fixtures are gone until the fixture server is restarted;
  restart `serve.mjs` to get a clean seeded state back for the next recipe.
- Run this feature **last** in a session — it removes the fixtures other recipes rely on.

# Item lifecycle

Open a saved piece and act on it: edit its metadata, move it to the archive and back,
or delete it permanently. All server-side, no AI.

## Sub-features

- `edit-metadata`: change Name / Farben / Kategorie / Notizen / collection and save.
- `archive`: move a piece to the archive (`Ins Archiv legen`); it leaves the closet grid.
- `restore`: from the archive (Settings → `Archiv öffnen`), `Zurück in den Schrank`.
- `delete`: `Stück endgültig löschen …` with a second explicit confirm; irreversible.

## How to get to it (user POV)

- Tap any item card in the closet/wishlist/archive to open its detail dialog.
- Edit fields, then `Änderungen speichern`.
- `Ins Archiv legen` archives; open the archive via `Einstellungen` → `Archiv öffnen`.
- `Stück endgültig löschen …` then confirm `Stück endgültig löschen`.

## Driving it with mobile.test.mjs / Playwright

Preconditions: doctor OK. Mutation — the shipped driver covers the whole chain:

- `PLAYWRIGHT_CHROMIUM_EXECUTABLE=/usr/bin/chromium node apps/web/e2e/mobile.test.mjs`
  edits a fixture item's name, saves, archives, restores from Settings, then permanently
  deletes, asserting the grid count drops to 0 and no browser errors occurred.

Targeted custom drive (edit only, on a seeded item):
- Closet → `page.locator('.item').first().click()` opens the `dialog`.
- `page.locator('dialog').getByLabel('Name', { exact: true }).fill('Umbenannt')` then
  `getByRole('button', { name: 'Änderungen speichern' }).click()`.
- Proof: the card `getByRole('button', { name: /Umbenannt/ })` appears; re-read
  `GET /v1/wardrobe-items?collection=owning` shows the new name and a bumped `recordVersion`.

Archive/restore proof: after `Ins Archiv legen`, the item is absent from
`?collection=owning` and present in `?collection=archived`; restore reverses it.

## Gotchas

- Delete is genuinely destructive against the fixture data — fine here because `serve.mjs`
  re-seeds on next boot, but never run delete/restore flows against the personal deployment.
- Archive and delete both need their **second** confirmation; the dialog closes only after
  the confirm, so wait for `page.locator('dialog')` to be hidden/detached before asserting.
- `Änderungen speichern` is the detail dialog's primary button; the intake form's primary
  is `In den Schrank aufnehmen` — don't confuse the two when matching by role.

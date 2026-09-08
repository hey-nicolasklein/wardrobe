# Photo intake & save

Add a piece by uploading one or more photos, naming each, and saving it into the closet.
This is the core write path and makes **no** AI request (detection is optional and separate).

## Sub-features

- `pick-photos`: choose one or several images from the library (or take a camera photo).
- `draft-edit`: each upload becomes a draft with editable Name, Farben, Kategorie, Notizen, and target collection.
- `save-item`: `In den Schrank aufnehmen` persists the draft as a wardrobe item with a real thumbnail.
- `discard-draft`: dismiss a draft without saving; drafts persist in the browser until saved or discarded.

## How to get to it (user POV)

- Tap `Hinzufügen` in the bottom nav (or the round `+` on the closet, or `#add`).
- Tap `Fotos auswählen` (library) or `Foto aufnehmen` (camera) to pick image(s).
- Fill the draft form and tap `In den Schrank aufnehmen`.

## Driving it with mobile.test.mjs / Playwright

Preconditions: doctor OK. This is a mutation — prefer the shipped driver, which covers
intake end to end (upload → save → edit → search → archive → restore → delete):

- `PLAYWRIGHT_CHROMIUM_EXECUTABLE=/usr/bin/chromium node apps/web/e2e/mobile.test.mjs`
  → prints `PASS: mobile import, save, edit, ...`; screenshots in `/tmp/form-pwa-qa`
  (`import.png` shows the filled draft, `detail.png` the saved item "Grünes Testhemd").

Targeted custom drive of just intake:
- Go to `#add`. The file inputs are hidden; set files directly instead of clicking the
  native picker: `page.locator('#library-input').setInputFiles({ name, mimeType: 'image/png', buffer })`.
  Generate a PNG in-process with `sharp` (see `mobile.test.mjs` for the exact SVG→PNG recipe).
- The draft form is `[data-save]`. Fill `getByLabel('Name', { exact: true })` and
  `getByLabel('Farben', { exact: true })` (Farben is required).
- Submit `getByRole('button', { name: 'In den Schrank aufnehmen' })`; wait for `[data-save]`
  to detach, then `Schrank` tab → `getByRole('button', { name: /<your name>/ })` appears.
- Side-effect proof: `curl -s "http://127.0.0.1:18444/v1/wardrobe-items?collection=owning"`
  now includes the new item; its thumbnail asset is downloadable via the item's preview route.

## Gotchas

- `#camera-input` uses `capture="environment"` — there is no real camera in the emulator;
  always drive intake through `#library-input` with `setInputFiles`, never by clicking `Foto aufnehmen`.
- `Farben` is a required field; submit fails silently (native validation) if it is empty.
- Drafts are stored in the browser (localStorage-style), not the server, until saved — a
  fresh browser context starts with none. Uploaded originals do live on the server immediately.
- The `Name und Farben automatisch erkennen …` button on a draft triggers OpenAI detection
  (a worker + provider call). Do not click it in automated verification.

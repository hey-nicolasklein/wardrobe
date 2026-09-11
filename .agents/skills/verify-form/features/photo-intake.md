# Photo intake & save

Add one or more photos, let FORM detect visible pieces, choose them on the image, and
import the selection. Each imported piece immediately queues a catalog image that will
be adopted automatically when the worker finishes.

## Sub-features

- `pick-photos`: choose one or several images from the library (or take a camera photo).
- `automatic-detection`: every completed upload starts detection without another confirmation.
- `piece-selection`: detected garments appear as tappable boxes and as an accessible list.
- `automatic-import`: one action creates the selection and queues low-quality catalog images.
- `manual-fallback`: failed or empty detection exposes one whole-photo metadata form.
- `discard-draft`: dismiss a draft without saving; drafts persist in the browser until saved or discarded.

## How to get to it (user POV)

- Tap `Hinzufügen` in the bottom nav (or the round `+` on the closet, or `#add`).
- Tap `Fotos auswählen` (library) or `Foto aufnehmen` (camera) to pick image(s).
- Toggle pieces on the photo and tap `<n> Stück(e) hinzufügen`.

## Driving it with Playwright

Precondition: doctor OK. The paid workers do not run in the fixture environment. The
shipped driver supplies deterministic detection proposals while keeping upload,
selection, item creation, and generation enqueue on the real local API and database:

- `PLAYWRIGHT_CHROMIUM_EXECUTABLE=/usr/bin/chromium node --env-file=.env.services.local --import tsx apps/web/e2e/add-auto.test.mjs`
  → proves two boxes render, one can be deselected, only the selection is stored, and
  the queued generation has `auto_keep = true`; evidence is in `/tmp/form-auto-add-qa`.

Targeted custom drive of just intake:
- Go to `#add`. The file inputs are hidden; set files directly instead of clicking the
  native picker: `page.locator('#library-input').setInputFiles({ name, mimeType: 'image/png', buffer })`.
  Generate a PNG in-process with `sharp` (see `mobile.test.mjs` for the exact SVG→PNG recipe).
- Wait for the `Stücke erkannt` heading, toggle a named detection button, and submit the
  count-labelled `Stück hinzufügen` button.
- Side-effect proof: `curl -s "http://127.0.0.1:18444/v1/wardrobe-items?collection=owning"`
  now includes the new item; its thumbnail asset is downloadable via the item's preview route.

## Gotchas

- `#camera-input` uses `capture="environment"` — there is no real camera in the emulator;
  always drive intake through `#library-input` with `setInputFiles`, never by clicking `Foto aufnehmen`.
- Manual fallback still requires a name and at least one color.
- Drafts and their idempotency keys are stored in the browser until import or discard.
- The automatic driver replaces only the paid provider result. It does not claim to prove
  OpenAI availability or the worker itself.

# Likeness lab

Run from the repository root:

```sh
node --env-file=apps/worker/.env.local --import tsx tools/likeness-lab/server.mjs
```

Open http://127.0.0.1:4319. This standalone local server reads JPEG, PNG and HEIC files from Downloads. It uses face-only lab prompts from `prompts.mjs` and imports the production provider, and serves the current `preparePhoto` function from the app. It does not connect to the wardrobe database or activate sheets.

Choose up to four solo reference photos, run the face-only prompt, and record likeness errors beside the result. Edit the prompt for a comparison, keeping the references and stable details unchanged. A refinement uses the chosen parent sheet followed by up to three photos, matching the app's reference order. Photo preparation failures appear above the generation button; provider and save failures appear on the run.

Runs make paid requests using the worker's configured API key and base URL. Images, prepared JPEGs, exact prompts, request IDs, token usage and manual reviews are saved under ignored `.prototype-data/likeness-lab/`. Refreshing the page preserves runs. A restart marks interrupted runs as failed rather than retrying them automatically.

This evaluates sheet creation and refinement only. It does not score likeness automatically or test the later feed-image generation step. HEIC support depends on browser decoding, just as in the app.

The gallery rescans Downloads automatically and also has a Refresh Downloads button. JPEG or PNG copies replace matching HEIC entries in the gallery. Use Crop on a photo to drag a rectangle or enter percentage coordinates. Applied crops persist in this browser, leave originals unchanged, and are applied before the production photo preparation. Each run saves its crop coordinates and exact cropped JPEG; Copy run settings restores those crops. Use whole photo followed by Apply crop removes a crop.

## Fit-photo experiments

The default mode generates a single 4:5 outfit photo from real identity photos and selected clothing. It uses the production image provider at medium quality and 1024 × 1280, with an editable lab prompt that explicitly distinguishes identity and clothing references. Select up to four reference images total, including 1–3 clothing items. The first selected identity photo in gallery order is the primary face reference. Cropping remains available.

Copy current non-archived clothing previews from the running local app with:

```sh
node tools/likeness-lab/import-wardrobe.mjs
```

This reads the app at `http://127.0.0.1:4143` and saves previews and metadata under `.prototype-data/likeness-lab/wardrobe/`. Set `LIKENESS_APP_URL` to use another app URL. Restart the lab after importing. The wardrobe import performs only GET requests. Each fit-photo run also saves its own clothing-image copies, selected item metadata, prepared identity photos and exact prompt. Previous face-sheet runs remain available; switch the experiment mode to generate another sheet.

Photo-board mode is now the default for fit photos. Select up to eight real photos; their saved crops and normal photo preparation are applied before deterministic placement in a board with up to three columns and 1000 px square cells. Images are contained, not stretched or cropped again. The top-left photo is primary. Preview photo board shows the same assembly used for generation without calling the image provider. The board is one input, leaving three slots for separate clothing images. Separate-photo mode remains available for comparison. Each board run saves both the prepared source photos and the actual board. Default clothing instructions use image numbers only, without item names, colors or material descriptions. Copied old runs retain their original prompts until Load default prompt is pressed.

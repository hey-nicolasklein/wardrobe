# Outfit builder + flat lays: handoff

User authorized building the full idea. Work paused at their request for rate limits. **Implementation is partial and has not been browser-tested. Do not call it done.**

## Intended experience

- Selecting clothes sends a cutout into a persistent compact tray above “Look erstellen”. Keep search, filters and scroll position.
- Expand the tray into an automatically arranged flat lay. Tap a garment to show its name and remove action; return to browsing without losing state.
- Selection means required starting pieces; FORM can add others. Use “Damit starten wir. FORM ergänzt den Rest.”
- Show the actual planned outfit during image generation, with additions settling into place.
- Saved looks have “Getragen / Gelegt” views. Preserve the existing tap-to-reveal worn-image interaction. Tap flat-lay garments to open details.
- Export/share a PNG outfit card using existing cutouts. Reuse a saved outfit as starting selections.
- Warm neutral background, restrained rotations, category-aware composition, stable positions, reduced-motion support. Automatic layouts first; free dragging and explicit item replacement were deferred.

## Current changes

- `apps/web/public/flat-lay.js` **new**: deterministic layout function, 100 × 125 artboard; category templates, dress variant, grid fallback for duplicate categories / large collections.
- `apps/web/public/app.js`: imports layout; shared flat-lay markup and motion; composer tray, expanded preview and removal; feed view switch; pending/failed outfit previews; canvas export/share; “Mit diesen Stücken kombinieren” menu action.
- `apps/web/public/style.css`: appended styles for the above; feed toolbar and footer now sit outside the image stage.
- `apps/web/public/sw.js`: shell cache v3 includes the new module.
- API already publishes `wardrobeItemIds` during `generating`: worker commits plan and look-item links before generating the image. **No backend/schema changes needed so far.**
- Starting selections are temporarily stored by look ID in `sessionStorage` (`form-look-starts`) until the API has planned items. View preference is an in-memory map. Feed polling now updates cards instead of rebuilding the shell, allowing position transitions.

## Validation and next work

- `npm run verify --workspace=@form/web` passed **before the last small layout edit**. `git diff --check` passed afterward. No browser check, layout tests, or integration test run.
- Add `node --check public/flat-lay.js` to web verification. Test layout bounds, stable ordering, duplicate categories, dress combinations and larger selections.
- Browser-check on iPhone size: tray flights, expand/back/Escape, removal including last item, reset, filter/search persistence, submission from expanded view, queued → generating → ready, view persistence, existing reveal, item detail, missing/deleted images, PNG download, reduced motion and small screens.
- Inspect sparse and unusual layouts: current templates may leave gaps or overlap, especially dresses with extra tops/bottoms. Improve based on screenshots.
- Check expanded preview height: removal panel may sit below the fold. Check garment flight coordinates inside the dialog and clipping.
- CSS `.composer-tray` currently uses undefined `--ink`; replace with an existing/inherited color.
- Review submission error handling: after creation, `refreshInspiration()` failure leaves composer open. Its idempotency key is reused even if selections change. Existing pattern, but new preview flow should not mislead or duplicate jobs.
- Review cleanup of `lookStarts` / `lookViews`; entries currently accumulate. Pending rendering sets flat preference during markup, so cached signature may trigger one unnecessary replacement.
- Missing-image fallback exists on boards/tray. Export deliberately errors if a garment/image is missing instead of silently exporting an incomplete outfit.
- No new test driver written yet. Prefer isolated browser tests with deterministic API responses for client interactions and simulated paid planner states; report these honestly as simulated. Do not mutate personal data for verification.

## Workspace cautions

- There were **pre-existing uncommitted changes** in `app.js` and `style.css`: character-sheet UI/history, `sheetReturn` navigation, generated looks in item galleries, plus existing feed/detail animations. Preserve them; do not reset either file.
- Pre-existing untracked directories: `docs/explorations/`, `docs/wayfinder/feed-reliability/`. They are unrelated to this implementation.
- No commits, deployments, data resets or migrations performed. No background process started by this task.
- Existing dev server was listening on `:8081`; Postgres `:55432` and MinIO `:9100` were running. Fixture server `:18444` was not running.
- Repo instructions: no deployment unless explicitly asked; local `form` DB is real data. The `verify-form` skill was read, but not run. Its fixture server resets/migrates on boot; user instructions require explicit authorization for data resets/migrations, so avoid silently launching it. A standalone client browser harness can avoid database writes entirely.

Resume by reading the diff and this handoff, then finish validation and repair. Do not reimplement from scratch.

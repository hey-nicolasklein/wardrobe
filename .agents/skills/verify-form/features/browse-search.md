# Browse & search wardrobe

Browsing your saved pieces: the closet (`owning`) and wishlist (`wanting`) collections,
each with a category filter and a live text search. No AI, no writes — this is the
default landing view and the safest thing to verify first.

## Sub-features

- `browse-owning`: the closet grid shows every owned piece with its photo, name, category.
- `browse-wanting`: the wishlist grid, reached from the `Wunschliste` nav tab.
- `filter-category`: category chips (`Alle` + only categories present) narrow the grid.
- `search-live`: typing in the search box filters the grid as you type; empty state when no match.

## How to get to it (user POV)

- App opens on the closet (`Schrank`) tab by default; hash route `#owning`.
- Tap `Wunschliste` in the bottom nav (or `#wanting`) for the wishlist.
- Tap a category chip under the search box to filter.
- Type in `Finde dein Lieblingsstück` (the search box) to filter by name/colors.

## Driving it with drive.mjs / Playwright

Preconditions: doctor OK; fixture server on :18444.

- Smoke the closet: run
  `PLAYWRIGHT_CHROMIUM_EXECUTABLE=/usr/bin/chromium node .agents/skills/verify-form/helpers/drive.mjs owning wardrobe`
  → JSON report has `horizontalOverflow:false`, `errors:[]`; `/tmp/form-verify/wardrobe.png`
  shows 2 Stücke ("Navy overshirt", "Black trousers") and the `Alle / Jacken / Hosen` chips.
- Smoke the wishlist: `... drive.mjs wanting wishlist` → screenshot shows "Canvas tote".
- Category filter (custom Playwright): `page.locator('[data-cat="jacket"]').click()` then
  `expect(page.locator('.item')).toHaveCount(1)` (only Navy overshirt remains).
- Live search (custom Playwright): `page.getByRole('searchbox').fill('Navy')` →
  `page.locator('.item')` count is 1; fill `zzz` → count 0 and the empty state renders.
- Side-effect check (read-only): `curl -s "http://127.0.0.1:18444/v1/wardrobe-items?collection=owning"`
  lists the same items shown in the grid.

## Gotchas

- Category chips only render for categories that exist in the current collection, so the
  chip set differs between closet and wishlist — assert against present categories, not a fixed list.
- Search matches name and colors; it is client-side over the loaded collection, so switch
  the collection tab first, then search within it.
- The grid uses `.item` buttons; the card's accessible name includes the item name — match
  by `getByRole('button', { name: /Navy overshirt/ })`, not by grid index.

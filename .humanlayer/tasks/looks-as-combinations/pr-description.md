[Plan: docs/looks-restructure-plan.md](https://github.com/hey-nicolasklein/wardrobe/blob/feat/looks-as-combinations/docs/looks-restructure-plan.md)

## Why the change

Looks used to exist only as paid AI images, so this turns the Looks tab into a collection of free outfit ideas made of the user's own pieces, with worn photos, try-ons and inspiration images as optional layers on top.

## Special things to note

- Migration `029_look_kinds.sql` adds `kind`, `source_photo_id` and `occasion` to `looks` and makes `character_sheet_id` nullable. Existing looks become `inspiration`, or `try-on` when they have a base asset.
- Onboarding no longer asks for the personal collage. It is requested on the first Inspiration instead.
- `npm run dev:seed` gives a local dev account three ready pieces, so the new look flows can be tried right away.

## Still to do

The data model and the free look kinds are done. The Looks tab itself still follows the old structure. These steps from the [plan](https://github.com/hey-nicolasklein/wardrobe/blob/feat/looks-as-combinations/docs/looks-restructure-plan.md) land on this PR before it is ready:

- [ ] Two entry points in the header ("Create look" and a photo button) replace the new-look sheet
- [ ] "Create look" flow: occasion, must-have pieces, swipe deck where tapping a piece marks it keep or drop
- [ ] One card for every look: fixed cover order, piece strip, attachment counters, discovery dot
- [ ] Background photo analysis: own vs. reference photo, outfit box for a clean crop, matches against wardrobe pieces ("Is this your black coat?"), reference pieces go to Wanting
- [ ] Look detail holds the attachments; Try on and Inspiration are only offered there, with their price
- [ ] Update PRODUCT.md to the new Looks structure

## Change outline

A look now has a kind. Only `inspiration` needs a character sheet.

```diff
 looks
+  kind             text  combination | photo | inspiration | try-on
+  source_photo_id  uuid  → source_photos   (photo looks)
+  occasion         text  night-out | party | business | casual
-  character_sheet_id uuid NOT NULL
+  character_sheet_id uuid NULL
```

New endpoints for the free kinds and for putting images on top of them:

```diff
+POST /v1/looks/combinations   { itemIds[1..12], occasion?, idempotencyKey }   free
+POST /v1/looks/photos         { sourcePhotoId, lookId?, idempotencyKey }      free, detects pieces
+PUT  /v1/looks/:id/items      { itemIds[0..12] }
+POST /v1/looks/:id/images     { mode: inspiration | try-on, baseAssetId?, style, quality }   paid
+POST /v1/looks/:id/keep       swipe proposal → combination, free
 POST /v1/looks                (unchanged, AI look)
```

A photo look lists the pieces detection found on its photo, each with a bounding box and the wardrobe piece it was added as:

```text
look.found = latest finished detection on source_photo
  → [{ name, category, colors, boundingBox, wardrobeItemId? }]
```

On mobile, the feed and the new-look actions moved to the new kinds:

```diff
 features/feed/
+├── look_actions.dart     # new-look sheet: combine, photos, suggestions
+├── found_pieces.dart     # detected pieces on a photo look, link or add
 ├── fitting_room_card.dart  # cards for combination, photo, try-on, inspiration
 ├── look_stacks.dart        # stacks by occasion, collection, piece, colour
 ├── look_proposals_*        # swiped proposals are kept as combinations
 └── look_composer_page.dart # saves a combination instead of rendering
 features/intake/
+├── intake_picker.dart    # shared photo picker for pieces and photo looks
 features/wardrobe/
 └── wardrobe_page.dart     # draft tiles with sweep, "new" badge, quick fixes
 features/onboarding/
-└── collage step
```

Checked locally: `npm run verify` for contracts, service and api, `npm run verify:mobile`, and `npm run test:integration`. All green.

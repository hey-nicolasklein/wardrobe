# Looks page restructure (prototype plan)

Status: agreed direction, not built. Target: `apps/mobile` (iOS first). Scope is a
working prototype on the dev wardrobe. Production deploy and TestFlight are separate
requests.

## Why

The Looks tab currently offers five ways to start something (combine, photos,
suggestions, try on, inspiration). It reads as a toolbox, and it leads with AI images
that are hit or miss, drift into the uncanny valley and cost credits every time.

The new Looks tab is a **collection of outfit ideas**. Its primary job is helping the
user put good combinations together from their own wardrobe. Photos and AI images are
attachments on a look, not the reason the page exists. AI should mostly work quietly
in the background (detection, matching, cropping) instead of being the headline.

## Model: one object, the look

```
Look = pieces + occasion                 free, always present
  ├─ Worn         user's own photos (0..n)  free
  ├─ Reference    someone else's photo      free
  ├─ Try on       pieces on user's photo    paid
  └─ Inspiration  AI scene                  paid
```

- A look is always a combination of the user's pieces. This is already true in the
  backend (`lookKindSchema` in `packages/contracts/src/domain.ts`: `combination`,
  `photo`, `try-on`, `inspiration`).
- A photo without confirmed pieces is already a look, just an incomplete one. There is
  no separate "photo" object in the UI.
- A photo of someone else (shop screenshot, street style) becomes a look whose new
  pieces go to **Wanting**. The photo is shown as a reference, not as "Worn".
- Paid actions (Try on, Inspiration) are reachable only from the look detail, each
  with its visible price. Nothing on the feed level spends credits.

## Feed: an idea collection

- Saved swipe proposals land directly in the feed. There is no extra "saved" area.
- "What have I worn before?" is a filter (**Worn**), next to the existing stacks by
  occasion, collection, piece and colour.
- Reference looks (someone else's photo) stay in the feed with a small marker and are
  filterable.

### Card anatomy

Every card has the same frame, so mixed media still reads as one feed.

| Look has | Card cover |
| --- | --- |
| own photo | photo |
| only a try-on | try-on |
| reference photo | cropped reference (see below) |
| nothing else | flat lay |
| inspiration | **never the automatic cover** |

- Below every cover sits the same strip of piece thumbnails. It is the shared element
  that marks a card as a look regardless of what sits above.
- Small counters show what hangs under the look (photos, try-on, inspiration).
- A discovery dot (top right) is the only accent. It lights up when background
  analysis found something the user has not reviewed yet.

### Clean reference covers

Shop screenshots carry prices, names and UI chrome. Detection already returns a
`boundingBox` per piece (`lookFoundPieceSchema`, migration `013_look_item_boxes.sql`).
Extend the analysis to also return one rough **outfit box** (the person or the outfit
as a whole) plus a flag `own | reference`. The card crops to that box on the client.
This is part of detection, so it costs nothing extra.

Open for later: an optional paid cleanup that turns the crop into a clean image. Not
in the prototype.

## Entry points: two, in the header

1. **"Create look"** (primary). Looking forward: "I'm going out tomorrow."
2. **Photo icon** (secondary). Looking back or collecting: "This is what I wore" or
   "Someone wears this."

No floating action button and no multi-option sheet. `showNewLookSheet` in
`apps/mobile/lib/features/feed/look_actions.dart` goes away. The manual composer
(`look_composer_page.dart`) loses its own entry point and becomes the edit mode of a
proposal or a look ("adjust myself").

## Flow A: Create look

1. **Occasion**: chips plus free text. Skippable.
2. **Must-have pieces** (optional): pick from the wardrobe ("these shoes have to be in
   it").
3. **Swipe deck** of proposals, reusing `look_proposals_page.dart`:
   - swipe right saves the combination to the feed
   - swipe left discards it
   - tapping a piece toggles it between *keep* and *drop*. The next proposals respect
     it, so the user steers towards a good look without ever pressing "generate".
   - "adjust myself" opens the composer on the current card.

Everything in this flow is free. Proposals are combinations only (no images).

## Flow B: Add photo

1. Pick one or more photos. They appear in the feed immediately and the user is done.
2. In the background: detection, matching against the wardrobe, own vs. reference
   classification, outfit box.
3. When there is something to review, the discovery dot lights up. Opening the card
   shows:
   - **Matches**: "Is this your black coat?" One tap confirms.
   - **New pieces**: "Add to wardrobe" (own photo) or "Add to Wanting" (reference).
     This hands over to the existing intake, so catalog images and costs behave as
     they do today.
   - Confirmed pieces become the look's combination automatically.
4. The user never watches a loading state for this.

Photo looks with detected pieces already exist (`foundColumn` in
`packages/service/src/inspiration.ts`, `found_pieces.dart`). New is the match against
existing wardrobe pieces: today `wardrobeItemId` is only set for pieces that were
added from this detection.

## Look detail

Top: the combination (flat lay). Below: attachments as a horizontal row. Actions,
each with its price:

- Attach photo: pick from already uploaded photos or add a new one (free)
- Try on (2 credits)
- Inspiration (2 credits)

## Build order for the prototype

1. Header with the two entry points. Remove the new-look sheet.
2. Flow A on top of the existing proposals deck: occasion step, must-have step,
   keep/drop toggles feeding the next proposals.
3. Unified card: cover priority, piece strip, attachment counters.
4. Flow B: background analysis returns `own | reference` and the outfit box, client
   crop, discovery dot, review sheet with "is this yours?" matches.
5. Look detail with attachments and the paid actions moved there.

Steps 1 to 3 are client-heavy and can be checked by reading the diff and reloading.
Step 4 touches contracts, service and worker: run
`npm run verify --workspace=@form/<pkg>` for each and `npm run test:integration`.

## Open decisions

- How matching decides "same piece" (category + colour + embedding similarity, or a
  model call on the crop vs. catalog images) and the confidence threshold for asking.
- Whether one look can hold several own photos from different days, or each photo
  creates its own look that can be merged.
- Copy for the new terms (Reference) in DE/EN, aligned with PRODUCT.md terminology.
- PRODUCT.md "Operating Context → Looks" needs an update once the prototype holds.

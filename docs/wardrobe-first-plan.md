# Wardrobe-first plan

Direction agreed on 2026-10-07. Product context lives in `apps/mobile/PRODUCT.md`.

FORM is the home for your clothes and looks. The Schrank is the baseline, and it only works when it is clean, which means every piece has its generated catalog image. Looks, Try on and AI inspiration are a bonus on top. The three steps below move the app towards that, in this order. Each one builds on the one before.

## 1. Adding: pick your photos and you're done

Today every photo becomes a draft on the intake page. The user waits for upload and detection, ticks pieces, sets Owning and saves each draft (`intake_page.dart`, `intake_repository.dart`).

- After picking photos, the intake page can close. Upload, detection and catalog images run in the background.
- Detected pieces appear straight in the Schrank as developing tiles (`_GeneratingTile` in `wardrobe_page.dart`).
- Corrections happen where pieces live: tap a tile to rename it, remove a wrongly detected piece with undo.
- The catalog image stays automatic. No review step, the first image is right in almost every case.
- Later: share photos to FORM from Apple Photos. This is also the way in for the planned selfie import.

## 2. Open on the Schrank and make Looks an archive

- Tab order Schrank, Looks, Settings. The app opens on the Schrank instead of `/feed` (`app_router.dart`).
- The Looks tab is your collection of looks, sorted by occasion, Sammlung, piece and color (the existing stacks).
- Creating a look is one action inside it, not the purpose of the tab. Selfie looks will land here later.

## 3. A look is always made of real pieces

Looks come in four levels. The first two always show what you really wore or own:

1. **Photo**: a real photo of you wearing it. Its detected pieces are listed on the look, to link to the Schrank or add to it.
2. **Combination**: your pieces as a flat lay, built locally from catalog images (`flat_lay_widget.dart`). Free and always correct.
3. **Try on (Anprobe)**: your real pieces put 1:1 on a photo of you.
4. **Inspiration**: a full AI look. Quality varies.

- The combination is the base of every look. Try on and Inspiration are images added on top and never replace it. A bad AI image costs only that image, the look stays intact.
- The link between looks and pieces gets more visible: every piece shows "worn in these looks", every look lets you tap its pieces.

## Decisions (built 2026-10-07)

- Detection mistakes: fresh tiles carry a "new" badge. Holding a tile renames it or moves it to the archive, with undo on a toast. The archive keeps the paid catalog image.
- Creating a look is one "New look" sheet in the Looks tab: combine pieces (composer), from your photos, or FORM's suggestions. Swiping right on a suggestion keeps it as a free combination.
- Data model: `looks.kind` is `combination`, `photo`, `inspiration` or `try-on`. Photo looks keep their source photo and list its detections; pieces are linked or added by the user, nothing joins the wardrobe by itself. AI images of a combination are looks with `parent_look_id` pointing at it, shown as its layers. Only inspirations need a character sheet.

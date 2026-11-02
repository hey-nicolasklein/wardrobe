# Intake: photo to catalog piece

The core of FORM. A real photo becomes detected pieces, and every kept piece gets a clean
catalog image. Detection and catalog images need the worker, so this is a **paid** run
(`stack.sh up --paid` or `stack.sh paid`).

## Sub-features

- `Fotos auswählen` (system photo picker, several photos) and `Foto aufnehmen` (camera, not available in the simulator)
- Detection, phases `Foto wird analysiert` and then `Wähle deine Stücke`
- Selecting pieces, `Im Schrank` / `Wunschliste`, and `N Stücke hinzufügen`
- Catalog image generation after saving

## How to get to it (user POV)

`Schrank` → `+` → "Neue Stücke / Alles auf ein Foto." → `Fotos auswählen`.

## Driving it with agent-device

```sh
agent-device press 356 145                         # + in the wardrobe
agent-device snapshot -i && agent-device press @e11 --settle    # Fotos auswählen
# The picker has no refs. Tap a photo, then ✓ (top right), using screenshot coordinates
agent-device press 65 367 && agent-device press 363 100 --settle
agent-device wait text "Wähle deine Stücke" --timeout 120000
agent-device screenshot "$(stack.sh shot detected)"
# Deselect the pieces you do not need, refreshing refs each time (--settle), then:
agent-device press @e15 --settle                   # "1 Stück hinzufügen"
```

The proof has three parts. `stack.sh collect` lists the new piece in `new-items.txt` with status
`ready`. The wardrobe shows it first, with the `Neu` badge, a catalog image, and `Alle` one
higher. `spend.txt` shows one detection and one catalog image per kept piece.

Example run from 2026-11-02: the first photo (cream fleece pullover with brown pants) produced 4
detections, and 1 piece was kept. It cost $0.0012 for detection and $0.0162 for the catalog
image, and was `ready` within about 30 s.

## Gotchas

- In a free run, detection stays at `Foto wird analysiert`. That means there is no worker, not a bug.
- Every kept piece costs one catalog image. Keep only the pieces the proof needs.
- Photo order in the picker follows the push order of `.example-photos/` and is stable per sim.

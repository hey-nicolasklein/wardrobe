# Wardrobe (Schrank)

## Sub-features

- Grid of pieces with catalog images and the tabs `Alle`, `Im Schrank`, `Wunschliste`, each with a count
- Search field "Name, Farbe oder Notiz" and `Filter`
- Piece detail (`/wardrobe/items/:id`)
- `+` opens intake (see [intake.md](intake.md))

## How to get to it (user POV)

`Schrank` tab, the start screen after sign-in.

## Driving it with agent-device

```sh
agent-device snapshot -i     # tabs: "Alle\n23", "Im Schrank\n21", "Wunschliste\n2"; pieces: "Neu\n<name>\n<category>"
agent-device press @e7 --settle            # Im Schrank
agent-device press 356 145                 # the + button, by coordinates
```

The seeded `dev@form.local` has 23 pieces: 21 owned and 2 wished for (Olive Work Jacket,
Nike Air Force 1 Black). The proof is that the counts match and the catalog images render.

## Gotchas

- The `+` button merges with the title into one node, `"Dein Schrank.\nNeue Stücke"`. A ref
  press lands on the title, so tap it by coordinates.

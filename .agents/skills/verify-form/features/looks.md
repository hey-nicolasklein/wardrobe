# Looks

Only the entry point has been driven so far. Complete this file during the first full run.

## Sub-features

- Empty state "Noch keine Looks." with `Look erstellen`
- Create a look: occasion ("Wofür?": Überraschung, Ausgehen, Party, Casual, or free text), then `Weiter` or `Überspringen`
- Composer (`/feed/composer`) and proposals (`/feed/proposals`)
- A saved combination is shown as a flat lay (see `apps/mobile/integration_test/looks_flow_test.dart`)

## How to get to it (user POV)

`Looks` tab → `Look erstellen`.

## Driving it with agent-device

```sh
agent-device press 201 805 --settle      # Looks tab
agent-device snapshot -i                  # "Look erstellen"
agent-device press @e10 --settle          # opens "Look erstellen / Wofür?"
```

Combinations from existing pieces are free. Images of a look cost credits and call OpenAI
(`Credits` badge on the action), so they belong in a paid run.

## Gotchas

- Pieces only show up in looks once they have a catalog image. All seeded pieces have one.

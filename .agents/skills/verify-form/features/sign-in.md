# Sign-in and onboarding

## Sub-features

- Dev sign-in without a password (debug builds only), as `dev@form.local`
- Password sign-in (`Mit Passwort anmelden`), for example with the fixture account `test@example.test` / `test`
- First-run onboarding with skip

## How to get to it (user POV)

A fresh install opens the sign-in screen "Willkommen bei FORM". After sign-in, the onboarding
"Willkommen bei FORM / Deine Garderobe, in Bewegung." follows, then the wardrobe.

## Driving it with agent-device

```sh
agent-device open de.nicolasklein.form.dev --relaunch
agent-device snapshot -i                  # buttons "Ohne Passwort anmelden", "Mit Passwort anmelden"
agent-device press @e5 --settle           # Ohne Passwort anmelden
agent-device snapshot -i                  # "Überspringen", "Zeig mir, wie"
agent-device press @e2 --settle           # Überspringen
```

Proven when the tab bar shows `Schrank`, `Looks` and `Einstellungen` and the wardrobe lists
`Alle 23`.

## Gotchas

- Apple and Google sign-in are disabled in this build (`APPLE_SIGN_IN=false`, no Google client).
- Only `stack.sh app` resets the session, because it reinstalls the app. A relaunch keeps it.

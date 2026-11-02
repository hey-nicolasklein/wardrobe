---
name: verify-form
description: Drive the FORM iOS app in a dedicated "FORM Verify" simulator against a local API on the disposable form_fixtures database, with a realistic seeded wardrobe and real example photos, and capture evidence. Free by default, optionally a real paid end-to-end run with OpenAI. Use when a user path must be proven in the real app, or when asked for an e2e run, including one with API costs.
---

# Verify FORM in the simulator

This is the top rung in the AGENTS.md check table. Use it only for a user path that
`verify:mobile` or `test:integration` cannot cover.

Everything goes through `.agents/skills/verify-form/scripts/stack.sh` (shortened to `stack.sh`
below). Run it from the repo root. The stack is separate from the dev setup:

| | Dev setup | Verification stack |
| --- | --- | --- |
| Database | `form` | `form_fixtures`, reset on every `up` |
| API | `:4143` | `:4144` |
| Simulator | Nico's sims | `FORM Verify`, app reinstalled on every `app` |

The `form` database and Nico's other simulators stay untouched. Never point the stack at them.

## Free or paid

- **Free** (`stack.sh up`) runs without the worker. Uploads work, but detection and catalog
  images stay queued and nothing calls OpenAI.
- **Paid** (`stack.sh up --paid`, or `stack.sh paid` on a running stack) starts the worker with
  the real OpenAI key from `apps/worker/.env.local`. Use it only when the user asked for a real
  or paid e2e run. One photo with one kept piece cost about $0.02 on 2026-11-02 ($0.0012 for
  detection, $0.016 for the catalog image). Keep only the pieces the proof needs, and report
  the spend from `stack.sh collect`.

## Launch

```sh
stack.sh up            # or: up --paid
stack.sh app           # ~2 min: build the debug app against :4144, reinstall it fresh
stack.sh doctor
```

`up` starts the Docker services and resets `form_fixtures` (the fixture accounts
`test@example.test` and `empty@example.test`). It then seeds `dev@form.local` with 23 real
pieces from the onboarding catalog images, plus 2 on the wishlist, and starts the API. It is
ready when it prints `Ready: API on :4144`. `app` creates the `FORM Verify` sim if needed and
pushes the real example photos from `.example-photos/` into its Photos library once. If the
folder is empty, run `scripts/sim-example-photos.sh pull` first (see the `sim-example-photos`
skill). Rebuild with `app` after every mobile code change you want to verify.

## Doctor

`stack.sh doctor` is read-only. It checks that the API process is ours and ready on `:4144`,
that MinIO is reachable, that the database is `form_fixtures` with `dev@form.local` seeded, the
worker state, and that the sim and app exist. Run it first whenever anything looks off.

## Drive

Use `agent-device`. In T3 Code, `device_list` and `device_open` on `FORM Verify` return the
bound command. Then run:

```sh
agent-device open de.nicolasklein.form.dev --relaunch
agent-device snapshot -i          # accessibility tree with @refs and German labels
agent-device press @e5 --settle
agent-device wait text "Wähle deine Stücke" --timeout 120000
```

The app runs in German. A fresh install shows sign-in first. Choose `Ohne Passwort anmelden`
(signs in as `dev@form.local`), then onboarding, then `Überspringen`. The feature map in
`features/` lists the paths with their labels.

## Evidence

Evidence for a run lives in `.verify/evidence/<run-id>/` (git-ignored, contains personal photos).

```sh
agent-device screenshot "$(stack.sh shot detected)"   # timestamped file in the evidence dir
stack.sh collect                                      # logs, new-items.txt, spend.txt
```

A proof needs these things:
- It goes through the real UI path: picker, buttons, tabs. No direct API calls or test endpoints.
- It captures the action and the resulting state, for example the detection screen and then the wardrobe.
- It checks the side effect in the database (`new-items.txt`, with status `ready` for catalog
  images) next to what is visible on screen.
- Paid runs report `spend.txt`.

## Cleanup

```sh
stack.sh down
```

`down` stops only the API and worker processes it recorded and shuts the `FORM Verify` sim down.
Evidence stays. Also run it after a failed attempt. The fixtures database stays as it is until
the next `up`.

## Gotchas

- **MinIO on :9100 unreachable** while `docker compose ps` says it is healthy. Colima lost the
  port forward. Restore it with
  `ssh -F /dev/null -o ControlPath="$HOME/.colima/_lima/colima/ssh.sock" -O forward -L 127.0.0.1:9100:127.0.0.1:9100 -p 53758 127.0.0.1`.
  The SSH port comes from `~/.colima/_lima/colima/ha.stderr.log`.
- **Worker log shows `Catalog job 70000000-… failed … payload is invalid`.** That is the
  deliberately broken fixture job. It fails before any OpenAI call.
- **Refs go stale after a tap.** Pressing several `@refs` in a row without a new snapshot drops
  presses. Use `--settle` on each press, or take a snapshot between presses.
- **Some Flutter buttons merge into one node.** For example, the wardrobe `+` is part of
  `"Dein Schrank. Neue Stücke"`. Tap by coordinates instead. `agent-device screenshot` saves 1x
  points, so its pixel coordinates are tap coordinates. `device_screenshot` returns 3x pixels.
- The iOS photo picker runs in a separate process and has no snapshot refs. Tap photos and the
  ✓ button by coordinates from a screenshot.

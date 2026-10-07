---
name: sim-example-photos
description: Load real outfit photos into an iOS Simulator's Photos library so item extraction can be tried in the FORM mobile app. Use when asked to push, add, or load example/test photos into a simulator, or to refresh the example set from stargate.
---

# Example photos for the simulator

`scripts/sim-example-photos.sh` keeps a set of real outfit photos in the git-ignored
`.example-photos/` directory and pushes them into a simulator's Photos library, where the
app's photo picker finds them.

```sh
scripts/sim-example-photos.sh push "Wardrobe Looks (16 pro)"   # name or UDID
scripts/sim-example-photos.sh pull                             # refresh from stargate
```

## Push

Pick the simulator the user names. If they name none, list the candidates with
`xcrun simctl list devices | grep Booted` and ask. The script boots the device if needed.

Run `pull` first only when `.example-photos/` is empty or the user asks for fresh photos.
Each push adds every photo again, so pushing twice to one simulator duplicates them in Photos.
Say so instead of pushing a second time unprompted.

## Pull

`pull` reaches stargate over SSH (`STARGATE_HOST`, default `stargate`). It reads production
read-only: one Postgres query and an `mc cp` from MinIO through the `minio/mc` image on the
`form-production_default` network. Nothing on stargate changes and nothing is deployed.

It takes only source photos of the owner account (`EXAMPLE_PHOTOS_OWNER`, Nico's email) that
produced at least one detection, and names files by content hash, so duplicates collapse and
repeated pulls only add new photos. Beta testers also upload to production. Never widen the
query to other accounts.

The photos are personal data. Keep them in `.example-photos/` and never commit them.

---
title: Make the wardrobe and Feed reliable for daily use
label: wayfinder:map
status: open
github_issue: https://github.com/hey-nicolasklein/wardrobe/issues/29
---

## Destination

Make FORM refresh current data across devices, complete clothing imports after a browser interruption, keep Look choices clear, make useful Looks easy to find again, and let the wardrobe remain usable when Feed services fail.

## Scope

- Refresh server state when the PWA returns to the foreground.
- Move batch import completion and image queueing into a durable server command.
- Make ownership scope visible and controllable in Look creation.
- Add durable Look favorites and filtering by wardrobe item. Defer occasion input until a later product decision.
- Load wardrobe and inspiration independently at startup.
- Bring documentation and focused client behavior coverage up to date.

## Decisions so far

- Feed generation remains defined by [Build the generated personal outfit Feed](https://github.com/hey-nicolasklein/wardrobe/issues/27).

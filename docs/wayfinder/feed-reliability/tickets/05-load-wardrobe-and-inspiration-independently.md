---
title: Keep the wardrobe available when inspiration loading fails
label: wayfinder:task
status: open
parent: ../map.md
github_issue: https://github.com/hey-nicolasklein/wardrobe/issues/34
---

## What

Load wardrobe data and inspiration data independently during startup. Render the available area when the other request fails, and show an actionable error only in the affected Feed or Settings section. Keep retry scoped to the failed request.

The client currently awaits `refreshItems()` and `refreshInspiration()` in one `Promise.all`. A failed Look or Character Sheet request sends the whole app to the connection-error screen even when the wardrobe request succeeded.

## Why

The wardrobe is the core record of clothing. A fault in the optional inspiration area should not block browsing, editing, or adding wardrobe items.

---
title: Refresh wardrobe and Feed data when the PWA returns to the foreground
label: wayfinder:task
status: open
parent: ../map.md
github_issue: https://github.com/hey-nicolasklein/wardrobe/issues/30
---

## What

Refresh the wardrobe and inspiration data when a visible, online PWA returns to the foreground. Re-render the active section when its data changed, and add a manual refresh action where it fits the current interface.

The current `visibilitychange` handler refreshes only `/version.json`. The ten-second polling loop refreshes API data only while the client already knows that an item, Look, or Character Sheet is active. A second device can therefore change the wardrobe without an open client learning about it.

## Why

FORM is used from more than one device. An open session should show added, changed, or deleted clothing and Looks after the user returns to it. Otherwise the app can look correct while showing old server state.

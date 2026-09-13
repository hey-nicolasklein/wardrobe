---
title: Update web documentation and add focused behavior checks
label: wayfinder:task
status: open
parent: ../map.md
github_issue: https://github.com/hey-nicolasklein/wardrobe/issues/35
---

## What

Update the README and mobile-web documentation to describe the current automatic high-quality catalog-image flow and the implemented Feed. Add focused checks for client behavior that can regress without a syntax error, starting with interrupted imports, foreground refresh, and independent startup failures.

`apps/web` verification currently runs JavaScript syntax checks only. The README still describes optional low-quality generation with manual Keep or Reject decisions, while the client requests high quality with `autoKeep: true`. `docs/mobile-web.md` also predates the Feed work.

## Why

The docs should describe what FORM does today so routine changes start from the right assumptions. Syntax checks cannot prove that the client resumes the right server state after an interruption or handles one failed startup request without hiding a usable wardrobe.

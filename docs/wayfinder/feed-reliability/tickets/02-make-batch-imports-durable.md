---
title: Make clothing batch imports complete after the browser closes
label: wayfinder:task
status: open
parent: ../map.md
github_issue: https://github.com/hey-nicolasklein/wardrobe/issues/31
---

## What

Add a server-owned batch import command that creates all selected detected items and queues their catalog images as durable work. Return one batch status that the client can resume and display after reconnecting.

Today `importDetected` creates each wardrobe item and then queues its image in a client-side loop. It persists draft state between iterations, but closing the browser can still leave a partial batch or a saved item whose image was never queued.

## Why

Saving a reviewed batch should not depend on the browser remaining open. A durable command makes the result recoverable, gives the user one progress state, and removes uncertainty after an interruption.

---
title: Package and protect the NAS deployment
label: wayfinder:task
status: open
assignee:
parent: ../map.md
github_issue: https://github.com/hey-nicolasklein/wardrobe/issues/13
blocked_by:
  - ./03-build-the-durable-service-foundation.md
  - ./06-build-the-gpt-catalog-worker.md
---

## Question

Create the production-shaped Docker Compose deployment, Tailscale-only HTTPS configuration, secret injection, persistent volumes, migrations, worker restart behavior, health checks, and a tested PostgreSQL-plus-media backup and restore procedure for the target NAS.

## Resolution

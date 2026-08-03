---
title: Establish the production workspace and contracts
label: wayfinder:task
status: closed
assignee: hey-nicolasklein
parent: ../map.md
github_issue: https://github.com/hey-nicolasklein/wardrobe/issues/11
blocked_by:
  - ./01-reconcile-the-v1-contract.md
---

## Question

Create the production monorepo boundaries, shared validated API contracts, development commands, environment examples, and verification baseline without importing disposable Vite prototype source into the Expo client.

## Resolution

Established npm workspaces for the Expo client, standalone Hono API, remote-image worker, and shared `@form/contracts` package while retaining the disposable Vite prototype as isolated root-level evidence. The Expo workspace is a clean SDK 57 scaffold and has no source dependency on the prototype.

The shared package now runtime-validates strict wardrobe records, normalized detection proposals, private asset metadata, generation defaults, replay-safe commands, API responses, domain events, and actionable error envelopes from the same Zod schemas that infer TypeScript types. Production app examples document only their owned environment surface, with client-visible configuration limited to `EXPO_PUBLIC_API_URL`.

Root commands install, develop, and verify the monorepo from one lockfile. Verification typechecks every boundary, runs five contract tests, confirms Expo dependency compatibility, exports the Expo web bundle, builds the legacy Vite evidence app, resolves one React 19.2.3 runtime across the monorepo, and smoke-tests API/worker resolution of contract version 1.

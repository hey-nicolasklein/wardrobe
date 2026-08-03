---
title: Ship the persistent personal wardrobe
label: wayfinder:map
status: open
github_issue: https://github.com/hey-nicolasklein/wardrobe/issues/1
---

## Destination

Deliver a working Expo application and NAS-hosted backend that can be used as a real, persistent personal wardrobe: authenticated people add Source Photos, review GPT-detected items, generate and approve clean Shelf Images, and manage Owning and Wanting collections from iPhone and web.

## Notes

- This effort explicitly carries execution through the destination; it does not stop after planning.
- The first usable release is the persistent wardrobe loop. Fitting profiles and generated Looks are a later effort.
- Consult `docs/v1-expo-spec.md`, `docs/gpt-image-garment-catalog-spec.md`, `CONTEXT.md`, the `expo-native-ui`, `expo-router`, `expo-data-fetching`, and `openai-docs` skills while implementing.
- iPhone is the design authority. Expo Web supports the same core flows without forced visual parity.
- Use native Expo SDK 57 navigation and controls, Owning and Wanting bottom tabs, Add in the top toolbar, native image transitions, and fullscreen pinch-to-zoom previews.
- One Source Photo may create several Wardrobe Items. The Source Photo remains private, durable, and visible from each derived item detail page.
- GPT proposes editable name, strict category, and colors. Notes are manual.
- Shelf Images use `gpt-image-2`, Low quality, and 816 × 816 output by default. Every generation is versioned and requires explicit Keep.
- Items persist immediately as drafts and durable jobs survive client, API, worker, and NAS restarts.
- Use lightweight administrator-created accounts with real per-user isolation.
- Host the service stack through Docker Compose on the NAS and expose the application boundary only through Tailscale HTTPS.
- Support cached offline browsing and queued lightweight edits; uploads and AI work require connectivity.
- Use Expo Go for rapid development and a free Xcode Personal Team build for realistic iPhone testing.
- Never commit provider credentials or personal media.

## Decisions so far

- [Reconcile the V1 contract with the usable wardrobe destination](https://github.com/hey-nicolasklein/wardrobe/issues/9) — The accepted specs now make the persistent, recoverable wardrobe loop the first release and defer fitting profiles and Looks.
- [Establish the production workspace and contracts](https://github.com/hey-nicolasklein/wardrobe/issues/11) — Production now has explicit mobile, API, worker, and runtime-validated contract boundaries with one install and verification baseline; the Vite prototype remains isolated evidence.
- [Build the durable service foundation](https://github.com/hey-nicolasklein/wardrobe/issues/12) — PostgreSQL migrations, database-enforced ownership, private versioned object storage, leased durable jobs, dependency health, and deterministic local scenarios now form one tested server boundary.
- [Enforce lightweight accounts and private media](https://github.com/hey-nicolasklein/wardrobe/issues/6) — Administrator-created scrypt credentials, revocable cookie/token sessions, secure native storage, validated signed media flows, and cross-account denial now form one tested authorization boundary.
- [Model the persistent wardrobe and its lifecycle](https://github.com/hey-nicolasklein/wardrobe/issues/2) — Account-scoped items now preserve immutable detection and generation provenance through idempotent edits, reversible collection state, explicit version approval, and source-aware permanent deletion.
- [Build the durable GPT wardrobe-ingestion pipeline](https://github.com/hey-nicolasklein/wardrobe/issues/3) — Leased replayable workers now turn private Source Photos into strict proposals and reviewable Shelf Images with validated chroma removal, immutable usage/cost ledgers, and classified recovery.

## Not yet specified

- Tune the grid's final density, spacing, empty states, haptics, and delight after it contains a representative real wardrobe rather than fixture-only data.
- Refine the offline conflict experience after real queued-edit behavior exposes which conflicts are understandable and which need stronger safeguards.
- Revisit account onboarding and distribution once use expands beyond manually provisioned Tailscale users.

## Out of scope

- Fitting-profile creation and static try-on Looks; these follow the usable wardrobe release as a separate Wayfinder effort.
- Public signup, email delivery, OAuth, password recovery, and public internet exposure.
- Shop URL import, scraping, recommendations, social features, sharing, and push notifications.
- SegFormer, pixel-mask editing, or claims that a Shelf Image is a pixel-exact extraction.
- App Store or TestFlight distribution before an Apple Developer Program membership exists.

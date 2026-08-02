# FORM V1 Expo App — Product and Architecture Specification

Status: agreed V1 direction, reconciled with the persistent-wardrobe destination on 2026-08-02

## Problem Statement

FORM currently exists as a throwaway, mobile-first web prototype. It proves useful interaction and image-generation ideas, but its session-oriented client state, temporary generated files, prototype persistence, and synchronous AI requests are not a suitable foundation for a real personal wardrobe.

The first usable release must let a person build and keep a private wardrobe: add one durable Source Photo, identify one or more Wardrobe Items, review GPT-proposed metadata, generate and approve versioned Shelf Images, and organize each item in Wanting or Owning. The wardrobe must survive app, API, worker, and NAS restarts; remain useful through temporary loss of connectivity; and be recoverable from backups.

Fitting profiles and generated Looks are intentionally deferred until the persistent wardrobe loop has been proven with representative personal data.

## Solution

Build a new Expo application for iPhone and web, with Android supported by the universal codebase. The application does not import source from the disposable Vite prototype; the prototype remains behavioral and visual evidence only.

Owning and Wanting are the two bottom tabs. Add is a top-toolbar action that opens a guided, native multi-item flow. Each Wardrobe Item has a native detail screen with its private Source Photo, editable metadata, lifecycle controls, generation history, and Shelf Image versions. Image transitions use native navigation affordances, and image previews can open fullscreen with pinch-to-zoom.

The Expo client communicates with a standalone Hono API. PostgreSQL is authoritative for accounts, sessions, domain records, generation attempts, costs, and durable jobs. Private S3-compatible object storage holds Source Photos and generated media. A PostgreSQL-backed worker performs detection and Shelf Image generation. The API, worker, PostgreSQL, and object storage run on the NAS through Docker Compose and are reachable only through Tailscale HTTPS.

The server uses GPT vision to propose item names, strict categories, colors, and normalized bounding boxes. After review, it uses the OpenAI Images edit API with `gpt-image-2` to generate a laid-flat Shelf Image. The default request is Low quality at 816 × 816. Provider calls, prompts, chroma processing, cost accounting, and asset writes remain behind narrow server-side module boundaries.

The client supports cached offline browsing and a durable outbox for lightweight edits. Uploads, detection, and image generation require connectivity. Jobs survive client closure and service restarts; completion is discovered through polling and refresh-on-focus rather than push notifications.

## User Stories

1. As a user with an administrator-created account, I want to sign in on iPhone or web and see the same private wardrobe.
2. As a user, I want cached Owning, Wanting, Archive, and item details to remain browsable without connectivity.
3. As a user, I want lightweight metadata and lifecycle edits queued offline and synchronized after reconnecting.
4. As a user, I want private media to require authorization so guessing an asset path cannot reveal it.
5. As a user, I want to add a Source Photo from camera or gallery and see a durable draft immediately.
6. As a user, I want one Source Photo to produce several Wardrobe Items without uploading it repeatedly.
7. As a user, I want GPT to propose a short name, strict category, and colors for each visible item, with me remaining authoritative over every field.
8. As a user, I want unsupported proposals identified before a paid generation starts.
9. As a user, I want Low-quality 816 × 816 Shelf Image generation by default, with one explicit action creating one paid attempt.
10. As a user, I want generation to continue if I navigate away or close the app.
11. As a user, I want every generated Shelf Image presented for review before it becomes current.
12. As a user, I want Keep to preserve an immutable Shelf Image Version and make it current.
13. As a user, I want another attempt to create a new version without overwriting earlier kept versions or their costs.
14. As a user, I want to restore an older kept Shelf Image Version without paying for another generation.
15. As a user, I want the Source Photo visible from every derived item's detail page as durable provenance.
16. As a user, I want Wanting, Owning, and Archive to be reversible states of the same Wardrobe Item.
17. As a user, I want buying a wanted item to preserve its identity, Source Photo, metadata, and Shelf Image history.
18. As an operator, I want accounts created manually without public signup, email delivery, or password-recovery infrastructure.
19. As an operator, I want the stack to restart safely on the NAS and expose only its Tailscale HTTPS boundary.
20. As an operator, I want database, object media, and deployment configuration backed up together and periodically restored in a drill.

## Implementation Decisions

### V1 product boundary

- The release destination is the usable persistent wardrobe loop: authenticate, add Source Photos, review proposed Wardrobe Items, generate and Keep Shelf Images, browse, edit, and move items between Wanting, Owning, and Archive.
- Owning and Wanting are bottom tabs. Archive is reachable from wardrobe controls rather than occupying a primary tab.
- Add is a top-toolbar action, not a third tab.
- One Source Photo may create multiple Wardrobe Items and remains private, durable provenance visible from each derived item detail page.
- Item Metadata consists of an editable short name, strict category, colors, and optional manual notes. GPT proposes name, category, and colors; notes are never inferred.
- A Shelf Image is an AI-generated display reconstruction, not a cutout, extraction, or proof of unseen construction.
- Every generation creates a Shelf Image Version. Keep is explicit, kept versions are immutable and restorable, and a later attempt never overwrites history.
- Fitting-profile creation, generated or photographed Looks, and try-on generation are outside this release and will be planned as a separate Wayfinder effort.

### Client application and native navigation

- Build a clean Expo application with no source-code dependency on the Vite prototype.
- Use Expo Router with native bottom tabs and nested native stacks.
- Use native toolbar items, menus, modal routes, and form sheets for Add, editing, and lifecycle actions rather than custom web-style overlays.
- Use native image transitions from Shelf Image and Source Photo thumbnails into detail views.
- Provide fullscreen, pinch-to-zoom previews for Source Photos and Shelf Images.
- Treat iPhone as the design authority. Expo Web supports the same core flows without forced pixel parity, and Android remains supported by the universal codebase.
- Use native camera/gallery selection and local file URIs; never convert media to base64 request bodies.
- Store native session credentials in secure device storage. Browser sessions use secure HTTP-only cookies.
- Refresh remote state on app focus and network reconnect. Poll active jobs while relevant surfaces are open.

### API and contract boundary

- Keep the Hono API independent from Expo so native, web, worker, and future clients share one server boundary.
- Define request, response, event, and error contracts with runtime validation in a shared package owned by the production workspace.
- Commands replayed by the offline outbox or network retries accept idempotency keys.
- Resolve every record, job, and asset through the authenticated account before returning metadata or media access.
- Use opaque stable IDs and server asset IDs as canonical data; never store expiring signed URLs as canonical values.
- Return typed, user-actionable error categories for validation, offline state, authorization, transient provider failure, moderation, and capacity limits.

### Authentication and tenancy

- Implement real multi-user isolation even though initial use may be by one person.
- Administrators create accounts directly. V1 has no public registration, invitations by email, OAuth, email delivery, or self-service password recovery.
- Use email and password credentials with one server-side session model: HTTP-only cookies on web and opaque tokens on native.
- Include at least two fixture accounts so cross-account record and media denial is continuously testable.
- Scope database queries, object ownership, queued jobs, and fixture resets by account.

### Persistence, NAS deployment, and recovery

- PostgreSQL is the source of truth for accounts, sessions, Wardrobe Items, item states, metadata, Source Photos, Shelf Image Versions, generation attempts and costs, jobs, and test scenarios.
- Use a PostgreSQL-backed durable job queue; do not add Redis in V1.
- Run the Hono API, worker, PostgreSQL, and private S3-compatible object storage through Docker Compose on the NAS with restart policies and persistent volumes.
- Expose the application boundary only through the NAS's Tailscale HTTPS hostname. Do not expose the API, database, or object storage to the public internet.
- Keep local development hot-reloading commands for Expo, API, and worker, backed by disposable local service containers and the same validated contracts.
- Back up PostgreSQL, object-storage data, and the non-secret deployment configuration as one recoverable system. Store credentials separately in the operator's secret store.
- Document backup schedule, retention, target, integrity checks, and restore steps. Prove recovery with a restore drill before calling the release usable.

### Media security and lifecycle

- Keep every object-storage bucket private.
- Upload media through short-lived signed upload URLs issued after authenticated intent and file validation.
- Read media through short-lived signed download URLs issued after ownership checks.
- Validate declared and decoded file type, byte size, and pixel dimensions before accepting an upload.
- Record asset purpose and owner so Source Photos, normalized derivatives, raw keyed outputs, transparent derivatives, and fixtures have explicit lifecycles.
- Retain a Source Photo while any Wardrobe Item depends on it. Permanent deletion requires all derived items to be permanently deleted and must remove or expire every dependent asset according to policy.

### Wardrobe domain

- A Wardrobe Item is one durable entity with a reversible state of `wanting`, `owning`, or `archived`.
- Moving Wanting to Owning or restoring an archived item updates the same record and preserves provenance and version history.
- A Source Photo is uploaded once and may have multiple detection proposals, generation attempts, and derived Wardrobe Items.
- A draft item is visible immediately and moves through detecting, reviewing-metadata, queued, generating, needs-review, and ready statuses without changing identity.
- The wardrobe module owns lifecycle transitions and readiness invariants so screens and workers cannot create illegal states directly.

### Detection and Shelf Image generation

- Follow `gpt-image-garment-catalog-spec.md` as the detailed provider and prompt contract.
- Normalize HEIC and HEIF to orientation-correct quality-92 JPEG before preview or provider input.
- Use GPT vision proposals with normalized bounding boxes, short name, strict category, and colors. The user can edit all proposed metadata before generation.
- Use the reviewed box to prepare a padded target reference. The crop identifies the target but is never represented as an extraction.
- Use the OpenAI Images edit API with `gpt-image-2`, a versioned laid-flat chroma prompt, Low quality by default, and 816 × 816 PNG output.
- Medium and High are explicit alternative attempts, never automatic companion generations.
- Infer and validate the generated chroma key, then derive a transparent Shelf Image for display on a neutral background.
- Persist every attempt with Source Photo and proposal provenance, reviewed metadata, model, quality, size, prompt version, resolved key, raw and transparent assets, request ID, token usage, captured rates, exact cost, state, and failure category.
- Require review. Keep makes a version current; generate again, edit metadata, or use another Source Photo create distinct attempts without overwriting prior versions.
- Do not use SegFormer, semantic masks, connected components, correction strokes, or on-device segmentation.

### Durable jobs and retries

- Use one PostgreSQL-backed remote-image queue with job kinds for detection and Shelf Image generation.
- Claim jobs with database-safe locking and recover abandoned leases after worker or NAS restart.
- Retry one transient connection, timeout, rate-limit, or provider-server failure with bounded backoff.
- Do not automatically retry validation, conversion, moderation, authentication, quota, accounting, or chroma-validation failures.
- Make global and per-account concurrency limits environment-configurable.

### Offline boundary

- Persist a query cache for Owning, Wanting, Archive, item details, Source Photo metadata, Shelf Image history, and job status.
- Queue only lightweight, idempotent edits such as name, category, colors, notes, lifecycle state, and current-version selection.
- Uploads, detection, Shelf Image generation, destructive deletion, account operations, and signed-media renewal require connectivity.
- Show pending edits and blocked online-only actions explicitly. Replay the outbox after reconnecting without duplicating commands.
- Detect stale writes with record versions. Surface a conflict instead of silently overwriting a newer server value.

### Testing and fixtures

- Use unit tests for domain transitions, authorization, provider parsing, cost accounting, chroma validation, idempotency, job recovery, and backup/restore scripts.
- Use integration tests against real PostgreSQL and S3-compatible storage for account isolation, private media, source/version lifecycle, job restart recovery, and offline replay.
- Use replay providers and private-safe recorded fixtures for routine detection and image-generation tests. Paid OpenAI calls are deliberate smoke tests only.
- Use browser automation for fast universal-flow coverage and Maestro for the highest-value native journeys.
- Maintain scenarios for empty, populated, offline, queued, failed, needs-review, multiple-version, and cross-account-denial states.

Primary E2E journeys:

1. Sign in with an administrator-created fixture account and restore its session.
2. Upload one Source Photo, receive several proposals, edit GPT-proposed name, category, and colors, and create multiple durable drafts.
3. Generate a Low-quality 816 × 816 Shelf Image, navigate away, and recover the result after worker and app restart.
4. Keep one version, generate another, and restore the earlier kept version without losing either attempt or cost ledger.
5. Open an item detail page, inspect its Source Photo, and use fullscreen pinch-to-zoom for source and shelf media.
6. Move one item Wanting → Owning → Archive → Owning without changing its identity or history.
7. Browse cached data offline, queue an allowed metadata edit, reconnect, and observe exactly one synchronized command.
8. Verify uploads and generation are blocked clearly while offline.
9. Attempt cross-account record and media access and receive no private data.
10. Restore PostgreSQL, object media, and deployment configuration into a clean stack and verify representative wardrobe records and assets.

## Out of Scope

- Fitting profiles, generated try-on Looks, photographed Looks, and Look history.
- Public registration, invitation email, email verification, external OAuth, and self-service password recovery.
- App Store or TestFlight distribution before an Apple Developer Program membership exists.
- Public internet exposure, public sharing, social features, or collaborative wardrobes.
- Shop URL import, scraping, recommendations, and inferred brand or material.
- SegFormer, pixel masks, mask editing, or claims that a Shelf Image is a pixel-exact extraction.
- Push notifications, general-purpose realtime sockets, and a desktop-specific authenticated interface.
- Automatic generation of multiple quality levels or 2K/4K Shelf Images.

## Further Notes

- The NAS deployment is the first production environment, not a temporary local phase. Public ingress and elastic capacity remain later operational changes.
- Browser and native clients use the same API, accounts, database, and object storage.
- The accepted Shelf Image direction is detailed in `gpt-image-garment-catalog-spec.md`; the older SegFormer prototype remains negative evidence only.
- Never commit provider credentials, account secrets, Tailscale credentials, backup credentials, or personal media.

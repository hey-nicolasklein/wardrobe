# FORM V1 Expo App — Product and Architecture Specification

Status: agreed V1 direction

## Problem Statement

FORM currently exists as a throwaway, mobile-first web prototype. It proves several important interaction and image-processing ideas, but its session-oriented client state, temporary generated files, prototype persistence, and synchronous AI requests are not a suitable foundation for a private multi-user application.

The real application needs to let a person build a reusable fitting profile, turn clothing photos into clean wardrobe items, and generate convincing static try-on images. It must preserve the exact inputs behind historical results, keep personal media private, survive app closure and unreliable connectivity, and remain easy to test without repeatedly uploading personal photos or paying for image generation.

The first release will be hosted on one local development machine and accessed from browsers and physical devices over Tailscale. Its architecture must nevertheless enforce real account isolation and use durable, replaceable service boundaries so it can later be deployed publicly without rebuilding the product model.

## Solution

Build a new Expo application for iOS and Android, with Expo Web retained as a fast browser-testing target. The new application will not reuse source code from the Vite prototype; the prototype remains only a behavioral and visual reference until it is removed.

The application has three primary tabs: Looks, Wanting, and Owning. A private Settings area contains fitting-profile management. Users create invite-only accounts, upload personal reference photos, create and refine versioned fitting profiles, add clothing from camera or gallery, review transparent garment extractions, and generate immutable try-on Looks from one fitting-profile version and up to three approved garment versions.

The Expo client communicates with a standalone Hono API. PostgreSQL is the authoritative store for users, domain records, ownership, versions, and durable jobs. Private S3-compatible object storage holds media. Separate image-generation and garment-extraction workers consume PostgreSQL-backed queues. The local stack runs PostgreSQL and object storage through Docker Compose while the Expo client, API, and workers run as hot-reloading application processes.

The server calls `gpt-image-2` directly for fitting profiles and try-ons at high quality. Garment extraction uses the existing deterministic local segmentation approach, followed by server-side mask processing and transparent PNG creation. AI and extraction implementations sit behind narrow provider boundaries so they can be replaced without changing product behavior.

The client supports cached offline browsing and queued basic mutations. Uploads, extraction, fitting-profile creation, and try-on generation require connectivity. Jobs survive app closure; V1 discovers completion through polling and refresh-on-focus rather than push notifications.

## User Stories

1. As an invited tester, I want to sign in with email and password, so that my private wardrobe is isolated from every other account.
2. As a tester, I want seeded account credentials, so that I can enter known scenarios without completing onboarding repeatedly.
3. As a user, I want to use the same account from a phone and browser, so that I see the same wardrobe and Looks everywhere.
4. As a user, I want my cached wardrobe and Looks to remain browsable without connectivity, so that temporary network loss does not make the app empty.
5. As a user, I want basic offline changes to synchronize after reconnecting, so that I do not lose ordinary organization work.
6. As a user, I want private media to require authorization, so that knowing or guessing an asset path never reveals my photos.
7. As a user, I want to add two to five clear photos to a fitting profile, so that generated try-ons resemble me from useful angles.
8. As a user, I want uploaded fitting-profile source photos deleted after a profile is successfully derived, so that unnecessary identifiable originals are not retained.
9. As a user, I want to create a new fitting profile from fresh photos, so that I can replace an inaccurate or outdated representation.
10. As a user, I want to refine a new fitting profile from an existing profile plus new guidance or photos, so that I can improve it without always starting over.
11. As a user, I want older derived fitting-profile versions retained, so that existing Looks remain historically accurate.
12. As a user, I want one fitting-profile version marked active, so that new try-ons consistently use my current choice.
13. As a user, I want to add a clothing source from the camera or gallery, so that I can build my wardrobe without shop-link import.
14. As a user, I want a newly uploaded garment to appear immediately as a draft, so that I can name and categorize it while extraction runs.
15. As a user, I want to manually name and categorize clothing, so that V1 does not depend on unreliable metadata inference.
16. As a user, I want the app to extract a visible garment into a transparent PNG, so that the wardrobe represents the garment rather than its original surroundings.
17. As a user, I want to choose which garment type should be extracted, so that one source photo can be interpreted intentionally.
18. As a user, I want to extract several garments from one source photo, so that I do not have to upload the same outfit repeatedly.
19. As a user, I want to review an extraction before approving it, so that bad masks do not become generation inputs.
20. As a user, I want to retry with another garment type or another source photo, so that I can recover from an imperfect extraction without editing a mask.
21. As a user, I want approved garment extractions to become selectable in Owning or Wanting, so that drafts never accidentally reach try-on generation.
22. As a user, I want a wanted item to become the same owned item after purchase, so that its history and linked Looks remain intact.
23. As a user, I want wardrobe items to transition through wanting, owning, and archived states, so that normal organization is reversible.
24. As a user, I want corrected or reprocessed garment versions preserved immutably, so that older Looks continue to identify their exact inputs.
25. As a user, I want to select up to three approved items from Owning and Wanting for a try-on, so that I can evaluate both existing and prospective clothing.
26. As a user, I want every try-on to use my active fitting profile unless I deliberately choose otherwise, so that results use my current representation.
27. As a user, I want fitting-profile and try-on generation to use high image quality, so that fidelity is evaluated before cost optimization.
28. As a user, I want generation to continue if I leave or close the app, so that a long request does not depend on keeping one screen alive.
29. As a user, I want to see whether a job is queued, processing, complete, or failed, so that background work is understandable.
30. As a user, I want completed generation shown as a preview, so that I decide whether it belongs in Looks.
31. As a user, I want tapping Keep to create one immutable generated Look, so that saved history is intentional and stable.
32. As a user, I want generating again to create another independent Look, so that previous results are never overwritten or hidden in a version tree.
33. As a user, I want to recreate an old Look using current profile and garment versions, so that upgrades create a new result while preserving the original.
34. As a user, I want to add a real outfit snap, so that Looks remains useful without AI generation.
35. As a user, I want to link any reasonable number of owned items to a real snap, so that the three-input AI limit does not constrain manual records.
36. As a user, I want generated Looks to record the exact fitting-profile and garment versions used, so that historical provenance is truthful.
37. As a user, I want transient generation failures retried once, so that brief provider failures do not require immediate manual action.
38. As a user, I want validation, moderation, or account-limit failures to wait for my explicit retry, so that the system does not consume model usage invisibly.
39. As a tester, I want to select prepared personas and data states, so that I can inspect app variants without uploading personal media.
40. As a tester, I want recorded generation and extraction results, so that routine E2E tests never invoke paid or slow AI work.
41. As a tester, I want to switch UI variants while keeping identical fixture data, so that visual comparisons isolate the interface decision.
42. As a tester, I want failed, pending, empty, and complete scenarios, so that important states are exercised deliberately.
43. As an operator, I want per-user worker concurrency to be configurable, so that local capacity can be tuned without code changes.
44. As an operator, I want account and asset ownership enforced centrally, so that later public deployment does not require a multi-tenancy migration.

## Implementation Decisions

### V1 product boundary

- The daily navigation consists of Looks, Wanting, and Owning.
- Fitting profiles live in Settings and are setup infrastructure rather than a primary tab.
- V1 includes fitting-profile generation, garment extraction, wardrobe lifecycle management, static try-on generation, real snaps, offline-aware client behavior, and fixture-backed testing.
- Generated Looks are immutable and contain exactly one result image. V1 has no iteration stack, branching history, or mutable cover image.
- One generated Look references one fitting-profile version and no more than three garment extraction versions.
- A second attempt or an upgrade creates another independent Look. An optional provenance reference may identify the source Look without introducing iteration behavior.
- Real snaps use the same top-level Look collection but are not constrained by the three-garment AI input limit.
- A completed generated preview is not a saved Look until the user explicitly keeps it.
- Unkept preview assets may be removed after a short cleanup period.

### Client application

- Build a clean Expo application with no source-code dependency on the existing Vite prototype.
- Use Expo Router with native tab navigation and nested native stacks.
- Use native modal or form-sheet routes for creation and editing flows rather than custom web-style overlays.
- Support iOS and Android from one codebase. Expo Web remains a supported development and E2E surface, not a separate full desktop product.
- Use native camera/gallery selection and local file URIs. Do not convert media to base64 request bodies.
- Treat server records as authoritative remote state. Use a persisted query cache for reads and a small SQLite-backed outbox for permitted offline mutations.
- Store native session credentials in secure device storage. Browser sessions use secure HTTP-only cookies.
- Refresh remote state on app focus and network reconnect. Poll active jobs while the relevant app surface is open.
- Do not implement push notifications in V1.

### API and contract boundary

- Keep the Hono API independent from the Expo runtime so native, web, workers, and future clients share one server boundary.
- Define request, response, and error contracts with runtime validation. Contract definitions belong to the new system and are not shared with the disposable prototype.
- Commands that can be replayed by the offline outbox or network retries must accept idempotency keys.
- Every owned record and job is resolved through the authenticated account. Ownership checks occur before returning metadata or media access.
- Use opaque stable IDs in domain records. Never store expiring signed URLs as canonical data.
- Return typed, user-actionable error categories for validation, offline state, authorization, transient provider failure, moderation, and capacity limits.

### Authentication and tenancy

- Implement real multi-user isolation in V1 even though early testing is primarily single-user.
- Start with invite/seed-only email and password accounts. Public registration, external OAuth, and complex onboarding are deferred.
- Use one server-side session model with platform-specific transport: HTTP-only cookies for web and opaque tokens for native.
- Include at least two fixture accounts so cross-account authorization is continuously testable.
- Scope database queries, object ownership, queued jobs, and fixture resets by account.

### Persistence and local deployment

- PostgreSQL is the source of truth for accounts, sessions, items, item states, assets, fitting-profile versions, extraction versions, Looks, jobs, and test scenarios.
- Use a PostgreSQL-backed durable job queue and no Redis in V1.
- Run PostgreSQL and private S3-compatible object storage through Docker Compose.
- Run the Expo development server, Hono API, generation worker, and extraction worker as separate hot-reloading processes.
- Browser clients use localhost. Physical devices use the machine's private Tailscale HTTPS hostname.
- Do not expose the API, database, or object storage directly to the public internet during the local phase.

### Media security and transfer

- Keep every object-storage bucket private.
- Upload media through short-lived signed upload URLs issued after authentication and intent validation.
- Read media through short-lived signed download URLs issued after ownership checks.
- Let the client cache rendered assets locally, while treating the server asset ID as canonical.
- Validate file type and size before issuing or confirming an upload.
- Record asset purpose and ownership so fitting references, garment sources, masks, stickers, generated previews, saved Looks, and fixtures have explicit lifecycles.

### Fitting-profile module

- An account has one active fitting profile and may retain multiple historical fitting-profile versions.
- A new version may be built fresh from new reference photos or derived from an older profile with new reference material and guidance.
- New generations use the active fitting-profile version.
- Historical Looks retain the exact fitting-profile version used to generate them.
- Delete newly uploaded personal reference photos after the fitting-profile version is successfully derived. Failed jobs retain recoverable inputs only long enough to retry or let the user resolve the failure.
- Derived historical fitting profiles remain available for history and deliberate reuse.
- Recreating a Look with a newer profile creates a new immutable Look; it never mutates the old image.

The fitting-profile module should expose a small interface around creating versions, activating a version, resolving the active generation reference, and cleaning up temporary source assets. Provider prompts and storage details remain internal.

### Wardrobe and garment-source module

- A wardrobe item is one durable entity with a lifecycle state of wanting, owning, or archived.
- Moving Wanting to Owning updates the existing item and preserves provenance, source, extraction versions, and linked Looks.
- Item creation is manual in V1. Name and garment category are user-provided; AI metadata extraction is deferred.
- A clothing source is uploaded once and may have multiple derived garment extraction jobs and items.
- Retain a clothing source while any extraction depends on it. Permanently delete it only after all dependent extractions are permanently deleted.
- A draft item is visible immediately after upload and moves through queued, extracting, needs-review, and ready states.
- Only ready, user-approved extraction versions are eligible for try-on generation.

The wardrobe module should encapsulate lifecycle transitions and readiness invariants so screens and workers cannot create illegal item states directly.

### Garment-extraction module

- Use the proven local semantic clothes-segmentation approach as the initial provider.
- A user deliberately selects the garment type to extract. The service does not infer metadata in V1.
- Persist each extraction version immutably with its source asset, full-resolution post-processed grayscale base mask, cropped transparent PNG, crop geometry, selected garment type, segmentation model version, and edge-processing version.
- Reserve normalized include and exclude correction strokes in the data model, even though V1 does not expose a mask editor.
- Do not persist every intermediate model tensor. The post-processed base mask is sufficient for later non-destructive stroke correction, edge changes, and recropping without rerunning segmentation.
- V1 recovery actions are Keep, try another garment type, or use another source photo.
- A future editor may send normalized point or stroke coordinates. Corrections create a new extraction version rather than overwriting the base result.
- Future on-device segmentation is permitted but not required. The current server implementation is not assumed to run unchanged inside Expo.

The extraction module should expose enqueue, status, review, approve, and reprocess operations while hiding model loading, mask composition, and asset writing.

### Look-generation module

- Use the OpenAI Images edit API with `gpt-image-2` at high quality for all V1 fitting-profile and try-on outputs.
- Keep provider credentials exclusively in the server/worker environment.
- A generation request resolves exactly one fitting-profile version and up to three approved garment extraction versions before enqueueing.
- Once enqueued, the resolved versions are immutable even if the user later activates or approves newer versions.
- Job completion creates a private review preview. Keeping the preview creates an immutable generated Look; rejecting it schedules preview cleanup.
- Recreating or upgrading from a saved Look copies its intent with currently selected versions and produces a new preview and, if kept, a new independent Look.
- Retry a transient timeout, connection failure, or provider server error once with backoff.
- Do not automatically retry validation, moderation, authentication, or account-limit failures.

The generation module should expose enqueue, status, retry, reject-preview, and keep-preview operations. Prompt construction, OpenAI request details, and provider error translation remain internal.

### Job orchestration

- Store jobs durably in PostgreSQL with ownership, kind, input references, state, progress, attempt count, timestamps, and structured failure information.
- Use separate image-generation and garment-extraction queues so CPU-heavy local segmentation and remote image work can be tuned independently.
- Permit up to three concurrent image-generation jobs per user and three concurrent extraction jobs per user in the local phase.
- Make concurrency limits environment-configurable. Global capacity limits and fair multi-user scheduling may be added before public deployment.
- Recover queued work after process restart. Reconcile jobs left in processing when a worker dies.
- The job row is the source of truth; client polling and any future push message are only delivery mechanisms.

### Offline synchronization

- Allow cached browsing of Looks, Wanting, Owning, item details, and fitting-profile history while offline.
- Queue reversible basic metadata and lifecycle mutations locally with idempotency keys.
- Pause uploads, extraction, and image generation while offline and explain why the action cannot start.
- Replay queued mutations after connectivity returns and refresh affected server queries.
- Use server record versions and timestamps to detect stale mutations. Prefer explicit conflict handling for destructive changes; ordinary scalar edits may use the latest accepted server command.
- Do not attempt a fully local replica of private media or server job execution.

### Scenario and provider-replay module

- Maintain development-only scenarios for at least: empty account, wardrobe ready, fitting profile ready, extraction queued, extraction needs review, generation processing, generation failed, several saved Looks, offline mutations pending, and cross-account access denial.
- Store fixture users, database records, and non-private media assets so a scenario can be reset deterministically.
- Provide replay generation and extraction providers that return recorded results without invoking OpenAI or the segmentation model.
- Add a development-only scenario and UI-variant selector. Variants must operate against identical fixture data.
- Support direct navigation or launch configuration into a named scenario so E2E flows do not depend on previous test order.
- Never include real personal fitting-profile source photos in committed fixtures.

## Testing Decisions

- Favor end-to-end tests that exercise user-visible behavior across the Expo client, API, database, object storage, and replay workers.
- Use Maestro for the highest-value native journeys and browser automation for fast universal-flow coverage.
- Run routine E2E tests against deterministic fixture scenarios and replay providers. Real OpenAI and segmentation smoke tests are deliberate, separate, and never prerequisites for ordinary UI testing.
- Tests assert outcomes and security boundaries rather than component structure, styling implementation, queue internals, or model-library calls.
- Keep unit and integration tests focused on deep modules where a small test surface protects important invariants.

Modules receiving focused non-E2E tests:

- Authentication and ownership authorization, especially cross-account asset and record denial.
- Wardrobe lifecycle transitions and extraction readiness invariants.
- Signed upload confirmation and private signed-read authorization.
- Fitting-profile source cleanup and historical-version preservation.
- Garment mask composition, crop geometry, and replay of normalized correction strokes.
- Immutable generation-input resolution and preview-to-Look promotion.
- Job retry classification, concurrency enforcement, restart recovery, and idempotency.
- Offline outbox replay and duplicate-command handling.

Primary E2E journeys:

1. Sign in with a seeded account and restore its persisted session.
2. Create a fitting profile and verify successful source-photo cleanup.
3. Create a newer fitting profile from fresh inputs and retain the older derived version.
4. Upload one clothing photo, create a draft, extract a garment, review it, and approve it.
5. Extract two different garments from the same source photo without duplicating the source asset.
6. Add a wanted item and transition it to owning without losing identity or history.
7. Generate a high-quality Look from a profile and up to three mixed Owning/Wanting items.
8. Close or navigate away during generation, reopen the app, and recover the job result.
9. Reject a generated preview and keep another, verifying that only the kept preview appears in Looks.
10. Recreate an old Look using current profile or garment versions and verify that the original remains unchanged.
11. Add a real snap and link more than three owned items.
12. Browse cached data offline, queue a permitted mutation, reconnect, and observe one synchronized result.
13. Attempt cross-account record and media access and receive no private data.
14. Switch UI variants while preserving the same selected fixture scenario.
15. Exercise queued, transiently failed, permanently failed, and recovered-after-restart jobs.

The current prototype provides prior art for fitting-profile creation, direct OpenAI image editing, durable garment jobs, local deterministic segmentation, transparent PNG composition, garment preview variants, and mobile-first navigation. Its implementation is evidence for behavior only and will not be imported into the new client.

## Out of Scope

- Public account registration and email verification.
- Apple, Google, or other external OAuth providers.
- Public release infrastructure and internet-facing deployment.
- Push notifications.
- Public or friend sharing of generated Looks or real snaps.
- Followers, social feeds, comments, or collaborative wardrobes.
- Arbitrary shop URLs, scraping, and product-page import.
- AI-generated clothing recommendations and suggestion voting.
- AI inference of item name, category, brand, color, or material.
- Manual mask painting or erasing in the Expo interface.
- Interactive segmentation prompted by user coordinates.
- On-device segmentation.
- Look iteration stacks, parent trees, branches, or mutable cover selection.
- Automatic regeneration of historical Looks after profile or garment updates.
- More than three garment references in a single generated Look.
- General-purpose realtime sockets.
- A full desktop-specific authenticated interface.
- Cost or quality optimization below high-quality image generation.
- Global fair scheduling and public-scale abuse controls.

## Further Notes

- The local deployment is production-shaped but not production-exposed. Real tenancy, durable jobs, private storage, and server-authoritative state are required now; public ingress, elastic capacity, and open registration are later operational changes.
- Tailscale is the only remote access path during local development. Device API and storage URLs must resolve through the private HTTPS hostname rather than localhost.
- Browser and native clients use the same API, fixture accounts, database, and object storage so behavior is comparable across surfaces.
- The existing garment prototype already calculates a full-size post-processed alpha mask in memory. The real extraction service must additionally persist that mask as a lossless grayscale asset.
- The existing direct OpenAI integration is the behavioral starting point for generation. The older Codex recommendation bridge is not part of the V1 generation architecture.
- Before external distribution, revisit global worker capacity, registration abuse prevention, email delivery, push notifications, account-deletion recovery periods, observability, backups, provider data-retention terms, and public deployment topology.

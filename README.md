# FORM — wardrobe studio POC

A mobile-first web prototype for building a private fitting profile of yourself, collecting wardrobe and wishlist pieces, assembling outfits, and rendering try-ons with GPT Image 2. The desktop layout is a secondary responsive expansion; the phone-sized experience is the primary POC surface and a precursor to the native Expo app.

## Run

```sh
npm install
npm run dev
```

Open the app over Tailscale at http://100.71.38.111:5174/. When MagicDNS is working on the client, `http://stargate.stork-platy.ts.net:5174/` is equivalent. The local AI bridge runs on port 4142.

The prototype runs as the enabled `form-wardrobe.service` user service so it survives agent sessions and restarts after failures.

Image generation uses `gpt-image-2` through the OpenAI Images edit API at the `high` quality setting for every fitting profile and look. In this shared development workspace the server reads `OPENAI_API_KEY` from `../photo-studio/.env`; an explicit process environment variable wins. Production should inject the key into the API service and never bundle it in the Expo client. Generated images and temporary uploads live in the OS temp directory (`/tmp/form-wardrobe-poc` on Linux) and can be wiped freely.

Fitting-profile drafts and the completed profile persist in browser IndexedDB so iOS can retire and reload the page without losing selected photos or form state. This remains device-local prototype storage; the Expo build should map the same persistence boundary to app-private filesystem storage plus durable metadata.

## Prototype question

The navigation decision is fixed to three tabs: **Looks**, **Wanting**, and **Owning**. The avatar opens Settings, where the user creates a reusable fitting profile from 2–5 real photos and revises it through a lightweight chat.

The current POC questions are: **does the fitting profile preserve identity well enough for repeated try-ons, and can image-aware AI suggest complementary items that are useful enough to save?**

Every outfit shows its linked items as a simple list. Snaps can be uploaded and manually linked to owned items. Codex suggestions expose confidence and require a thumbs-up or thumbs-down verdict; accepted suggestions move into Wanting and link back to the source look.

## What is real vs. mocked

- Real: fitting-profile creation and revision, local snap uploads, manual item linking, item-to-look backlinks, product-page/image URL import, GPT Image 2 try-on generation, and Codex outfit recommendations.
- Seeded for evaluation: clothing items only. There are no sample people, looks, or recommendations.
- Device-local: fitting-profile drafts and the completed profile persist in IndexedDB.
- Session-only: wardrobe and look changes are intentionally not persisted in this throwaway POC.

## Before a real build

Capture the winning interaction model in `NOTES.md`, then rebuild that path with proper persistence, tests, background jobs, URL-import hardening, and a shared API contract suitable for the later Expo client.

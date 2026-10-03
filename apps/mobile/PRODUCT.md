# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

iOS is the design and runtime authority. Android (10+/API 29) stays buildable with the same FORM design and gets its own QA and polish after the iOS release. iOS 16+, phones in portrait only. The PWA in `apps/web` stays a supported client for browser use.

## Users

People who want to know, use and grow their own wardrobe from their phone. FORM is heading for a public App Store release. Planning in `docs/accounts-and-billing.md` assumes a few hundred users in the first months and a few thousand at most. Nico is one account among them.

Users meet FORM with no prior context. They sign in with Apple or Google, go through onboarding, and photograph their clothes, often several pieces in one photo, in everyday settings at home.

## Product Purpose

FORM is a reliable and pleasant catalog of the clothes a person owns and the pieces they want. The wardrobe comes first. Generated looks are an extra built on top of it.

Success means the catalog stays complete and trustworthy. Adding a piece takes little effort, finding one takes a moment, and the catalog matches what is actually in the closet.

## Positioning

FORM turns photos into a clean wardrobe. One photo can hold several pieces, FORM names them and can create a consistent catalog image for each. Owning and Wanting live side by side, so the wish list sits right next to the wardrobe. The same catalog then feeds looks that are laid out flat or worn by the user, based on their own photo collage.

## Operating Context

- Intake: one or several photos, each piece named and saved directly. Optional detection proposes metadata and splits a photo into multiple pieces. Drafts survive interruption.
- Wardrobe: grid sorted by recency, Owning/Wanting/Archived, filters for category and color, localized search, item detail with edit, image versions and restore.
- Catalog images: optional and paid. Users can choose a quality and give feedback (proportions, color, details) to request a better version. Older versions remain restorable.
- Feed and looks: generated looks, Worn and Flat views, a look composer, share and save to Photos.
- Personal photo collage: one to four photos of the user, used as the reference for worn looks.
- Settings: language, account, credits and weekly costs, quality, feed weights, cache, archive.
- Offline: cached grid, details and media stay readable. Changes are disabled until the connection returns.

## Capabilities and Constraints

- Flutter with Bloc, go_router, easy_localization and drift. One widget tree for both platforms. Material is only the implementation base, and FORM components replace its default visual language.
- German and English. The app follows the device language on first launch, falls back to German, and persists an override.
- Accounts use Sign in with Apple and Google. Email and password remain for CLI/admin accounts and the PWA. Users can delete their account and all records.
- Credits come from an append-only ledger. New accounts get 40. Detection costs 0, a catalog image 1, a look 2, a character sheet 2. Failed jobs are refunded. Errors such as running out of credits and too many active jobs must be surfaced.
- AI work runs on OpenAI and costs money. Every paid generation requires an explicit user action. Photo-only intake, browsing, search and editing make no AI requests.
- No analytics, tracking or remote crash reporting. Logs exclude wardrobe metadata, images, request bodies and credentials.
- Light theme only for now.
- Undecided: pricing, plans and credit packs. The ledger supports them, but no offer is defined.

## Brand Commitments

- Name: FORM, written in capitals.
- Voice: short, warm and direct. Second person ("your wardrobe"). Honest about limits. Onboarding says openly what FORM cannot do: hidden pieces, size and fit, getting every detail right the first time, and working for free.
- Terminology: Wardrobe, Feed, Look, Owning/Wanting/Archived, catalog image, collage, Worn/Flat.
- Visual identity is defined by the existing PWA and `docs/flutter-native/visual-guide.md` and is recorded separately in DESIGN.md.

## Evidence on Hand

- Onboarding garment cutouts in `apps/mobile/assets/onboarding/`.
- Full DE/EN copy in `apps/mobile/assets/translations/`.
- No testimonials, user counts, reviews, press or pricing exist. Do not invent them.

## Product Principles

1. The wardrobe is the product. Every feature has to keep the catalog trustworthy and cheap to maintain.
2. Effort only where it pays off. Capturing a piece should take one photo and a name. Anything more is optional.
3. Costs stay visible and opt-in. Users never trigger paid AI work by accident and can always see what it cost.
4. Honest about AI. Say what works, what varies and what to do when an image is wrong.
5. Personal data stays personal. No tracking, and the user's photos and collage are used only for the user.

## Accessibility & Inclusion

No product-specific standard has been set yet. Stage 1 relied on standard Flutter semantics. Icon-only actions need localized labels, and custom controls must expose their selected and disabled states. A public release needs a dedicated accessibility pass. That target is still open.

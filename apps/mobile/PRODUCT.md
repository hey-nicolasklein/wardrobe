# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

iOS is the design and runtime authority. Android (10+/API 29) stays buildable with the same FORM design and gets its own QA and polish after the iOS release. iOS 16+, phones in portrait only. The PWA in `apps/web` stays a supported client for browser use.

## Users

People who want to know, use and grow their own wardrobe from their phone. FORM is heading for a public App Store release. Planning in `docs/accounts-and-billing.md` assumes a few hundred users in the first months and a few thousand at most. Nico is one account among them.

Users meet FORM with no prior context. They sign in with Apple or Google, go through onboarding, and photograph their clothes, often several pieces in one photo, in everyday settings at home. Photos of themselves are asked for only when they first use Inspiration.

## Product Purpose

FORM is the home for a person's clothes and looks. Today those live as selfies scattered across the camera roll. FORM replaces that with a clean wardrobe and managed looks, and every look links back to the pieces it is made of.

The wardrobe is the baseline. Everything around it is a bonus:
- Inspiration from clothes the user already owns, so they buy less. That saves money and effort and is better for the environment.
- AI-generated looks that inspire. Their quality varies a lot, so nothing in the wardrobe depends on them.
- Trying looks on the user's own photos.

FORM only works when the wardrobe is clean. A wardrobe of screenshots or raw phone photos is not usable. It is clean only once every piece has its generated catalog image.

Success means the catalog stays complete and trustworthy. Adding a piece feels seamless, finding one takes a moment, and the catalog matches what is actually in the closet.

## Positioning

FORM is a better version of the selfie folder in Apple Photos. FORM turns photos into a clean wardrobe. One photo can hold several pieces, FORM names them and creates a consistent catalog image for each. Owning and Wanting live side by side, so the wish list sits right next to the wardrobe. The same catalog then feeds looks: laid out flat, tried on the user's own photo, or generated as inspiration.

## Operating Context

- Intake: pick one or several photos and you are done. Upload, detection and catalog images run in the background while the user stays in the Schrank. Detected pieces arrive as new tiles; accessories stay out unless picked. Corrections happen on the tile: rename, or move a wrongly detected piece to the archive with undo. Photos without detected pieces wait for a name. Drafts survive interruption.
- Wardrobe: grid sorted by recency, Owning/Wanting/Archived, filters for category and color, localized search, item detail with edit, image versions and restore.
- Catalog images: part of every saved piece and paid. The first image is right in almost every case, so no review step is needed. In the rare bad case, users give feedback (proportions, color, details) to request a better version. Users can choose a quality. Older versions remain restorable.
- Looks: the second tab, an archive sorted by occasion, Sammlung, piece and colour. A look is always a combination of the user's pieces, free and laid out flat. Images sit on top and never replace it: a photo the user wore it in (a photo look, whose detected pieces are listed for linking or adding), Try on (Anprobe), which puts the pieces 1:1 on a photo of the user, or Inspiration, a full AI scene whose quality varies. New looks come from the composer, from the user's photos, or from FORM's swipe suggestions, which are kept as combinations for free.
- Personal photo collage: one to four photos of the user, used as the reference for Inspiration looks only. Asked for on the first Inspiration, not in onboarding.
- Settings: language, account, credits and weekly costs, quality, feed weights, cache, archive.
- Offline: cached grid, details and media stay readable. Changes are disabled until the connection returns.

## Capabilities and Constraints

- Flutter with Bloc, go_router, easy_localization and drift. One widget tree for both platforms. Material is only the implementation base, and FORM components replace its default visual language.
- German and English. The app follows the device language on first launch, falls back to German, and persists an override.
- Accounts use Sign in with Apple and Google. Email and password remain for CLI/admin accounts and the PWA. Users can delete their account and all records.
- Credits come from an append-only ledger. New accounts get 40. Detection costs 0, a catalog image 1, a look 2, a character sheet 2. Failed jobs are refunded. Errors such as running out of credits and too many active jobs must be surfaced.
- AI work runs on OpenAI and costs money. Every paid generation requires an explicit user action. Saving pieces is that action for catalog images, and the cost is stated before saving. Browsing, search and editing make no AI requests.
- No analytics, tracking or remote crash reporting. Logs exclude wardrobe metadata, images, request bodies and credentials.
- Light theme only for now.
- Undecided: pricing, plans and credit packs. The ledger supports them, but no offer is defined.

## Brand Commitments

- Name: FORM, written in capitals.
- Voice: short, warm and direct. Second person ("your wardrobe"). Honest about limits. Onboarding says openly what FORM cannot do: hidden pieces, size and fit, getting every detail right the first time, and working for free.
- Terminology: Wardrobe, Feed, Look, Owning/Wanting/Archived, catalog image, collage, Worn/Flat, Try on (Anprobe), Inspiration.
- Visual identity is defined by the existing PWA and `docs/flutter-native/visual-guide.md` and is recorded separately in DESIGN.md.

## Evidence on Hand

- Onboarding garment cutouts in `apps/mobile/assets/onboarding/`.
- Full DE/EN copy in `apps/mobile/assets/translations/`.
- No testimonials, user counts, reviews, press or pricing exist. Do not invent them.

## Product Principles

1. The wardrobe is the product. Every feature has to keep the catalog clean, trustworthy and cheap to maintain.
2. Adding is seamless. Capturing a piece should take one photo and a name. The catalog image follows on its own, and anything more is optional.
3. Looks are a bonus. Their quality varies, so nothing in the wardrobe may depend on them.
4. Costs stay visible and opt-in. Users never trigger paid AI work by accident and can always see what it cost.
5. Honest about AI. Say what works, what varies and what to do when an image is wrong.
6. Personal data stays personal. No tracking, and the user's photos and collage are used only for the user.

## Accessibility & Inclusion

No product-specific standard has been set yet. Stage 1 relied on standard Flutter semantics. Icon-only actions need localized labels, and custom controls must expose their selected and disabled states. A public release needs a dedicated accessibility pass. That target is still open.

# Prototype verdict

## Garment preview experiment

Question: does a literal transparent sticker or an in-context dimmed spotlight best highlight one visible garment?

- Route: `/?prototype=garment&variant=A`
- A — sticker first verdict:
- B — context spotlight verdict:
- C — evidence board verdict:
- Mask failures noticed (arms, hair, layering, dark fabrics):
- Decision to absorb:

The experiment stores only the original upload, crop geometry, and a context-cropped transparent PNG. The browser recreates the spotlight by dimming a crop of the original and layering the PNG over it. Jobs and these two image assets live in `.prototype-data/garment-jobs`; queued work resumes after a server restart. This is deliberately scratch persistence for the POC.

Edge treatment under review: a one-pixel feathered alpha ramp with restored midpoint contrast. Spotlight surroundings can be dimmed toward black or faded toward white; this presentation choice is URL-stable and creates no additional stored image.

Questions:

1. Can a 2–5 photo fitting profile preserve identity well enough for repeated wardrobe try-ons?
2. Can image-aware AI suggest complementary items that are useful enough to save?

Navigation decision: three tabs — Looks, Wanting, Owning.

Profile concept under review:

- Product name: **fitting profile**, not character or profile card.
- Lives in Settings behind the avatar; it is setup infrastructure, not a daily tab.
- Upload-first: 2 photos minimum, 5 maximum; front/side/full-body guidance.
- One multi-pose vertical contact sheet is the reusable identity artifact.
- Chat revisions regenerate a low-quality GPT Image 2 draft while preserving the last successful image on failure.
- Low quality is the default for profile drafts and try-ons. Promote selectively only if identity or garment fidelity fails in representative testing.
- Fitting-profile drafts and completed profiles persist locally in IndexedDB so iOS page retirement is recoverable. Production requires encrypted persistence, explicit deletion, background jobs, and Expo-safe upload handling.

Fitting-profile evaluation:

- Identity is recognisable across all panels: 
- Body proportions are credible: 
- Revision chat fixes a specific issue without regressing identity: 
- Low quality is sufficient for setup decisions: 
- Upgrade trigger for medium quality, if any: 
- Verdict — keep contact sheet, split views, or change artifact: 

Evaluate after at least 20 suggestions across a mix of generated looks and real snaps:

- Suggestions accepted into Wanting: 
- Suggestions rejected: 
- Acceptance rate: 
- Repeated/generic suggestions noticed: 
- Did confidence correlate with usefulness? 
- Verdict — keep, narrow, or remove recommendations: 

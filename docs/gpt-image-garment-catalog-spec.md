# GPT Image 2 Shelf Image Specification

Status: accepted V1 direction, 2026-08-02

Supersedes the production direction proposed by `gpt-segformer-prototype-spec.md`. The SegFormer prototype remains historical evidence; SegFormer is not part of the V1 garment pipeline.

## Decision

FORM will turn a visible Wardrobe Item in a private, durable Source Photo into a clean, laid-flat Shelf Image with `gpt-image-2` through the OpenAI Images edit API.

This is a generative reconstruction, not a pixel-exact segmentation or transparent cutout. The product must call it a **Shelf Image**, never a mask, cutout, extraction, or proof of the item's unseen construction. Every result requires user review and an explicit Keep before it becomes the Wardrobe Item's current Shelf Image.

V1 will not load, run, store outputs from, or provide recovery controls for SegFormer. It will not store semantic masks, component scores, mapped segmentation labels, edge-processing versions, or mask correction strokes.

## What the prototype established

### Keep

- GPT vision can propose multiple visible Wardrobe Items with useful short names, strict categories, colors, and normalized bounding boxes.
- The image-first selection interaction works best when boxes and a synchronized list are both present. The list is required for overlapping and small proposals.
- Selection and metadata review must remain separate. A user can correct the target name, category, and colors before spending money on image generation; notes remain manual.
- One Source Photo may create several independent Wardrobe Items without being uploaded repeatedly, and it remains visible as private provenance from every derived item detail page.
- GPT Image 2 can produce the desired shop-style presentation: the empty garment alone, laid flat, centered, and separated from the source person and surroundings.
- Low, Medium, and High are useful explicit comparison settings. They must be independent opt-in generations, never three automatic charges.
- API-returned usage is sufficient to show request-level text-input, image-input, and image-output costs.
- A uniform collision-avoiding chroma background gives the server a practical way to derive a transparent catalog asset even though GPT Image 2 does not support transparent output.
- HEIC and HEIF camera-roll photos must be normalized before browser preview or provider processing.

### Reject

- SegFormer is not reliable enough for wardrobe-quality extraction of layered, cropped, occluded, or same-label garments.
- GPT bounding boxes cannot repair an incomplete or contaminated semantic mask.
- Connected-component scoring cannot separate garments that a semantic model has already joined.
- A technically complete segmentation is not a visual-quality verdict.
- The production system must not retain SegFormer as a mandatory pre-step or fallback.

## User flow

```text
choose Source Photo
  → normalize HEIC/HEIF to JPEG when necessary
  → GPT proposes visible garments and normalized boxes
  → user selects proposals
  → user reviews name, category, and colors
  → Low-quality 816 × 816 is selected by default; Medium and High are optional alternatives
  → one explicit action starts one GPT Image 2 edit per selected garment
  → server removes the generated chroma background
  → user reviews the Shelf Image
  → Keep creates an immutable Shelf Image Version and makes it current
```

For a Source Photo containing one obvious product, the client may offer a direct “use this item” path that skips proposal selection. Metadata review and the explicit paid-generation action remain required.

The UI may offer a development comparison mode that retains Low, Medium, and High side by side. Production defaults to Low at 816 × 816 and does not run Medium or High unless the user explicitly requests another version.

## Source ingestion

- Accept JPEG, PNG, WebP, HEIC, and HEIF.
- Native clients upload file bytes from local URIs; they do not send base64 request bodies.
- Convert HEIC and HEIF to orientation-correct JPEG before browser preview, GPT vision, or GPT Image input. The current validated conversion quality is 0.92.
- Enforce authenticated upload intent, private object storage, declared and decoded file-type validation, pixel limits, and byte limits.
- Preserve the private Source Photo while any proposal or Wardrobe Item depends on it. Show it from each derived item's authenticated detail page.
- Do not persist a second conversion-only upload when a normalized derivative can be managed as a temporary job input.

## Detection contract

Use a server-side GPT vision request with strict structured output. Provider credentials never enter client code.

```ts
type DetectionCategory =
  | 'top'
  | 'jacket'
  | 'pants'
  | 'skirt'
  | 'dress'
  | 'shoes'
  | 'bag'
  | 'hat'
  | 'scarf'
  | 'unsupported';

type GarmentDetection = {
  id: string;
  name: string;
  category: DetectionCategory;
  colors: string[];
  boundingBox: {
    x: number;
    y: number;
    width: number;
    height: number;
  };
};
```

Coordinates are integers normalized to a 1000 × 1000 space. Validate and clamp them server-side. Unsupported proposals remain visible but cannot start catalog generation in V1.

The detection prompt asks for every distinct visible wearable item, including layered garments and accessories, and proposes a concise color list supported by visible pixels. It must not infer hidden items, merge separate garments, or return brands, materials, arbitrary tags, notes, masks, or polygons.

## Reference preparation

For each reviewed proposal:

1. Normalize source orientation.
2. Convert the reviewed normalized box to source pixels.
3. Crop the target with approximately 18% context padding, clamped to the source bounds.
4. Keep enough context for GPT Image 2 to understand the garment, but do not include the full outfit when a useful target crop is available.
5. Send the cropped reference and the reviewed name, category, and colors to the image worker.

The crop identifies the target; it is not an extraction result and must not be displayed as if it were one.

## GPT Image request

- Endpoint: OpenAI Images edit API.
- Model: `gpt-image-2`.
- Output format: PNG.
- Size: 816 × 816.
- Quality: Low, Medium, or High; Low is the production default.
- Moderation: provider-supported application setting, with moderation failures treated as user-actionable and never automatically retried.

816 × 816 is the smallest practical square near the original 500 × 500 product target while satisfying GPT Image 2's minimum pixel count and 16-pixel edge alignment. Do not request 2K or 4K for garment catalog assets in V1.

### Prompt template

Use this prompt as the V1 baseline. Substitute only the reviewed item name, category, and colors. Prompt changes require a version bump and replay evaluation against the garment fixture set.

```text
Create a faithful e-commerce catalog presentation from the source image.

SUBJECT
- Show only the complete empty garment: {reviewed item name} ({reviewed category}; reviewed colors: {reviewed colors}).
- Remove every person, body part, mannequin, hanger, tag string, prop, and surrounding object.
- Present the garment laid flat, viewed straight from above, centered, with generous even padding.
- Preserve the source-supported silhouette, proportions, color, pattern, seams, panels, hems, cuffs, collar, closures, pockets, trim, wear, and fabric behavior exactly.
- Construction must be supported by the source. Omit logos, labels, text, hardware, lining, reverse-side features, material claims, or decorative details that are hidden, illegible, ambiguous, or uncertain.
- Where removing the wearer exposes an unseen area, use only the plainest continuation of source-supported fabric needed to make the empty item complete. Add no new seam, fold, fastening, texture, or design detail.

BACKGROUND
- Use one perfectly uniform, fully opaque chroma background across every non-garment pixel, with no floor line, texture, gradient, lighting variation, contact shadow, or cast shadow.
- Default to exact RGB #00ff00.
- If #00ff00 is present in the garment, use exact RGB #ff00ff instead, unless magenta is prominent in the garment.
- If both defaults conflict, choose the maximally distant saturated RGB key color.
- Never use a key color present anywhere in the garment.

OUTPUT
- One square shop-style product image. Garment only. No styling, text, border, watermark, or extra view.
```

## Chroma removal and Shelf Image asset

1. Infer the key from padded corner pixels in the returned image.
2. Verify that the border is sufficiently uniform. If it is not, fail the post-processing step rather than silently removing arbitrary garment colors.
3. Make pixels close to the inferred key transparent and feather only the narrow antialiased boundary.
4. Preserve the full square canvas and generous padding.
5. Display the transparent Shelf Image on the app's neutral background.

Never remove a hard-coded green or magenta value without first resolving the key for that result. Record the resolved key with the Shelf Image Version.

The worker retains the raw keyed provider output until the transparent derivative has passed validation and the user has made a review decision. Kept Shelf Image Versions retain both the raw keyed asset and the transparent derivative so post-processing can be improved without paying for another generation. Rejected temporary assets follow the normal cleanup policy.

## Review and readiness

A completed provider request enters `needs_review`; it does not automatically become the current Shelf Image.

The detail panel shows:

- Source Photo proposal and reviewed name, category, and colors;
- Shelf Image on a clean neutral background;
- model, quality, requested size, prompt version, and resolved chroma key;
- actual token usage and cost breakdown;
- Keep, generate another quality, or choose another source.

Keep creates an immutable Shelf Image Version and makes it current. Another generation creates another version and never overwrites or hides an earlier kept version, charge, or result. A person may restore any kept version as current without another provider request.

The UI must describe the output as AI-generated when that distinction is material. It must not imply that occluded construction, exact material, branding, or reverse-side details were observed in the source.

## Cost accounting

Calculate request cost from the usage object returned by OpenAI, not from a per-image estimate.

```text
text input cost  = text input tokens  × captured text-input rate  / 1,000,000
image input cost = image input tokens × captured image-input rate / 1,000,000
image output cost = output tokens      × captured image-output rate / 1,000,000
request cost = text input cost + image input cost + image output cost
```

Store money as integer microdollars or a decimal type, never binary floating point. Persist the token counts, rate snapshot, pricing effective date, service tier, model, quality, size, request ID, and computed components with each attempt.

The displayed value is exact for the captured standard API rate calculation. Taxes, contractual discounts, credits, or a future regional-processing uplift are account-level billing concerns and must not be silently folded into a request estimate.

Do not save a successful result without its provider usage ledger. If usage is absent, mark the attempt failed with an internal accounting error and retain enough provider metadata for investigation.

## Durable jobs and retries

Use one durable remote-image job queue. There is no local segmentation queue.

Each garment generation attempt stores:

- owner and source asset ID;
- reviewed detection ID, name, category, colors, and bounding box;
- cropped reference asset ID or deterministic crop parameters;
- model, quality, size, prompt version, and request ID;
- queued, processing, needs-review, kept, rejected, or failed state;
- actual usage, captured rates, and cost components;
- raw keyed output asset ID, transparent Shelf Image asset ID, and resolved chroma key;
- attempt count, timestamps, and structured failure category.

Retry one transient connection, timeout, rate-limit, or provider-server failure with backoff. Do not automatically retry validation, conversion, moderation, authentication, quota, accounting, or chroma-validation failures. An explicit user retry creates a separately costed attempt.

## Module boundary

The Shelf Image module exposes operations equivalent to:

- detect source garments;
- review proposals;
- enqueue Shelf Image generation;
- read attempt status and cost;
- keep or reject a result;
- create another quality/version;
- keep, restore, and resolve the current Shelf Image Version.

It hides provider prompts, image cropping, HEIC conversion, OpenAI transport, cost arithmetic, chroma removal, private asset writing, and cleanup policy.

## Testing

Routine tests use replay providers and recorded private-safe fixtures. Paid OpenAI calls are deliberate smoke tests only.

Required fixture coverage:

- simple isolated top;
- patterned garment;
- green garment requiring a non-green key;
- magenta garment requiring a third saturated key;
- layered outerwear;
- cropped pants or dress;
- dark garment on a dark background;
- two same-category garments;
- shoes and bag;
- unsupported wearable;
- HEIC source with orientation metadata;
- non-uniform provider background failure;
- missing usage ledger;
- Low, Medium, and High recorded outputs and costs.

Primary assertions:

1. HEIC/HEIF becomes a decodable, orientation-correct JPEG before preview and processing.
2. Selection and metadata review do not spend image-generation money.
3. One explicit action creates one Low-quality 816 × 816 charged attempt by default.
4. Low, Medium, and High attempts remain independently visible and their costs sum correctly.
5. A missing usage ledger cannot create a ready version.
6. Chroma selection never removes a color present in the garment fixture.
7. Non-uniform chroma output fails visibly.
8. Rejected outputs never become current Shelf Images.
9. Keeping a result creates an immutable Shelf Image Version with exact Source Photo and reviewed-metadata provenance.
10. Restoring an older kept version changes the current pointer without mutating history or invoking the provider.
11. Cross-account job, cost, Source Photo, and media access is denied.

## Out of scope

- SegFormer or another mandatory semantic-segmentation pre-step.
- Pixel-exact claims about generated garment geometry.
- Manual mask painting, correction strokes, or connected-component controls.
- Automatic approval or wardrobe insertion.
- Automatic generation of all three quality levels.
- 2K or 4K garment catalog output.
- Inference of brand, material, hidden construction, labels, or illegible text.
- Shop-page scraping or arbitrary product import.

# GPT Detection → SegFormer Extraction Prototype

Status: ready for a fresh implementation chat

## Fresh-chat instruction

Use the `prototype` skill and implement this specification as a throwaway UI prototype in the existing `wardrobe-studio` repository.

Do not redesign the production Expo architecture and do not turn the prototype into production code. Reuse the existing Vite prototype, Hono server, OpenAI bridge, and local `Xenova/segformer_b2_clothes` implementation where useful. Clearly mark every new route, module, API, and data file as prototype-only.

The prototype must run through the repository's normal development command (`npm run dev`). Put the experiment on one URL-stable route, using `?prototype=detect-extract&variant=A|B|C` for its presentation variants.

## Question to answer

Does this end-to-end interaction and technical pipeline feel viable?

```text
upload one clothing/outfit photo
  → GPT proposes every visible garment with metadata and bounding boxes
  → user selects supported highlighted garments
  → user reviews names and categories
  → one batch confirmation starts extraction
  → SegFormer extracts every selected garment
  → evidence view makes successes and failure causes visible
```

Specifically, discover:

1. Which garments GPT misses, duplicates, mislabels, or boxes poorly.
2. Which valid GPT proposals SegFormer fails to extract.
3. When the GPT category maps to the wrong SegFormer configuration.
4. When two garments sharing a semantic label cause the wrong instance to be extracted.
5. Whether selecting suggestions, reviewing them, and extracting them as one batch feels understandable.

This is an evidence-gathering prototype, not a demonstration that assumes the pipeline works.

## Fixed decisions

- Use a real `gpt-5.4-mini` vision request.
- Use the existing real local SegFormer model.
- Process one source photo per run.
- A source photo may produce several garment proposals.
- Supported proposals begin unselected.
- Unsupported detections remain visible but cannot be selected for extraction.
- Selecting proposals does not start work.
- After selection, show a separate metadata-review step.
- One explicit batch confirmation starts all selected extractions.
- Run SegFormer once against the full source image, not once per cropped proposal.
- Use GPT bounding boxes to choose connected components from the relevant semantic mask.
- Crop only after resolving the final full-resolution mask.
- Keep failure evidence visible. Do not add correction or recovery tools.
- Do not implement library insertion, Wanting/Owning decisions, authentication, offline behavior, or production persistence.
- Do not implement bounding-box-only crops for unsupported garments. That is a possible future fallback, not part of this experiment.
- Do not add pixel-mask editing, manual boxes, box resizing, category controls outside the agreed review step, or retry workflows beyond resetting and trying another source image.

## GPT detection contract

Send the uploaded image to `gpt-5.4-mini` through the server. Credentials must never enter client code.

Require strict structured output containing every distinct visible wearable item:

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
  boundingBox: {
    x: number;
    y: number;
    width: number;
    height: number;
  };
};
```

Bounding-box coordinates are integers normalized to a 1000 × 1000 coordinate space. Validate and clamp them server-side. IDs only need to be stable within the current in-memory run.

Ask only for the short name, category, and bounding box. Do not ask GPT for colors, brands, materials, tags, masks, polygons, or arbitrary SegFormer label names.

The UI may allow editing the proposed short name and choosing another value from the same strict category enum during the review step. The raw GPT response must remain visible in diagnostics so an edit does not hide the original classification.

## Deterministic category mapping

The server, not GPT, owns this mapping:

| GPT category | SegFormer labels |
| --- | --- |
| `top` | `Upper-clothes` |
| `jacket` | `Upper-clothes` |
| `pants` | `Pants` |
| `skirt` | `Skirt` |
| `dress` | `Dress` |
| `shoes` | `Left-shoe`, `Right-shoe` |
| `bag` | `Bag` |
| `hat` | `Hat` |
| `scarf` | `Scarf` |
| `unsupported` | none |

Keep the product category and resolved SegFormer labels separately in diagnostic state. This must make it possible to distinguish a GPT classification error from a mapping or segmentation error.

## Segmentation and instance-selection algorithm

1. Normalize orientation and decode the source once.
2. Run `Xenova/segformer_b2_clothes` once on the complete source image.
3. Preserve the raw label results needed for diagnostics.
4. For each selected proposal, combine the masks for its mapped SegFormer labels into a full-resolution grayscale semantic mask.
5. Find connected components in that mask.
6. Convert the GPT box from normalized coordinates to source-image pixels.
7. Score components using overlap with the GPT box. The implementation may combine intersection-over-component, intersection-over-box, and distance between component and box centers, but it must expose the component scores in diagnostic state.
8. Select the strongest plausible component or component group. Shoes may deliberately combine left- and right-shoe components when both overlap the proposal.
9. If no plausible component overlaps the box, report an explicit extraction failure instead of silently using the entire category mask.
10. Apply the existing edge post-processing to the selected mask.
11. Produce:
    - full-resolution grayscale selected mask;
    - transparent cropped PNG;
    - crop geometry in source coordinates;
    - extraction status and diagnostic reason.

Do not ask GPT Image to reconstruct or redraw the garment.

## Minimal state model

Render the full relevant state in a collapsible diagnostics panel after every transition.

```ts
type PrototypePhase =
  | 'empty'
  | 'detecting'
  | 'selecting'
  | 'reviewing'
  | 'extracting'
  | 'complete'
  | 'failed';

type PrototypeState = {
  phase: PrototypePhase;
  sourcePreviewUrl: string | null;
  sourceDimensions: { width: number; height: number } | null;
  rawDetectionResponse: unknown;
  detections: Array<GarmentDetection & {
    supported: boolean;
    selected: boolean;
  }>;
  reviewedItems: Array<{
    detectionId: string;
    originalName: string;
    originalCategory: DetectionCategory;
    name: string;
    category: DetectionCategory;
  }>;
  segmentationRun: {
    model: string;
    labelsPresent: string[];
    startedAt: string;
    finishedAt: string | null;
  } | null;
  results: Array<{
    detectionId: string;
    mappedLabels: string[];
    boundingBoxPixels: { x: number; y: number; width: number; height: number };
    componentScores: unknown[];
    status: 'complete' | 'failed';
    failureReason?: string;
    maskUrl?: string;
    cutoutUrl?: string;
    crop?: { x: number; y: number; width: number; height: number };
  }>;
  error: string | null;
};
```

State may live in memory. Temporary generated files may live under an obviously disposable `.prototype-data/detect-extract/` directory if URLs are needed to display them. The prototype must provide a Reset action that returns to `empty` and makes another source photo testable.

## Shared interaction flow

All variants use the same underlying state and real API behavior.

### 1. Upload and detect

- Choose one JPEG, PNG, or WebP image.
- Show the selected image immediately.
- Start detection through an explicit action; do not spend API money merely because the file picker changed.
- While detecting, show that GPT is analyzing the image.

### 2. Select proposals

- Draw every GPT bounding box over the source image.
- Give every box a readable name/category label.
- Supported proposals start unselected and can be toggled.
- Unsupported boxes remain visible with a clear “Not supported for extraction” treatment.
- Keep a synchronized proposal list available where overlapping boxes would make direct tapping ambiguous.
- Continue is disabled until at least one supported proposal is selected.

### 3. Review metadata

- Use a separate review step.
- Show one compact row or card per selected proposal.
- Show its source thumbnail, short name, and strict category selector.
- Require a supported valid category for every row.
- Back returns to selection without rerunning GPT.
- The final action says `Extract N items` and is the single commitment point.

### 4. Extract and inspect

- Start one server-side segmentation run for the full source image.
- Derive each selected result from that shared run.
- Show per-item progress/status even if processing is sequential internally.
- For every item, show:
  - the source with its GPT box;
  - mapped SegFormer labels;
  - selected mask on a black/white or checkerboard background;
  - transparent cutout when successful;
  - explicit failure reason when unsuccessful.
- Never replace a failed result with a plausible-looking fallback.

## UI variants

Implement all variants on the same route and switch them through both the URL parameter and a floating prototype switcher. Switching variants must preserve the current in-memory run and render the full relevant state.

### Variant A — Image-first

The source photo dominates the screen. Bounding-box labels are the primary selection controls. A compact bottom sheet/list resolves overlaps and advances to review. Extraction results replace or sit beneath the source.

Question: does direct manipulation of the highlighted garments feel obvious?

### Variant B — Evidence board

Keep the source with boxes, proposal list, metadata, masks, cutouts, and diagnostics visible in a dense comparison layout.

Question: is a transparent all-at-once view best for evaluating technical failures?

### Variant C — Guided stepper

Use four clear screens or panels: Upload, Select, Review, Results. Keep only the information necessary for the current step visible, with Back where it does not repeat paid or expensive work.

Question: does progressive disclosure make the multi-stage pipeline easier to understand?

Skip visual polish. The three variants should differ structurally, not through colors or typography alone.

## Failure evidence to surface

The prototype must make these cases recognizable without adding repair tools:

- GPT returned no garments.
- GPT missed an item visible to the tester.
- GPT returned a duplicate item.
- GPT box covers the wrong or incomplete region.
- GPT marked a garment unsupported.
- GPT chose the wrong supported category.
- Expected SegFormer labels are absent from the source result.
- Relevant label exists but no component plausibly overlaps the GPT box.
- Several components compete for the same proposal.
- Two GPT proposals resolve to the same component.
- Selected mask contains the wrong garment, multiple garments, body pixels, or severe missing regions.
- Extraction succeeds technically but produces an unusable crop or edge.

Not every visual-quality problem can be detected automatically. Show enough evidence for the tester to judge it.

## Evaluation session

Run the prototype against a deliberately varied set of personal or disposable test images, one at a time. Include, when available:

- one isolated garment;
- a person wearing a simple top and pants;
- layered top and jacket;
- two garments sharing the same broad category;
- shoes or accessories;
- partial occlusion;
- dark garment on dark background;
- patterned garment;
- mirror selfie or visually busy room;
- at least one unsupported wearable.

For each image, record a short manual verdict outside the runtime UI:

```text
Source:
GPT detections correct/missed/extra:
Boxes usable:
Category mappings correct:
SegFormer result per selected item:
Failure stage: detection | classification | box | mapping | segmentation | component selection | crop/edge
Notes:
```

Do not build a verdict database or annotation tool.

## Success criteria

The prototype succeeds as an experiment if it lets us answer all of the following, even if the pipeline itself performs badly:

1. Can testers understand how to select GPT-proposed garments?
2. Is the separate metadata review worth the extra step?
3. Does one full-image SegFormer pass produce usable masks for several selected proposals?
4. Do bounding boxes reliably disambiguate connected components with the same semantic label?
5. Can every bad result be attributed to a specific pipeline stage from the displayed evidence?
6. Which image or garment classes should be unsupported, warned about, or handled differently in the real application?

Do not declare the pipeline viable from one successful image. The final verdict must name the tested source-image classes, observed failure modes, and recommended production boundary.

## Explicit non-goals

- Production Expo UI or native components
- Adding items to the real library
- Wanting/Owning/archive lifecycle
- Authentication or account isolation
- Offline support
- Durable production jobs or queues
- AI garment reconstruction
- Modeled previews or try-on generation
- Color, brand, material, or tag inference
- Manual boxes, box adjustment, or mask correction
- Bounding-box-only fallback crops
- Automated quality scoring
- Test suites, general abstractions, or reusable design-system work

## Expected handoff

When implementation and a representative evaluation are complete:

1. Report the exact route and one command to run it.
2. Report which source-image classes were tested.
3. Separate failures by detection, classification, box, mapping, segmentation, component selection, and crop/edge stages.
4. Give a concise verdict on whether the flow feels right and whether the technical pipeline is viable.
5. State what should be absorbed into the production spec and what should be rejected or deferred.
6. Follow the `prototype` skill's capture rule: keep throwaway implementation out of main, preserve it on a throwaway branch, and record the verdict with a pointer to that branch.

import { randomUUID } from 'node:crypto';

import {
  garmentDetectionSchema,
  type GarmentDetection,
  type GenerationQuality,
  type ItemMetadata,
  type NormalizedBoundingBox,
  type LookConcept,
} from '@form/contracts';
import sharp from 'sharp';
import { z } from 'zod';

export type ProviderFailureCategory =
  | 'connection'
  | 'timeout'
  | 'rate-limit'
  | 'provider-server'
  | 'validation'
  | 'moderation'
  | 'authentication'
  | 'quota'
  | 'accounting';

export class CatalogProviderError extends Error {
  constructor(
    readonly category: ProviderFailureCategory,
    message: string,
    readonly retryable: boolean,
  ) {
    super(message);
    this.name = 'CatalogProviderError';
  }
}

export type DetectionProviderResult = {
  requestId: string;
  detections: GarmentDetection[];
};

export type GenerationUsage = {
  textInputTokens: number;
  imageInputTokens: number;
  outputTokens: number;
  serviceTier: string;
  raw: unknown;
};

export type GenerationProviderResult = {
  requestId: string;
  pngBytes: Buffer;
  usage: GenerationUsage;
};

export interface CatalogProvider {
  detect(input: {
    jpegBytes: Uint8Array;
    model: string;
    signal?: AbortSignal;
  }): Promise<DetectionProviderResult>;
  generate(input: {
    referenceJpeg: Uint8Array;
    metadata: ItemMetadata;
    model: string;
    quality: GenerationQuality;
    size: '816x816';
    promptVersion: string;
    signal?: AbortSignal;
  }): Promise<GenerationProviderResult>;
  planLook(input: {
    candidates: Array<{ id: string; metadata: ItemMetadata }>;
    recent: Array<{ itemIds: string[]; concept: LookConcept | null }>;
    exactItemIds: string[];
    categories: string[];
    occasion?: string | null;
    model: string;
    signal?: AbortSignal;
  }): Promise<{ requestId: string; itemIds: string[]; concept: LookConcept }>;
  generateComposite(input: {
    references: Uint8Array[];
    prompt: string;
    model: string;
    quality: GenerationQuality;
    size: '864x1536' | '1024x1280';
    signal?: AbortSignal;
  }): Promise<GenerationProviderResult>;
}

const detectionOutputSchema = z
  .object({
    detections: z.array(
      z
        .object({
          name: z.string(),
          category: z.enum([
            'top',
            'jacket',
            'pants',
            'skirt',
            'dress',
            'shoes',
            'bag',
            'hat',
            'scarf',
            'unsupported',
          ]),
          colors: z.array(z.string()),
          boundingBox: z.object({
            top: z.number(),
            left: z.number(),
            bottom: z.number(),
            right: z.number(),
          }),
        })
        .strict(),
    ),
  })
  .strict();

function detectionJsonSchema(pixelWidth: number, pixelHeight: number) {
  return {
    type: 'object',
    properties: {
      detections: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            name: { type: 'string' },
            category: {
              type: 'string',
              enum: [
                'top',
                'jacket',
                'pants',
                'skirt',
                'dress',
                'shoes',
                'bag',
                'hat',
                'scarf',
                'unsupported',
              ],
            },
            colors: {
              type: 'array',
              items: { type: 'string' },
              minItems: 1,
              maxItems: 6,
            },
            boundingBox: {
              type: 'object',
              properties: {
                top: { type: 'integer', minimum: 0, maximum: pixelHeight - 1 },
                left: { type: 'integer', minimum: 0, maximum: pixelWidth - 1 },
                bottom: { type: 'integer', minimum: 1, maximum: pixelHeight },
                right: { type: 'integer', minimum: 1, maximum: pixelWidth },
              },
              required: ['top', 'left', 'bottom', 'right'],
              additionalProperties: false,
            },
          },
          required: ['name', 'category', 'colors', 'boundingBox'],
          additionalProperties: false,
        },
      },
    },
    required: ['detections'],
    additionalProperties: false,
  } as const;
}

function detectionPrompt(pixelWidth: number, pixelHeight: number) {
  return `This image is exactly ${pixelWidth} pixels wide and ${pixelHeight} pixels high. Identify every distinct visible clothing item and wearable accessory in it.

Treat screenshots and product grids as multiple pictured instances. Return each separately pictured garment as its own proposal, even when the same product appears more than once. Never merge a main product image with thumbnails, recommendations, captions, or controls.

Return layered garments and small accessories separately. Do not infer hidden items or return brands, materials, tags, notes, masks, or polygons. Propose a concise visible-pixel-supported name and color list. Write every name in title case, capitalizing each meaningful word, for example "Black Wide-Leg Pants" or "Oversized Black Jacket with Faux-Fur Leopard Collar". Use category unsupported for a visible wearable outside the supported categories.

For every bounding box, locate the outermost visible pixels of exactly one garment. Use a tight box with at most 2% padding and exclude captions, controls, cards, background, and other garments. Use original image pixels in the standard order top, left, bottom, right. Top and bottom are pixel rows from 0 to ${pixelHeight}. Left and right are pixel columns from 0 to ${pixelWidth}. The origin is the image's top-left corner. Before responding, verify that the center of each box lies on its named garment and that the box does not group multiple pictured instances.`;
}

export const shelfImagePromptVersion = 'laid-flat-v4';

// Recorded on every attempt, so older rows keep the model that produced them.
// Flare emits 1536 output tokens against gpt-image-2's 6143 for the same
// high/816x816 request — same rate card, a quarter of the tokens, and it holds
// the flat chroma key more reliably on fuzzy edges.
export const shelfImageModel = 'gpt-image-2.5-flare';

export function buildShelfImagePrompt(metadata: ItemMetadata): string {
  const presentation =
    metadata.category === 'shoes'
      ? 'For a pair of shoes, show both shoes. Place the right shoe upright on its sole, facing upward in the composition so its top and opening are visible. Place the left shoe immediately to its left, laid on its outer side to show its side profile. Keep both shoes fully visible, at the same scale, and naturally paired.'
      : 'Present the garment laid flat, viewed straight from above, centered, with generous even padding.';
  return `Create a faithful e-commerce catalog presentation from the source image.

SUBJECT
- Show only the complete empty garment: ${metadata.name} (${metadata.category}; reviewed colors: ${metadata.colors.join(', ')}).
- Remove every person, body part, mannequin, hanger, tag string, prop, and surrounding object.
- ${presentation}
- Preserve the source-supported silhouette, proportions, color, pattern, seams, panels, hems, cuffs, collar, closures, pockets, trim, wear, and fabric behavior exactly.
- Reproduce the fabric's visible surface at full detail: weave or knit structure, pile, ribbing, quilting, jacquard or tonal motifs, sheen, and the exact repeat and scale of any pattern. A textured fabric must never be rendered as a flat, smooth surface, and a tonal pattern must stay visible even when it is close to the base color.
- Match collar shape, lapel roll, opening depth, and cuff or hem construction to the source rather than to a generic version of this garment type.
- Keep every brand mark that is visible on the garment in the source: logo, wordmark, emblem, embroidery, print, or woven label. Reproduce its exact wording, letterforms, colors, size relative to the garment, and position, and keep it as sharp as the source shows it. Never move a brand mark to a more typical spot, never enlarge it, and never replace it with a generic or invented mark.
- Construction must be supported by the source. Omit logos, labels, text, hardware, lining, reverse-side features, material claims, or decorative details that are hidden, illegible, ambiguous, or uncertain. An illegible mark stays out entirely rather than being rendered as approximate or garbled lettering.
- Where removing the wearer exposes an unseen area, use only the plainest continuation of source-supported fabric needed to make the empty item complete. Add no new seam, fold, fastening, texture, or design detail.

BACKGROUND
- Use one perfectly uniform, fully opaque chroma background across every non-garment pixel, with no floor line, texture, gradient, lighting variation, contact shadow, or cast shadow.
- Default to exact RGB #00ff00.
- If #00ff00 is present in the garment, use exact RGB #ff00ff instead, unless magenta is prominent in the garment.
- If both defaults conflict, choose the maximally distant saturated RGB key color.
- Never use a key color present anywhere in the garment.

OUTPUT
- One square shop-style product image. Garment only. No styling, border, watermark, or extra view, and no text beyond what is printed, woven, or embroidered on the garment itself.`;
}

function clampBox(
  box: z.infer<typeof detectionOutputSchema>['detections'][number]['boundingBox'],
  pixelWidth: number,
  pixelHeight: number,
): NormalizedBoundingBox {
  const x = Math.max(0, Math.min(999, Math.round((box.left / pixelWidth) * 1_000)));
  const y = Math.max(0, Math.min(999, Math.round((box.top / pixelHeight) * 1_000)));
  const right = Math.max(x + 1, Math.min(1_000, Math.round((box.right / pixelWidth) * 1_000)));
  const bottom = Math.max(y + 1, Math.min(1_000, Math.round((box.bottom / pixelHeight) * 1_000)));
  const width = right - x;
  const height = bottom - y;
  return { x, y, width, height };
}

function providerErrorFromResponse(status: number, body: unknown): CatalogProviderError {
  const providerCode =
    typeof body === 'object' && body !== null
      ? ((body as { error?: { code?: string; type?: string } }).error?.code ??
        (body as { error?: { type?: string } }).error?.type)
      : undefined;
  const message =
    typeof body === 'object' && body !== null
      ? ((body as { error?: { message?: string } }).error?.message ?? 'OpenAI request failed.')
      : 'OpenAI request failed.';
  if (providerCode === 'insufficient_quota') {
    return new CatalogProviderError('quota', message, false);
  }
  if (providerCode === 'content_policy_violation' || providerCode === 'moderation_blocked') {
    return new CatalogProviderError('moderation', message, false);
  }
  if (status === 401 || status === 403) {
    return new CatalogProviderError('authentication', message, false);
  }
  if (status === 408) return new CatalogProviderError('timeout', message, true);
  if (status === 429) return new CatalogProviderError('rate-limit', message, true);
  if (status >= 500) return new CatalogProviderError('provider-server', message, true);
  return new CatalogProviderError('validation', message, false);
}

async function readProviderResponse(response: Response): Promise<unknown> {
  try {
    return await response.json();
  } catch {
    throw new CatalogProviderError(
      'provider-server',
      'OpenAI returned a non-JSON response.',
      response.status >= 500,
    );
  }
}

function supportedImageType(bytes: Uint8Array): {
  mimeType: 'image/jpeg' | 'image/png' | 'image/webp';
  extension: 'jpg' | 'png' | 'webp';
} {
  if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff)
    return { mimeType: 'image/jpeg', extension: 'jpg' };
  if (
    bytes[0] === 0x89 &&
    bytes[1] === 0x50 &&
    bytes[2] === 0x4e &&
    bytes[3] === 0x47 &&
    bytes[4] === 0x0d &&
    bytes[5] === 0x0a &&
    bytes[6] === 0x1a &&
    bytes[7] === 0x0a
  )
    return { mimeType: 'image/png', extension: 'png' };
  if (
    bytes[0] === 0x52 &&
    bytes[1] === 0x49 &&
    bytes[2] === 0x46 &&
    bytes[3] === 0x46 &&
    bytes[8] === 0x57 &&
    bytes[9] === 0x45 &&
    bytes[10] === 0x42 &&
    bytes[11] === 0x50
  )
    return { mimeType: 'image/webp', extension: 'webp' };
  throw new CatalogProviderError(
    'validation',
    'An image reference uses an unsupported file format.',
    false,
  );
}

export class OpenAICatalogProvider implements CatalogProvider {
  constructor(
    private readonly apiKey: string,
    private readonly baseUrl = 'https://api.openai.com/v1',
  ) {}

  async detect(input: {
    jpegBytes: Uint8Array;
    model: string;
    signal?: AbortSignal;
  }): Promise<DetectionProviderResult> {
    const metadata = await sharp(input.jpegBytes).metadata();
    const pixelWidth = metadata.width;
    const pixelHeight = metadata.height;
    if (!pixelWidth || !pixelHeight) {
      throw new CatalogProviderError(
        'validation',
        'The source image dimensions could not be read.',
        false,
      );
    }
    let response: Response;
    try {
      response = await fetch(`${this.baseUrl}/responses`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${this.apiKey}`,
          'Content-Type': 'application/json',
        },
        signal: input.signal,
        body: JSON.stringify({
          model: input.model,
          store: false,
          input: [
            {
              role: 'user',
              content: [
                {
                  type: 'input_text',
                  text: detectionPrompt(pixelWidth, pixelHeight),
                },
                {
                  type: 'input_image',
                  image_url: `data:image/jpeg;base64,${Buffer.from(input.jpegBytes).toString('base64')}`,
                  detail: 'high',
                },
              ],
            },
          ],
          text: {
            format: {
              type: 'json_schema',
              name: 'garment_detections',
              strict: true,
              schema: detectionJsonSchema(pixelWidth, pixelHeight),
            },
          },
        }),
      });
    } catch (error) {
      if ((error as { name?: string }).name === 'AbortError') {
        throw new CatalogProviderError('timeout', 'OpenAI detection timed out.', true);
      }
      throw new CatalogProviderError('connection', 'OpenAI detection could not connect.', true);
    }
    const body = await readProviderResponse(response);
    if (!response.ok) throw providerErrorFromResponse(response.status, body);
    const raw = body as {
      id?: string;
      output_text?: string;
      status?: string;
      output?: Array<{ content?: Array<{ type?: string; text?: string }> }>;
    };
    if (raw.status && raw.status !== 'completed') {
      throw new CatalogProviderError('validation', 'OpenAI detection did not complete.', false);
    }
    let parsed;
    try {
      const outputText =
        raw.output_text ??
        raw.output
          ?.flatMap((item) => item.content ?? [])
          .find((content) => content.type === 'output_text')?.text;
      parsed = detectionOutputSchema.parse(JSON.parse(outputText ?? ''));
    } catch {
      throw new CatalogProviderError(
        'validation',
        'OpenAI detection did not match the strict garment schema.',
        false,
      );
    }
    const detections = parsed.detections.map((detection) =>
      garmentDetectionSchema.parse({
        id: randomUUID(),
        name: detection.name.trim().slice(0, 80),
        category: detection.category,
        colors: detection.colors
          .map((color) => color.trim().slice(0, 32))
          .filter(Boolean)
          .slice(0, 6),
        boundingBox: clampBox(detection.boundingBox, pixelWidth, pixelHeight),
      }),
    );
    return {
      requestId: raw.id ?? response.headers.get('x-request-id') ?? randomUUID(),
      detections,
    };
  }

  async generate(input: {
    referenceJpeg: Uint8Array;
    metadata: ItemMetadata;
    model: string;
    quality: GenerationQuality;
    size: '816x816';
    promptVersion: string;
    signal?: AbortSignal;
  }): Promise<GenerationProviderResult> {
    if (input.promptVersion !== shelfImagePromptVersion) {
      throw new CatalogProviderError('validation', 'Unknown Shelf Image prompt version.', false);
    }
    const form = new FormData();
    form.set('model', input.model);
    form.set('image', new Blob([input.referenceJpeg], { type: 'image/jpeg' }), 'reference.jpg');
    form.set('prompt', buildShelfImagePrompt(input.metadata));
    form.set('quality', input.quality);
    form.set('size', input.size);
    form.set('output_format', 'png');
    form.set('moderation', 'auto');
    let response: Response;
    try {
      response = await fetch(`${this.baseUrl}/images/edits`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${this.apiKey}` },
        body: form,
        signal: input.signal,
      });
    } catch (error) {
      if ((error as { name?: string }).name === 'AbortError') {
        throw new CatalogProviderError('timeout', 'OpenAI image editing timed out.', true);
      }
      throw new CatalogProviderError('connection', 'OpenAI image editing could not connect.', true);
    }
    const body = await readProviderResponse(response);
    if (!response.ok) throw providerErrorFromResponse(response.status, body);
    const raw = body as {
      id?: string;
      service_tier?: string;
      data?: Array<{ b64_json?: string }>;
      usage?: {
        input_tokens?: number;
        output_tokens?: number;
        input_tokens_details?: { text_tokens?: number; image_tokens?: number };
      };
    };
    const encoded = raw.data?.[0]?.b64_json;
    if (!encoded) {
      throw new CatalogProviderError('validation', 'OpenAI returned no edited image.', false);
    }
    if (
      raw.usage?.input_tokens_details?.text_tokens === undefined ||
      raw.usage.input_tokens_details.image_tokens === undefined ||
      raw.usage.output_tokens === undefined
    ) {
      throw new CatalogProviderError(
        'accounting',
        'OpenAI returned an image without the required usage ledger.',
        false,
      );
    }
    return {
      requestId: raw.id ?? response.headers.get('x-request-id') ?? randomUUID(),
      pngBytes: Buffer.from(encoded, 'base64'),
      usage: {
        textInputTokens: raw.usage.input_tokens_details.text_tokens,
        imageInputTokens: raw.usage.input_tokens_details.image_tokens,
        outputTokens: raw.usage.output_tokens,
        serviceTier: raw.service_tier ?? 'default',
        raw: raw.usage,
      },
    };
  }

  async planLook(input: {
    candidates: Array<{ id: string; metadata: ItemMetadata }>;
    recent: Array<{ itemIds: string[]; concept: LookConcept | null }>;
    exactItemIds: string[];
    categories: string[];
    occasion?: string | null;
    model: string;
    signal?: AbortSignal;
  }): Promise<{ requestId: string; itemIds: string[]; concept: LookConcept }> {
    const schema = {
      type: 'object',
      properties: {
        itemIds: {
          type: 'array',
          items: { type: 'string', enum: input.candidates.map(({ id }) => id) },
          minItems: 1,
          maxItems: 12,
        },
        concept: {
          type: 'object',
          properties: {
            activity: { type: 'string', maxLength: 300 },
            scene: { type: 'string', maxLength: 300 },
            framing: { type: 'string', enum: ['full-body', 'three-quarter'] },
            mood: { type: 'string', maxLength: 200 },
          },
          required: ['activity', 'scene', 'framing', 'mood'],
          additionalProperties: false,
        },
      },
      required: ['itemIds', 'concept'],
      additionalProperties: false,
    } as const;
    let response: Response;
    try {
      response = await fetch(`${this.baseUrl}/responses`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${this.apiKey}`,
          'Content-Type': 'application/json',
        },
        signal: input.signal,
        body: JSON.stringify({
          model: input.model,
          store: false,
          input: `Plan one coherent candid outfit photograph. Exact item IDs are mandatory. Satisfy every requested category. Build a complete outfit around the exact items, adding complementary pieces from the candidates. Match the requested occasion in both clothing and scene when provided. Avoid recent combinations and situations. Do not use weather, season or location context. Candidates: ${JSON.stringify(input.candidates)}. Exact: ${JSON.stringify(input.exactItemIds)}. Categories: ${JSON.stringify(input.categories)}. Occasion: ${JSON.stringify(input.occasion ?? null)}. Recent: ${JSON.stringify(input.recent)}.`,
          text: {
            format: {
              type: 'json_schema',
              name: 'look_plan',
              strict: true,
              schema,
            },
          },
        }),
      });
    } catch (error) {
      if ((error as { name?: string }).name === 'AbortError')
        throw new CatalogProviderError('timeout', 'OpenAI planning timed out.', true);
      throw new CatalogProviderError('connection', 'OpenAI planning could not connect.', true);
    }
    const body = await readProviderResponse(response);
    if (!response.ok) throw providerErrorFromResponse(response.status, body);
    const raw = body as {
      id?: string;
      output_text?: string;
      output?: Array<{ content?: Array<{ type?: string; text?: string }> }>;
    };
    try {
      const text =
        raw.output_text ??
        raw.output?.flatMap((o) => o.content ?? []).find((c) => c.type === 'output_text')?.text ??
        '';
      const parsed = z
        .object({
          itemIds: z.array(z.string()).min(1).max(12),
          concept: z
            .object({
              activity: z.string().min(1).max(300),
              scene: z.string().min(1).max(300),
              framing: z.enum(['full-body', 'three-quarter']),
              mood: z.string().min(1).max(200),
            })
            .strict(),
        })
        .strict()
        .parse(JSON.parse(text));
      const allowed = new Set(input.candidates.map(({ id }) => id));
      if (
        parsed.itemIds.some((id) => !allowed.has(id)) ||
        input.exactItemIds.some((id) => !parsed.itemIds.includes(id))
      )
        throw new Error();
      return {
        requestId: raw.id ?? response.headers.get('x-request-id') ?? randomUUID(),
        ...parsed,
      };
    } catch {
      throw new CatalogProviderError('validation', 'OpenAI returned an invalid Look plan.', false);
    }
  }

  async generateComposite(input: {
    references: Uint8Array[];
    prompt: string;
    model: string;
    quality: GenerationQuality;
    size: '864x1536' | '1024x1280';
    signal?: AbortSignal;
  }): Promise<GenerationProviderResult> {
    const form = new FormData();
    form.set('model', input.model);
    input.references.forEach((bytes, index) => {
      const { mimeType, extension } = supportedImageType(bytes);
      form.append(
        'image[]',
        new Blob([bytes], { type: mimeType }),
        `reference-${index + 1}.${extension}`,
      );
    });
    form.set('prompt', input.prompt);
    form.set('quality', input.quality);
    form.set('size', input.size);
    form.set('output_format', 'png');
    form.set('moderation', 'auto');
    let response: Response;
    try {
      response = await fetch(`${this.baseUrl}/images/edits`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${this.apiKey}` },
        body: form,
        signal: input.signal,
      });
    } catch (error) {
      if ((error as { name?: string }).name === 'AbortError')
        throw new CatalogProviderError('timeout', 'OpenAI image editing timed out.', true);
      throw new CatalogProviderError('connection', 'OpenAI image editing could not connect.', true);
    }
    const body = await readProviderResponse(response);
    if (!response.ok) throw providerErrorFromResponse(response.status, body);
    const raw = body as {
      id?: string;
      service_tier?: string;
      data?: Array<{ b64_json?: string }>;
      usage?: {
        output_tokens?: number;
        input_tokens_details?: { text_tokens?: number; image_tokens?: number };
      };
    };
    const encoded = raw.data?.[0]?.b64_json;
    const details = raw.usage?.input_tokens_details;
    if (!encoded)
      throw new CatalogProviderError('validation', 'OpenAI returned no edited image.', false);
    if (
      details?.text_tokens === undefined ||
      details.image_tokens === undefined ||
      raw.usage?.output_tokens === undefined
    )
      throw new CatalogProviderError(
        'accounting',
        'OpenAI returned an image without the required usage ledger.',
        false,
      );
    return {
      requestId: raw.id ?? response.headers.get('x-request-id') ?? randomUUID(),
      pngBytes: Buffer.from(encoded, 'base64'),
      usage: {
        textInputTokens: details.text_tokens,
        imageInputTokens: details.image_tokens,
        outputTokens: raw.usage.output_tokens,
        serviceTier: raw.service_tier ?? 'default',
        raw: raw.usage,
      },
    };
  }
}

export type ReplayCatalogFixture = {
  key: string;
  detection?: DetectionProviderResult;
  generation?: GenerationProviderResult;
  failure?: CatalogProviderError;
};

export class ReplayCatalogProvider implements CatalogProvider {
  private readonly fixtures: Map<string, ReplayCatalogFixture>;

  constructor(fixtures: ReplayCatalogFixture[]) {
    this.fixtures = new Map(fixtures.map((fixture) => [fixture.key, fixture]));
  }

  private fixture(key: string): ReplayCatalogFixture {
    const fixture = this.fixtures.get(key);
    if (!fixture) {
      throw new CatalogProviderError('validation', `Replay fixture ${key} is missing.`, false);
    }
    if (fixture.failure) throw fixture.failure;
    return fixture;
  }

  async detect(input: { model: string }): Promise<DetectionProviderResult> {
    const result = this.fixture(`detect:${input.model}`).detection;
    if (!result)
      throw new CatalogProviderError('validation', 'Replay detection is missing.', false);
    return structuredClone(result);
  }

  async generate(input: {
    model: string;
    quality: GenerationQuality;
  }): Promise<GenerationProviderResult> {
    const result = this.fixture(`generate:${input.model}:${input.quality}`).generation;
    if (!result)
      throw new CatalogProviderError('validation', 'Replay generation is missing.', false);
    return {
      ...structuredClone(result),
      pngBytes: Buffer.from(result.pngBytes),
    };
  }

  async planLook(input: {
    candidates: Array<{ id: string; metadata: ItemMetadata }>;
    exactItemIds: string[];
  }): Promise<{ requestId: string; itemIds: string[]; concept: LookConcept }> {
    const fixture = this.fixtures.get('plan:look');
    const planned = fixture as
      | (ReplayCatalogFixture & {
          plan?: { requestId: string; itemIds: string[]; concept: LookConcept };
        })
      | undefined;
    return structuredClone(
      planned?.plan ?? {
        requestId: 'replay-look-plan',
        itemIds: input.exactItemIds.length
          ? input.exactItemIds
          : input.candidates.slice(0, 3).map(({ id }) => id),
        concept: {
          activity: 'walking with a coffee',
          scene: 'a quiet street',
          framing: 'full-body',
          mood: 'relaxed',
        },
      },
    );
  }

  async generateComposite(input: {
    model: string;
    quality: GenerationQuality;
  }): Promise<GenerationProviderResult> {
    const result = this.fixture(`generate:${input.model}:${input.quality}`).generation;
    if (!result)
      throw new CatalogProviderError('validation', 'Replay generation is missing.', false);
    return {
      ...structuredClone(result),
      pngBytes: Buffer.from(result.pngBytes),
    };
  }
}

import { randomUUID } from 'node:crypto';

import {
  garmentDetectionSchema,
  type GarmentDetection,
  type GenerationQuality,
  type ItemMetadata,
  type NormalizedBoundingBox,
} from '@form/contracts';
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
            x: z.number(),
            y: z.number(),
            width: z.number(),
            height: z.number(),
          }),
        })
        .strict(),
    ),
  })
  .strict();

const detectionJsonSchema = {
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
          colors: { type: 'array', items: { type: 'string' }, minItems: 1, maxItems: 6 },
          boundingBox: {
            type: 'object',
            properties: {
              x: { type: 'integer', minimum: 0, maximum: 999 },
              y: { type: 'integer', minimum: 0, maximum: 999 },
              width: { type: 'integer', minimum: 1, maximum: 1000 },
              height: { type: 'integer', minimum: 1, maximum: 1000 },
            },
            required: ['x', 'y', 'width', 'height'],
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

const detectionPrompt = `Identify every distinct visible clothing item and wearable accessory in this image.

Return layered garments and small accessories separately. Do not infer hidden items, merge separate garments, or return brands, materials, tags, notes, masks, or polygons. Propose a concise visible-pixel-supported name and color list. Use category unsupported for a visible wearable outside the supported categories. Bounding boxes are integer coordinates in a normalized 1000 by 1000 frame and must contain the visible item.`;

export const shelfImagePromptVersion = 'laid-flat-v1';

export function buildShelfImagePrompt(metadata: ItemMetadata): string {
  return `Create a faithful e-commerce catalog presentation from the source image.

SUBJECT
- Show only the complete empty garment: ${metadata.name} (${metadata.category}; reviewed colors: ${metadata.colors.join(', ')}).
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
- One square shop-style product image. Garment only. No styling, text, border, watermark, or extra view.`;
}

function clampBox(box: z.infer<typeof detectionOutputSchema>['detections'][number]['boundingBox']): NormalizedBoundingBox {
  const x = Math.max(0, Math.min(999, Math.round(box.x)));
  const y = Math.max(0, Math.min(999, Math.round(box.y)));
  const width = Math.max(1, Math.min(1_000 - x, Math.round(box.width)));
  const height = Math.max(1, Math.min(1_000 - y, Math.round(box.height)));
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
                { type: 'input_text', text: detectionPrompt },
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
              schema: detectionJsonSchema,
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
        colors: detection.colors.map((color) => color.trim().slice(0, 32)).filter(Boolean).slice(0, 6),
        boundingBox: clampBox(detection.boundingBox),
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
    if (!result) throw new CatalogProviderError('validation', 'Replay detection is missing.', false);
    return structuredClone(result);
  }

  async generate(input: {
    model: string;
    quality: GenerationQuality;
  }): Promise<GenerationProviderResult> {
    const result = this.fixture(`generate:${input.model}:${input.quality}`).generation;
    if (!result) throw new CatalogProviderError('validation', 'Replay generation is missing.', false);
    return { ...structuredClone(result), pngBytes: Buffer.from(result.pngBytes) };
  }
}

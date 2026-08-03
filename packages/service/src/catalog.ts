import { createHash, randomUUID } from 'node:crypto';

import { GetObjectCommand, PutObjectCommand } from '@aws-sdk/client-s3';
import type { GenerationQuality, ItemMetadata, NormalizedBoundingBox } from '@form/contracts';
import sharp from 'sharp';
import { z } from 'zod';

import { cropGenerationReference, normalizeSourceForProvider, removeValidatedChromaBackground } from './catalog-images.js';
import {
  CatalogProviderError,
  type CatalogProvider,
  type ProviderFailureCategory,
} from './catalog-provider.js';
import type { Database } from './database.js';
import { withTransaction } from './database.js';
import { enqueueJob, type RemoteImageJob } from './jobs.js';
import { IdempotencyConflictError, OwnedResourceNotFoundError } from './media.js';
import type { PrivateObjectStorage } from './storage.js';
import {
  completeGenerationAttempt,
  failGenerationAttempt,
  recordDetectionProposals,
  startGenerationAttempt,
} from './wardrobe.js';

export type CatalogPricing = {
  effectiveDate: string;
  textInputMicrodollarsPerMillion: number;
  imageInputMicrodollarsPerMillion: number;
  imageOutputMicrodollarsPerMillion: number;
};

export type CatalogExecutionConfig = {
  detectionModel: string;
  pricing: CatalogPricing;
  requestTimeoutMs: number;
};

export class CatalogJobError extends Error {
  constructor(
    readonly category: ProviderFailureCategory | 'conversion' | 'chroma-validation' | 'internal',
    message: string,
    readonly retryable: boolean,
  ) {
    super(message);
    this.name = 'CatalogJobError';
  }
}

function commandHash(value: unknown): string {
  return createHash('sha256').update(JSON.stringify(value)).digest('hex');
}

export async function enqueueSourcePhotoDetection(
  database: Database,
  input: {
    accountId: string;
    sourcePhotoId: string;
    model: string;
    idempotencyKey: string;
  },
): Promise<{ jobId: string; detectionAttemptId: string }> {
  const request = { sourcePhotoId: input.sourcePhotoId, model: input.model };
  return withTransaction(database, async (client) => {
    await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [
      `${input.accountId}:${input.idempotencyKey}`,
    ]);
    const replay = await client.query<{
      command_kind: string;
      request_hash: string;
      response_body: { jobId: string; detectionAttemptId: string };
    }>(
      `SELECT command_kind, request_hash, response_body FROM idempotency_commands
       WHERE account_id = $1 AND key = $2`,
      [input.accountId, input.idempotencyKey],
    );
    if (replay.rows[0]) {
      if (
        replay.rows[0].command_kind !== 'enqueue-source-photo-detection' ||
        replay.rows[0].request_hash !== commandHash(request)
      ) {
        throw new IdempotencyConflictError();
      }
      return replay.rows[0].response_body;
    }

    const source = await client.query(
      `SELECT 1 FROM source_photos WHERE id = $1 AND account_id = $2 FOR UPDATE`,
      [input.sourcePhotoId, input.accountId],
    );
    if (!source.rows[0]) throw new OwnedResourceNotFoundError();
    const detectionAttemptId = randomUUID();
    await client.query(
      `INSERT INTO detection_attempts (id, account_id, source_photo_id, state, model)
       VALUES ($1, $2, $3, 'queued', $4)`,
      [detectionAttemptId, input.accountId, input.sourcePhotoId, input.model],
    );
    const jobId = await enqueueJob(client, {
      accountId: input.accountId,
      kind: 'detect-source-photo',
      payload: { sourcePhotoId: input.sourcePhotoId, detectionAttemptId },
      idempotencyKey: `detection:${input.idempotencyKey}`,
    });
    const body = { jobId, detectionAttemptId };
    await client.query(
      `INSERT INTO idempotency_commands (
         account_id, key, command_kind, request_hash, response_status, response_body, expires_at
       ) VALUES ($1, $2, 'enqueue-source-photo-detection', $3, 200, $4, now() + interval '7 days')`,
      [input.accountId, input.idempotencyKey, commandHash(request), JSON.stringify(body)],
    );
    return body;
  });
}

type ReadyAssetRow = {
  id: string;
  object_key: string;
  object_version_id: string;
  content_type: string;
};

async function readAsset(
  database: Database,
  storage: PrivateObjectStorage,
  accountId: string,
  assetId: string,
): Promise<Buffer> {
  const result = await database.query<ReadyAssetRow>(
    `SELECT id, object_key, object_version_id, content_type FROM private_assets
     WHERE id = $1 AND account_id = $2 AND state = 'ready'`,
    [assetId, accountId],
  );
  const asset = result.rows[0];
  if (!asset?.object_version_id) throw new OwnedResourceNotFoundError();
  const object = await storage.client.send(
    new GetObjectCommand({
      Bucket: storage.bucket,
      Key: asset.object_key,
      VersionId: asset.object_version_id,
    }),
  );
  const bytes = await object.Body?.transformToByteArray();
  if (!bytes) throw new CatalogJobError('internal', 'A private image asset is empty.', false);
  return Buffer.from(bytes);
}

async function writeAsset(
  database: Database,
  storage: PrivateObjectStorage,
  input: {
    accountId: string;
    purpose: 'generation-reference' | 'shelf-image-keyed' | 'shelf-image-transparent';
    bytes: Uint8Array;
    contentType: 'image/jpeg' | 'image/png';
    width: number;
    height: number;
  },
): Promise<string> {
  const assetId = randomUUID();
  const objectKey = `accounts/${input.accountId}/catalog/${input.purpose}/${assetId}`;
  const result = await storage.client.send(
    new PutObjectCommand({
      Bucket: storage.bucket,
      Key: objectKey,
      Body: input.bytes,
      ContentType: input.contentType,
      ContentLength: input.bytes.byteLength,
    }),
  );
  if (!result.VersionId) {
    throw new CatalogJobError('internal', 'Object storage did not version a catalog asset.', false);
  }
  await database.query(
    `INSERT INTO private_assets (
       id, account_id, purpose, object_key, object_version_id, content_type, byte_size,
       pixel_width, pixel_height, state, ready_at
     ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'ready', now())`,
    [
      assetId,
      input.accountId,
      input.purpose,
      objectKey,
      result.VersionId,
      input.contentType,
      input.bytes.byteLength,
      input.width,
      input.height,
    ],
  );
  return assetId;
}

const detectionPayloadSchema = z.object({
  sourcePhotoId: z.uuid(),
  detectionAttemptId: z.uuid(),
});
const generationPayloadSchema = z.object({ generationAttemptId: z.uuid() });

async function sourceAssetId(
  database: Database,
  accountId: string,
  sourcePhotoId: string,
): Promise<string> {
  const result = await database.query<{ asset_id: string }>(
    `SELECT asset_id FROM source_photos WHERE id = $1 AND account_id = $2`,
    [sourcePhotoId, accountId],
  );
  if (!result.rows[0]) throw new OwnedResourceNotFoundError();
  return result.rows[0].asset_id;
}

async function executeDetection(
  database: Database,
  storage: PrivateObjectStorage,
  provider: CatalogProvider,
  job: RemoteImageJob,
  config: CatalogExecutionConfig,
): Promise<void> {
  const payload = detectionPayloadSchema.parse(job.payload);
  const started = await database.query<{ model: string }>(
    `UPDATE detection_attempts SET state = 'processing', started_at = COALESCE(started_at, now())
     WHERE id = $1 AND account_id = $2 AND state IN ('queued', 'processing') RETURNING model`,
    [payload.detectionAttemptId, job.accountId],
  );
  if (!started.rows[0]) {
    const completed = await database.query(
      `SELECT 1 FROM detection_attempts
       WHERE id = $1 AND account_id = $2 AND state = 'succeeded'`,
      [payload.detectionAttemptId, job.accountId],
    );
    if (completed.rows[0]) return;
    throw new CatalogJobError('internal', 'The detection attempt cannot be started.', false);
  }
  const assetId = await sourceAssetId(database, job.accountId, payload.sourcePhotoId);
  const sourceBytes = await readAsset(database, storage, job.accountId, assetId);
  const normalized = await normalizeSourceForProvider(sourceBytes);
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), config.requestTimeoutMs);
  try {
    const result = await provider.detect({
      jpegBytes: normalized,
      model: started.rows[0].model,
      signal: controller.signal,
    });
    await recordDetectionProposals(database, {
      accountId: job.accountId,
      sourcePhotoId: payload.sourcePhotoId,
      detections: result.detections,
    });
    await database.query(
      `UPDATE detection_attempts SET state = 'succeeded', provider_request_id = $3,
         finished_at = now() WHERE id = $1 AND account_id = $2 AND state = 'processing'`,
      [payload.detectionAttemptId, job.accountId, result.requestId],
    );
  } finally {
    clearTimeout(timer);
  }
}

type GenerationInputRow = {
  source_photo_id: string;
  reviewed_metadata: ItemMetadata;
  model: string;
  quality: GenerationQuality;
  output_size: '816x816';
  prompt_version: string;
  bounding_box: NormalizedBoundingBox | null;
};

function componentCost(tokens: number, rate: number): number {
  return Number((BigInt(tokens) * BigInt(rate) + 999_999n) / 1_000_000n);
}

export function calculateCostLedger(
  usage: { textInputTokens: number; imageInputTokens: number; outputTokens: number },
  pricing: CatalogPricing,
): {
  textInputMicrounits: number;
  imageInputMicrounits: number;
  imageOutputMicrounits: number;
  totalMicrounits: number;
} {
  const textInputMicrounits = componentCost(
    usage.textInputTokens,
    pricing.textInputMicrodollarsPerMillion,
  );
  const imageInputMicrounits = componentCost(
    usage.imageInputTokens,
    pricing.imageInputMicrodollarsPerMillion,
  );
  const imageOutputMicrounits = componentCost(
    usage.outputTokens,
    pricing.imageOutputMicrodollarsPerMillion,
  );
  const totalMicrounits =
    textInputMicrounits + imageInputMicrounits + imageOutputMicrounits;
  if (!Number.isSafeInteger(totalMicrounits)) {
    throw new CatalogJobError('internal', 'The calculated request cost is out of range.', false);
  }
  return {
    textInputMicrounits,
    imageInputMicrounits,
    imageOutputMicrounits,
    totalMicrounits,
  };
}

export function calculateCostMicrounits(
  usage: { textInputTokens: number; imageInputTokens: number; outputTokens: number },
  pricing: CatalogPricing,
): number {
  return calculateCostLedger(usage, pricing).totalMicrounits;
}

async function executeGeneration(
  database: Database,
  storage: PrivateObjectStorage,
  provider: CatalogProvider,
  job: RemoteImageJob,
  config: CatalogExecutionConfig,
): Promise<void> {
  const payload = generationPayloadSchema.parse(job.payload);
  const existing = await database.query<{ state: string }>(
    `SELECT state FROM generation_attempts WHERE id = $1 AND account_id = $2`,
    [payload.generationAttemptId, job.accountId],
  );
  if (existing.rows[0]?.state === 'needs-review' || existing.rows[0]?.state === 'kept') return;
  const started = await startGenerationAttempt(database, {
    accountId: job.accountId,
    generationAttemptId: payload.generationAttemptId,
  });
  if (!started) {
    throw new CatalogJobError('internal', 'The generation attempt cannot be started.', false);
  }
  const attempt = await database.query<GenerationInputRow>(
    `SELECT attempts.source_photo_id, attempts.reviewed_metadata, attempts.model,
       attempts.quality, attempts.output_size, attempts.prompt_version,
       proposals.bounding_box
     FROM generation_attempts attempts
     LEFT JOIN detection_proposals proposals ON proposals.id = attempts.detection_proposal_id
     WHERE attempts.id = $1 AND attempts.account_id = $2`,
    [payload.generationAttemptId, job.accountId],
  );
  const input = attempt.rows[0];
  if (!input) throw new OwnedResourceNotFoundError();
  const assetId = await sourceAssetId(database, job.accountId, input.source_photo_id);
  const sourceBytes = await readAsset(database, storage, job.accountId, assetId);
  const normalized = await normalizeSourceForProvider(sourceBytes);
  const reference = await cropGenerationReference(
    normalized,
    input.bounding_box ?? { x: 0, y: 0, width: 1_000, height: 1_000 },
  );
  const referenceMetadata = await sharp(reference).metadata();
  const referenceAssetId = await writeAsset(database, storage, {
    accountId: job.accountId,
    purpose: 'generation-reference',
    bytes: reference,
    contentType: 'image/jpeg',
    width: referenceMetadata.width ?? 1,
    height: referenceMetadata.height ?? 1,
  });
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), config.requestTimeoutMs);
  try {
    const result = await provider.generate({
      referenceJpeg: reference,
      metadata: input.reviewed_metadata,
      model: input.model,
      quality: input.quality,
      size: input.output_size,
      promptVersion: input.prompt_version,
      signal: controller.signal,
    });
    const processed = await removeValidatedChromaBackground(result.pngBytes);
    const keyedAssetId = await writeAsset(database, storage, {
      accountId: job.accountId,
      purpose: 'shelf-image-keyed',
      bytes: result.pngBytes,
      contentType: 'image/png',
      width: 816,
      height: 816,
    });
    const transparentAssetId = await writeAsset(database, storage, {
      accountId: job.accountId,
      purpose: 'shelf-image-transparent',
      bytes: processed.transparentPng,
      contentType: 'image/png',
      width: 816,
      height: 816,
    });
    const cost = calculateCostLedger(result.usage, config.pricing);
    const completed = await completeGenerationAttempt(database, {
      accountId: job.accountId,
      generationAttemptId: payload.generationAttemptId,
      referenceAssetId,
      keyedAssetId,
      transparentAssetId,
      resolvedChromaKey: processed.resolvedChromaKey,
      providerRequestId: result.requestId,
      inputTokens: result.usage.textInputTokens + result.usage.imageInputTokens,
      textInputTokens: result.usage.textInputTokens,
      imageInputTokens: result.usage.imageInputTokens,
      outputTokens: result.usage.outputTokens,
      capturedRates: config.pricing,
      costMicrounits: cost.totalMicrounits,
      textInputCostMicrounits: cost.textInputMicrounits,
      imageInputCostMicrounits: cost.imageInputMicrounits,
      imageOutputCostMicrounits: cost.imageOutputMicrounits,
      serviceTier: result.usage.serviceTier,
      pricingEffectiveDate: config.pricing.effectiveDate,
      providerUsage: result.usage.raw,
    });
    if (!completed) {
      throw new CatalogJobError('internal', 'The generation result could not be persisted.', false);
    }
  } finally {
    clearTimeout(timer);
  }
}

export async function executeCatalogJob(
  database: Database,
  storage: PrivateObjectStorage,
  provider: CatalogProvider,
  job: RemoteImageJob,
  config: CatalogExecutionConfig,
): Promise<void> {
  try {
    if (job.kind === 'detect-source-photo') {
      await executeDetection(database, storage, provider, job, config);
    } else {
      await executeGeneration(database, storage, provider, job, config);
    }
  } catch (error) {
    if (error instanceof CatalogJobError) throw error;
    if (error instanceof CatalogProviderError) {
      throw new CatalogJobError(error.category, error.message, error.retryable);
    }
    const category = (error as { category?: string }).category;
    if (category === 'conversion' || category === 'chroma-validation') {
      throw new CatalogJobError(category, (error as Error).message, false);
    }
    if (error instanceof z.ZodError) {
      throw new CatalogJobError('validation', 'The durable job payload is invalid.', false);
    }
    throw new CatalogJobError('internal', (error as Error).message, false);
  }
}

export async function failCatalogAttempt(
  database: Database,
  job: RemoteImageJob,
  error: CatalogJobError,
): Promise<void> {
  if (job.kind === 'generate-shelf-image' && job.generationAttemptId) {
    await failGenerationAttempt(database, {
      accountId: job.accountId,
      generationAttemptId: job.generationAttemptId,
      failureCategory: error.category,
      failureDetail: error.message,
    });
    return;
  }
  const parsed = detectionPayloadSchema.safeParse(job.payload);
  if (parsed.success) {
    await database.query(
      `UPDATE detection_attempts SET state = 'failed', failure_category = $3,
         failure_detail = $4, finished_at = now()
       WHERE id = $1 AND account_id = $2 AND state IN ('queued', 'processing')`,
      [parsed.data.detectionAttemptId, job.accountId, error.category, error.message],
    );
  }
}

export const catalogFixtureCoverage = [
  'simple-isolated-top',
  'patterned-garment',
  'green-garment-non-green-key',
  'magenta-garment-third-key',
  'layered-outerwear',
  'cropped-pants-or-dress',
  'dark-on-dark',
  'two-same-category-garments',
  'shoes-and-bag',
  'unsupported-wearable',
  'heic-orientation',
  'non-uniform-background',
  'missing-usage-ledger',
  'low-quality',
  'medium-quality',
  'high-quality',
] as const;

import { createHash, randomUUID } from 'node:crypto';

import { DeleteObjectsCommand, ListObjectVersionsCommand } from '@aws-sdk/client-s3';
import type {
  DetectionProposal,
  GarmentDetection,
  GenerationAttempt,
  GenerationQuality,
  ItemMetadata,
  ItemState,
  ShelfImageVersion,
  SourcePhoto,
  WardrobeItem,
} from '@form/contracts';

import type { Database, DatabaseClient } from './database.js';
import { withTransaction } from './database.js';
import { enqueueJob } from './jobs.js';
import { IdempotencyConflictError, OwnedResourceNotFoundError } from './media.js';
import type { PrivateObjectStorage } from './storage.js';

type Queryable = Pick<Database, 'query'> | Pick<DatabaseClient, 'query'>;

export class StaleRecordVersionError extends Error {
  constructor() {
    super('The Wardrobe Item changed on another device. Refresh it before trying again.');
    this.name = 'StaleRecordVersionError';
  }
}

export class InvalidWardrobeTransitionError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'InvalidWardrobeTransitionError';
  }
}

type WardrobeItemRow = {
  id: string;
  source_photo_id: string;
  state: WardrobeItem['state'];
  status: WardrobeItem['status'];
  name: string;
  category: WardrobeItem['metadata']['category'];
  colors: string[];
  notes: string | null;
  current_shelf_image_version_id: string | null;
  record_version: number;
  created_at: Date;
  updated_at: Date;
};

type DetectionRow = {
  id: string;
  source_photo_id: string;
  name: string;
  category: DetectionProposal['category'];
  colors: string[];
  bounding_box: DetectionProposal['boundingBox'];
  created_at: Date;
};

type GenerationAttemptRow = {
  id: string;
  wardrobe_item_id: string;
  source_photo_id: string;
  detection_proposal_id: string | null;
  state: GenerationAttempt['state'];
  reviewed_metadata: ItemMetadata;
  model: string;
  quality: GenerationAttempt['quality'];
  output_size: GenerationAttempt['size'];
  prompt_version: string;
  keyed_asset_id: string | null;
  transparent_asset_id: string | null;
  provider_request_id: string | null;
  text_input_tokens: number | null;
  image_input_tokens: number | null;
  output_tokens: number | null;
  service_tier: string | null;
  pricing_effective_date: string | null;
  text_input_cost_microunits: string | null;
  image_input_cost_microunits: string | null;
  image_output_cost_microunits: string | null;
  cost_microunits: string | null;
  failure_category: string | null;
  created_at: Date;
  finished_at: Date | null;
};

type ShelfImageVersionRow = {
  id: string;
  wardrobe_item_id: string;
  generation_attempt_id: string;
  keyed_asset_id: string;
  transparent_asset_id: string;
  quality: ShelfImageVersion['quality'];
  output_size: ShelfImageVersion['size'];
  prompt_version: string;
  kept_at: Date;
};

function mapWardrobeItem(row: WardrobeItemRow): WardrobeItem {
  return {
    id: row.id,
    sourcePhotoId: row.source_photo_id,
    state: row.state,
    status: row.status,
    metadata: {
      name: row.name,
      category: row.category,
      colors: row.colors,
      notes: row.notes,
    },
    currentShelfImageVersionId: row.current_shelf_image_version_id,
    recordVersion: row.record_version,
    createdAt: row.created_at.toISOString(),
    updatedAt: row.updated_at.toISOString(),
  };
}

function mapDetection(row: DetectionRow): DetectionProposal {
  return {
    id: row.id,
    sourcePhotoId: row.source_photo_id,
    name: row.name,
    category: row.category,
    colors: row.colors,
    boundingBox: row.bounding_box,
    createdAt: row.created_at.toISOString(),
  };
}

function mapGenerationAttempt(row: GenerationAttemptRow): GenerationAttempt {
  return {
    id: row.id,
    wardrobeItemId: row.wardrobe_item_id,
    sourcePhotoId: row.source_photo_id,
    detectionProposalId: row.detection_proposal_id,
    state: row.state,
    reviewedMetadata: row.reviewed_metadata,
    model: row.model,
    quality: row.quality,
    size: row.output_size,
    promptVersion: row.prompt_version,
    keyedAssetId: row.keyed_asset_id,
    transparentAssetId: row.transparent_asset_id,
    providerRequestId: row.provider_request_id,
    costMicrounits: row.cost_microunits === null ? null : Number(row.cost_microunits),
    usage:
      row.text_input_tokens === null ||
      row.image_input_tokens === null ||
      row.output_tokens === null ||
      row.service_tier === null
        ? null
        : {
            textInputTokens: row.text_input_tokens,
            imageInputTokens: row.image_input_tokens,
            outputTokens: row.output_tokens,
            serviceTier: row.service_tier,
          },
    costBreakdown:
      row.text_input_cost_microunits === null ||
      row.image_input_cost_microunits === null ||
      row.image_output_cost_microunits === null ||
      row.cost_microunits === null ||
      row.pricing_effective_date === null
        ? null
        : {
            textInputMicrounits: Number(row.text_input_cost_microunits),
            imageInputMicrounits: Number(row.image_input_cost_microunits),
            imageOutputMicrounits: Number(row.image_output_cost_microunits),
            totalMicrounits: Number(row.cost_microunits),
            pricingEffectiveDate: row.pricing_effective_date,
          },
    failureCategory: row.failure_category,
    createdAt: row.created_at.toISOString(),
    finishedAt: row.finished_at?.toISOString() ?? null,
  };
}

function mapShelfImageVersion(row: ShelfImageVersionRow): ShelfImageVersion {
  return {
    id: row.id,
    wardrobeItemId: row.wardrobe_item_id,
    generationAttemptId: row.generation_attempt_id,
    keyedAssetId: row.keyed_asset_id,
    transparentAssetId: row.transparent_asset_id,
    quality: row.quality,
    size: row.output_size,
    promptVersion: row.prompt_version,
    keptAt: row.kept_at.toISOString(),
  };
}

const itemColumns = `id, source_photo_id, state, status, name, category, colors, notes,
  current_shelf_image_version_id, record_version, created_at, updated_at`;
const attemptColumns = `id, wardrobe_item_id, source_photo_id, detection_proposal_id, state,
  reviewed_metadata, model, quality, output_size, prompt_version, keyed_asset_id,
  transparent_asset_id, provider_request_id, text_input_tokens, image_input_tokens,
  output_tokens, service_tier, pricing_effective_date::text AS pricing_effective_date,
  text_input_cost_microunits,
  image_input_cost_microunits, image_output_cost_microunits, cost_microunits, failure_category,
  created_at, finished_at`;
const versionColumns = `id, wardrobe_item_id, generation_attempt_id, keyed_asset_id,
  transparent_asset_id, quality, output_size, prompt_version, kept_at`;

function commandHash(value: unknown): string {
  return createHash('sha256').update(JSON.stringify(value)).digest('hex');
}

type CommandReplay<T> = { replayed: true; body: T } | { replayed: false };

async function beginCommand<T>(
  client: DatabaseClient,
  input: { accountId: string; key: string; kind: string; request: unknown },
): Promise<CommandReplay<T>> {
  await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [
    `${input.accountId}:${input.key}`,
  ]);
  const requestHash = commandHash(input.request);
  const existing = await client.query<{
    command_kind: string;
    request_hash: string;
    response_body: T;
  }>(
    `SELECT command_kind, request_hash, response_body
     FROM idempotency_commands WHERE account_id = $1 AND key = $2`,
    [input.accountId, input.key],
  );
  const row = existing.rows[0];
  if (!row) return { replayed: false };
  if (row.command_kind !== input.kind || row.request_hash !== requestHash) {
    throw new IdempotencyConflictError();
  }
  return { replayed: true, body: row.response_body };
}

async function finishCommand(
  client: DatabaseClient,
  input: { accountId: string; key: string; kind: string; request: unknown; body: unknown },
): Promise<void> {
  await client.query(
    `INSERT INTO idempotency_commands (
       account_id, key, command_kind, request_hash, response_status, response_body, expires_at
     ) VALUES ($1, $2, $3, $4, 200, $5, now() + interval '7 days')`,
    [input.accountId, input.key, input.kind, commandHash(input.request), JSON.stringify(input.body)],
  );
}

export async function listWardrobeItems(
  database: Queryable,
  input: { accountId: string; state?: ItemState },
): Promise<WardrobeItem[]> {
  const result = await database.query<WardrobeItemRow>(
    `SELECT ${itemColumns} FROM wardrobe_items
     WHERE account_id = $1 AND deleted_at IS NULL
       AND ($2::text IS NULL OR state = $2)
     ORDER BY updated_at DESC, id`,
    [input.accountId, input.state ?? null],
  );
  return result.rows.map(mapWardrobeItem);
}

export async function findWardrobeItem(
  database: Queryable,
  accountId: string,
  wardrobeItemId: string,
): Promise<WardrobeItem | null> {
  const result = await database.query<WardrobeItemRow>(
    `SELECT ${itemColumns} FROM wardrobe_items
     WHERE id = $1 AND account_id = $2 AND deleted_at IS NULL`,
    [wardrobeItemId, accountId],
  );
  return result.rows[0] ? mapWardrobeItem(result.rows[0]) : null;
}

export async function getWardrobeItemDetail(
  database: Queryable,
  input: { accountId: string; wardrobeItemId: string },
): Promise<{
  wardrobeItem: WardrobeItem;
  sourcePhoto: SourcePhoto;
  shelfImageVersions: ShelfImageVersion[];
  generationAttempts: GenerationAttempt[];
} | null> {
  const item = await findWardrobeItem(database, input.accountId, input.wardrobeItemId);
  if (!item) return null;
  const [source, versions, attempts] = await Promise.all([
    database.query<{ id: string; asset_id: string; created_at: Date }>(
      `SELECT id, asset_id, created_at FROM source_photos WHERE id = $1 AND account_id = $2`,
      [item.sourcePhotoId, input.accountId],
    ),
    database.query<ShelfImageVersionRow>(
      `SELECT ${versionColumns} FROM shelf_image_versions
       WHERE wardrobe_item_id = $1 AND account_id = $2 ORDER BY kept_at DESC`,
      [input.wardrobeItemId, input.accountId],
    ),
    database.query<GenerationAttemptRow>(
      `SELECT ${attemptColumns} FROM generation_attempts
       WHERE wardrobe_item_id = $1 AND account_id = $2 ORDER BY created_at DESC`,
      [input.wardrobeItemId, input.accountId],
    ),
  ]);
  const sourceRow = source.rows[0];
  if (!sourceRow) return null;
  return {
    wardrobeItem: item,
    sourcePhoto: {
      id: sourceRow.id,
      assetId: sourceRow.asset_id,
      createdAt: sourceRow.created_at.toISOString(),
    },
    shelfImageVersions: versions.rows.map(mapShelfImageVersion),
    generationAttempts: attempts.rows.map(mapGenerationAttempt),
  };
}

export async function listDetectionProposals(
  database: Queryable,
  input: { accountId: string; sourcePhotoId: string },
): Promise<DetectionProposal[] | null> {
  const source = await database.query(
    `SELECT 1 FROM source_photos WHERE id = $1 AND account_id = $2`,
    [input.sourcePhotoId, input.accountId],
  );
  if (!source.rows[0]) return null;
  const result = await database.query<DetectionRow>(
    `SELECT id, source_photo_id, name, category, colors, bounding_box, created_at
     FROM detection_proposals WHERE source_photo_id = $1 AND account_id = $2
     ORDER BY created_at, id`,
    [input.sourcePhotoId, input.accountId],
  );
  return result.rows.map(mapDetection);
}

export async function getLatestDetectionAttempt(
  database: Queryable,
  input: { accountId: string; sourcePhotoId: string },
): Promise<{
  id: string;
  sourcePhotoId: string;
  state: 'queued' | 'processing' | 'succeeded' | 'failed';
  model: string;
  failureCategory: string | null;
  createdAt: string;
  finishedAt: string | null;
} | null> {
  const result = await database.query<{
    id: string;
    source_photo_id: string;
    state: 'queued' | 'processing' | 'succeeded' | 'failed';
    model: string;
    failure_category: string | null;
    created_at: Date;
    finished_at: Date | null;
  }>(
    `SELECT id, source_photo_id, state, model, failure_category, created_at, finished_at
     FROM detection_attempts
     WHERE source_photo_id = $1 AND account_id = $2
     ORDER BY created_at DESC, id DESC LIMIT 1`,
    [input.sourcePhotoId, input.accountId],
  );
  const row = result.rows[0];
  return row
    ? {
        id: row.id,
        sourcePhotoId: row.source_photo_id,
        state: row.state,
        model: row.model,
        failureCategory: row.failure_category,
        createdAt: row.created_at.toISOString(),
        finishedAt: row.finished_at?.toISOString() ?? null,
      }
    : null;
}

export async function recordDetectionProposals(
  database: Database,
  input: { accountId: string; sourcePhotoId: string; detections: GarmentDetection[] },
): Promise<DetectionProposal[]> {
  return withTransaction(database, async (client) => {
    const source = await client.query(
      `SELECT 1 FROM source_photos WHERE id = $1 AND account_id = $2 FOR UPDATE`,
      [input.sourcePhotoId, input.accountId],
    );
    if (!source.rows[0]) throw new OwnedResourceNotFoundError();
    for (const detection of input.detections) {
      await client.query(
        `INSERT INTO detection_proposals (
           id, account_id, source_photo_id, name, category, colors, bounding_box
         ) VALUES ($1, $2, $3, $4, $5, $6, $7)
         ON CONFLICT (id) DO NOTHING`,
        [
          detection.id,
          input.accountId,
          input.sourcePhotoId,
          detection.name,
          detection.category,
          detection.colors,
          JSON.stringify(detection.boundingBox),
        ],
      );
    }
    return (await listDetectionProposals(client, input)) ?? [];
  });
}

export async function createWardrobeItemFromDetection(
  database: Database,
  input: {
    accountId: string;
    detectionProposalId: string;
    state: Exclude<ItemState, 'archived'>;
    metadata?: ItemMetadata;
    idempotencyKey: string;
  },
): Promise<WardrobeItem> {
  const request = {
    detectionProposalId: input.detectionProposalId,
    state: input.state,
    metadata: input.metadata,
  };
  return withTransaction(database, async (client) => {
    const replay = await beginCommand<WardrobeItem>(client, {
      accountId: input.accountId,
      key: input.idempotencyKey,
      kind: 'create-wardrobe-item',
      request,
    });
    if (replay.replayed) return replay.body;
    const proposal = await client.query<DetectionRow>(
      `SELECT id, source_photo_id, name, category, colors, bounding_box, created_at
       FROM detection_proposals WHERE id = $1 AND account_id = $2`,
      [input.detectionProposalId, input.accountId],
    );
    const detection = proposal.rows[0];
    if (!detection) throw new OwnedResourceNotFoundError();
    if (detection.category === 'unsupported' && !input.metadata) {
      throw new InvalidWardrobeTransitionError(
        'Choose a supported category before creating this Wardrobe Item.',
      );
    }
    const metadata = input.metadata ?? {
      name: detection.name,
      category: detection.category as ItemMetadata['category'],
      colors: detection.colors,
      notes: null,
    };
    const result = await client.query<WardrobeItemRow>(
      `INSERT INTO wardrobe_items (
         id, account_id, source_photo_id, detection_proposal_id, state, status,
         name, category, colors, notes
       ) VALUES ($1, $2, $3, $4, $5, 'reviewing-metadata', $6, $7, $8, $9)
       RETURNING ${itemColumns}`,
      [
        randomUUID(),
        input.accountId,
        detection.source_photo_id,
        detection.id,
        input.state,
        metadata.name,
        metadata.category,
        metadata.colors,
        metadata.notes,
      ],
    );
    const item = mapWardrobeItem(result.rows[0]!);
    await finishCommand(client, {
      accountId: input.accountId,
      key: input.idempotencyKey,
      kind: 'create-wardrobe-item',
      request,
      body: item,
    });
    return item;
  });
}

export async function updateWardrobeItem(
  database: Database,
  input: {
    accountId: string;
    wardrobeItemId: string;
    metadata?: ItemMetadata;
    state?: ItemState;
    currentShelfImageVersionId?: string | null;
    expectedRecordVersion: number;
    idempotencyKey: string;
  },
): Promise<WardrobeItem> {
  const request = {
    wardrobeItemId: input.wardrobeItemId,
    metadata: input.metadata,
    state: input.state,
    currentShelfImageVersionId: input.currentShelfImageVersionId,
    expectedRecordVersion: input.expectedRecordVersion,
  };
  return withTransaction(database, async (client) => {
    const replay = await beginCommand<WardrobeItem>(client, {
      accountId: input.accountId,
      key: input.idempotencyKey,
      kind: 'update-wardrobe-item',
      request,
    });
    if (replay.replayed) return replay.body;
    const current = await client.query<WardrobeItemRow>(
      `SELECT ${itemColumns} FROM wardrobe_items
       WHERE id = $1 AND account_id = $2 AND deleted_at IS NULL FOR UPDATE`,
      [input.wardrobeItemId, input.accountId],
    );
    const row = current.rows[0];
    if (!row) throw new OwnedResourceNotFoundError();
    if (row.record_version !== input.expectedRecordVersion) throw new StaleRecordVersionError();
    if (input.currentShelfImageVersionId) {
      const version = await client.query(
        `SELECT 1 FROM shelf_image_versions
         WHERE id = $1 AND wardrobe_item_id = $2 AND account_id = $3`,
        [input.currentShelfImageVersionId, input.wardrobeItemId, input.accountId],
      );
      if (!version.rows[0]) {
        throw new InvalidWardrobeTransitionError(
          'The selected Shelf Image Version does not belong to this Wardrobe Item.',
        );
      }
    }
    const metadata = input.metadata ?? mapWardrobeItem(row).metadata;
    const status =
      input.currentShelfImageVersionId === undefined
        ? row.status
        : input.currentShelfImageVersionId === null
          ? 'reviewing-metadata'
          : 'ready';
    const updated = await client.query<WardrobeItemRow>(
      `UPDATE wardrobe_items SET
         state = $3, status = $4, name = $5, category = $6, colors = $7, notes = $8,
         current_shelf_image_version_id = $9, record_version = record_version + 1,
         updated_at = now()
       WHERE id = $1 AND account_id = $2
       RETURNING ${itemColumns}`,
      [
        input.wardrobeItemId,
        input.accountId,
        input.state ?? row.state,
        status,
        metadata.name,
        metadata.category,
        metadata.colors,
        metadata.notes,
        input.currentShelfImageVersionId === undefined
          ? row.current_shelf_image_version_id
          : input.currentShelfImageVersionId,
      ],
    );
    const item = mapWardrobeItem(updated.rows[0]!);
    await finishCommand(client, {
      accountId: input.accountId,
      key: input.idempotencyKey,
      kind: 'update-wardrobe-item',
      request,
      body: item,
    });
    return item;
  });
}

export async function enqueueShelfImageGeneration(
  database: Database,
  input: {
    accountId: string;
    wardrobeItemId: string;
    quality: GenerationQuality;
    size: '816x816';
    idempotencyKey: string;
  },
): Promise<{ jobId: string; generationAttemptId: string }> {
  const request = {
    wardrobeItemId: input.wardrobeItemId,
    quality: input.quality,
    size: input.size,
  };
  return withTransaction(database, async (client) => {
    const replay = await beginCommand<{ jobId: string; generationAttemptId: string }>(client, {
      accountId: input.accountId,
      key: input.idempotencyKey,
      kind: 'enqueue-shelf-image-generation',
      request,
    });
    if (replay.replayed) return replay.body;
    const itemResult = await client.query<WardrobeItemRow & { detection_proposal_id: string | null }>(
      `SELECT ${itemColumns}, detection_proposal_id FROM wardrobe_items
       WHERE id = $1 AND account_id = $2 AND deleted_at IS NULL FOR UPDATE`,
      [input.wardrobeItemId, input.accountId],
    );
    const row = itemResult.rows[0];
    if (!row) throw new OwnedResourceNotFoundError();
    if (row.status === 'queued' || row.status === 'generating') {
      throw new InvalidWardrobeTransitionError(
        'A Shelf Image generation is already active for this Wardrobe Item.',
      );
    }
    const generationAttemptId = randomUUID();
    const metadata = mapWardrobeItem(row).metadata;
    await client.query(
      `INSERT INTO generation_attempts (
         id, account_id, wardrobe_item_id, source_photo_id, detection_proposal_id,
         state, reviewed_metadata, model, quality, output_size, prompt_version
       ) VALUES ($1, $2, $3, $4, $5, 'queued', $6, 'gpt-image-2', $7, $8, 'laid-flat-v1')`,
      [
        generationAttemptId,
        input.accountId,
        input.wardrobeItemId,
        row.source_photo_id,
        row.detection_proposal_id,
        JSON.stringify(metadata),
        input.quality,
        input.size,
      ],
    );
    const jobId = await enqueueJob(client, {
      accountId: input.accountId,
      wardrobeItemId: input.wardrobeItemId,
      generationAttemptId,
      kind: 'generate-shelf-image',
      payload: { generationAttemptId },
      idempotencyKey: `generation:${input.idempotencyKey}`,
    });
    await client.query(
      `UPDATE wardrobe_items SET status = 'queued', record_version = record_version + 1,
         updated_at = now() WHERE id = $1 AND account_id = $2`,
      [input.wardrobeItemId, input.accountId],
    );
    const body = { jobId, generationAttemptId };
    await finishCommand(client, {
      accountId: input.accountId,
      key: input.idempotencyKey,
      kind: 'enqueue-shelf-image-generation',
      request,
      body,
    });
    return body;
  });
}

export async function startGenerationAttempt(
  database: Database,
  input: { accountId: string; generationAttemptId: string },
): Promise<boolean> {
  return withTransaction(database, async (client) => {
    const attempt = await client.query<{ wardrobe_item_id: string; state: string }>(
      `SELECT wardrobe_item_id, state FROM generation_attempts
       WHERE id = $1 AND account_id = $2 FOR UPDATE`,
      [input.generationAttemptId, input.accountId],
    );
    const row = attempt.rows[0];
    if (!row || (row.state !== 'queued' && row.state !== 'processing')) return false;
    if (row.state === 'processing') return true;
    await client.query(
      `UPDATE generation_attempts SET state = 'processing', started_at = now()
       WHERE id = $1 AND account_id = $2`,
      [input.generationAttemptId, input.accountId],
    );
    await client.query(
      `UPDATE wardrobe_items SET status = 'generating', record_version = record_version + 1,
         updated_at = now() WHERE id = $1 AND account_id = $2`,
      [row.wardrobe_item_id, input.accountId],
    );
    return true;
  });
}

export async function attachGenerationAsset(
  database: Database,
  input: {
    accountId: string;
    generationAttemptId: string;
    kind: 'reference' | 'keyed' | 'transparent';
    assetId: string;
  },
): Promise<string | null> {
  const column = {
    reference: 'reference_asset_id',
    keyed: 'keyed_asset_id',
    transparent: 'transparent_asset_id',
  }[input.kind];
  return withTransaction(database, async (client) => {
    await client.query(
      `UPDATE generation_attempts SET ${column} = $3
       WHERE id = $1 AND account_id = $2 AND state = 'processing'
         AND ${column} IS NULL`,
      [input.generationAttemptId, input.accountId, input.assetId],
    );
    const attached = await client.query<{ asset_id: string | null }>(
      `SELECT ${column} AS asset_id FROM generation_attempts
       WHERE id = $1 AND account_id = $2 AND state = 'processing'`,
      [input.generationAttemptId, input.accountId],
    );
    return attached.rows[0]?.asset_id ?? null;
  });
}

export type RecordGenerationProviderUsageInput = {
  accountId: string;
  generationAttemptId: string;
  providerRequestId: string;
  inputTokens: number;
  textInputTokens: number;
  imageInputTokens: number;
  outputTokens: number;
  capturedRates: unknown;
  costMicrounits: number;
  textInputCostMicrounits: number;
  imageInputCostMicrounits: number;
  imageOutputCostMicrounits: number;
  serviceTier: string;
  pricingEffectiveDate: string;
  providerUsage: unknown;
};

export async function recordGenerationProviderUsage(
  database: Database,
  input: RecordGenerationProviderUsageInput,
): Promise<boolean> {
  const attempt = await database.query(
    `UPDATE generation_attempts SET
       provider_request_id = $3, input_tokens = $4, text_input_tokens = $5,
       image_input_tokens = $6, output_tokens = $7, captured_rates = $8,
       cost_microunits = $9, service_tier = $10, pricing_effective_date = $11,
       provider_usage = $12, text_input_cost_microunits = $13,
       image_input_cost_microunits = $14, image_output_cost_microunits = $15
     WHERE id = $1 AND account_id = $2 AND state = 'processing'
       AND provider_request_id IS NULL`,
    [
      input.generationAttemptId,
      input.accountId,
      input.providerRequestId,
      input.inputTokens,
      input.textInputTokens,
      input.imageInputTokens,
      input.outputTokens,
      JSON.stringify(input.capturedRates),
      input.costMicrounits,
      input.serviceTier,
      input.pricingEffectiveDate,
      JSON.stringify(input.providerUsage),
      input.textInputCostMicrounits,
      input.imageInputCostMicrounits,
      input.imageOutputCostMicrounits,
    ],
  );
  return attempt.rowCount === 1;
}

export async function completeGenerationAttempt(
  database: Database,
  input: { accountId: string; generationAttemptId: string; resolvedChromaKey: string },
): Promise<boolean> {
  return withTransaction(database, async (client) => {
    const attempt = await client.query<{ wardrobe_item_id: string }>(
      `UPDATE generation_attempts SET state = 'needs-review', resolved_chroma_key = $3,
         finished_at = now()
       WHERE id = $1 AND account_id = $2 AND state = 'processing'
         AND reference_asset_id IS NOT NULL AND keyed_asset_id IS NOT NULL
         AND transparent_asset_id IS NOT NULL AND provider_request_id IS NOT NULL
       RETURNING wardrobe_item_id`,
      [input.generationAttemptId, input.accountId, input.resolvedChromaKey],
    );
    const row = attempt.rows[0];
    if (!row) return false;
    await client.query(
      `UPDATE wardrobe_items SET status = 'needs-review',
         record_version = record_version + 1, updated_at = now()
       WHERE id = $1 AND account_id = $2`,
      [row.wardrobe_item_id, input.accountId],
    );
    return true;
  });
}

export async function failGenerationAttempt(
  database: Database,
  input: {
    accountId: string;
    generationAttemptId: string;
    failureCategory: string;
    failureDetail: string;
  },
): Promise<boolean> {
  return withTransaction(database, async (client) => {
    const attempt = await client.query<{ wardrobe_item_id: string }>(
      `UPDATE generation_attempts SET state = 'failed', failure_category = $3,
         failure_detail = $4, finished_at = now()
       WHERE id = $1 AND account_id = $2 AND state IN ('queued', 'processing')
       RETURNING wardrobe_item_id`,
      [
        input.generationAttemptId,
        input.accountId,
        input.failureCategory,
        input.failureDetail,
      ],
    );
    const row = attempt.rows[0];
    if (!row) return false;
    await client.query(
      `UPDATE wardrobe_items SET status = 'failed', record_version = record_version + 1,
         updated_at = now() WHERE id = $1 AND account_id = $2`,
      [row.wardrobe_item_id, input.accountId],
    );
    return true;
  });
}

export async function keepShelfImage(
  database: Database,
  input: {
    accountId: string;
    wardrobeItemId: string;
    generationAttemptId: string;
    expectedRecordVersion: number;
    idempotencyKey: string;
  },
): Promise<{ wardrobeItem: WardrobeItem; shelfImageVersion: ShelfImageVersion }> {
  const request = {
    wardrobeItemId: input.wardrobeItemId,
    generationAttemptId: input.generationAttemptId,
    expectedRecordVersion: input.expectedRecordVersion,
  };
  return withTransaction(database, async (client) => {
    const replay = await beginCommand<{
      wardrobeItem: WardrobeItem;
      shelfImageVersion: ShelfImageVersion;
    }>(client, {
      accountId: input.accountId,
      key: input.idempotencyKey,
      kind: 'keep-shelf-image',
      request,
    });
    if (replay.replayed) return replay.body;
    const item = await client.query<WardrobeItemRow>(
      `SELECT ${itemColumns} FROM wardrobe_items
       WHERE id = $1 AND account_id = $2 AND deleted_at IS NULL FOR UPDATE`,
      [input.wardrobeItemId, input.accountId],
    );
    const itemRow = item.rows[0];
    if (!itemRow) throw new OwnedResourceNotFoundError();
    if (itemRow.record_version !== input.expectedRecordVersion) throw new StaleRecordVersionError();
    const attempt = await client.query<GenerationAttemptRow>(
      `SELECT ${attemptColumns} FROM generation_attempts
       WHERE id = $1 AND wardrobe_item_id = $2 AND account_id = $3 FOR UPDATE`,
      [input.generationAttemptId, input.wardrobeItemId, input.accountId],
    );
    const attemptRow = attempt.rows[0];
    if (
      !attemptRow ||
      attemptRow.state !== 'needs-review' ||
      !attemptRow.keyed_asset_id ||
      !attemptRow.transparent_asset_id
    ) {
      throw new InvalidWardrobeTransitionError(
        'Only a completed Shelf Image awaiting review can be kept.',
      );
    }
    const version = await client.query<ShelfImageVersionRow>(
      `INSERT INTO shelf_image_versions (
         id, account_id, wardrobe_item_id, generation_attempt_id, keyed_asset_id,
         transparent_asset_id, quality, output_size, prompt_version, kept_at
       ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, now())
       RETURNING ${versionColumns}`,
      [
        randomUUID(),
        input.accountId,
        input.wardrobeItemId,
        input.generationAttemptId,
        attemptRow.keyed_asset_id,
        attemptRow.transparent_asset_id,
        attemptRow.quality,
        attemptRow.output_size,
        attemptRow.prompt_version,
      ],
    );
    await client.query(
      `UPDATE generation_attempts SET state = 'kept' WHERE id = $1 AND account_id = $2`,
      [input.generationAttemptId, input.accountId],
    );
    const updated = await client.query<WardrobeItemRow>(
      `UPDATE wardrobe_items SET current_shelf_image_version_id = $3, status = 'ready',
         record_version = record_version + 1, updated_at = now()
       WHERE id = $1 AND account_id = $2 RETURNING ${itemColumns}`,
      [input.wardrobeItemId, input.accountId, version.rows[0]!.id],
    );
    const body = {
      wardrobeItem: mapWardrobeItem(updated.rows[0]!),
      shelfImageVersion: mapShelfImageVersion(version.rows[0]!),
    };
    await finishCommand(client, {
      accountId: input.accountId,
      key: input.idempotencyKey,
      kind: 'keep-shelf-image',
      request,
      body,
    });
    return body;
  });
}

type DeletionResponse = {
  wardrobeItemId: string;
  sourcePhotoDeleted: boolean;
  deletedAssetIds: string[];
};

async function deleteStoredAssets(
  database: Database,
  storage: PrivateObjectStorage,
  accountId: string,
  assetIds: string[],
): Promise<void> {
  if (assetIds.length === 0) return;
  const assets = await database.query<{ object_key: string }>(
    `SELECT object_key FROM private_assets
     WHERE account_id = $1 AND id = ANY($2::uuid[]) AND state = 'deleted'`,
    [accountId, assetIds],
  );
  for (const { object_key: objectKey } of assets.rows) {
    let keyMarker: string | undefined;
    let versionIdMarker: string | undefined;
    const versions: { Key: string; VersionId: string }[] = [];
    do {
      const page = await storage.client.send(
        new ListObjectVersionsCommand({
          Bucket: storage.bucket,
          Prefix: objectKey,
          KeyMarker: keyMarker,
          VersionIdMarker: versionIdMarker,
        }),
      );
      versions.push(
        ...[...(page.Versions ?? []), ...(page.DeleteMarkers ?? [])].flatMap(
          ({ Key, VersionId }) =>
            Key === objectKey && VersionId ? [{ Key, VersionId }] : [],
        ),
      );
      keyMarker = page.NextKeyMarker;
      versionIdMarker = page.NextVersionIdMarker;
    } while (keyMarker !== undefined);
    for (let offset = 0; offset < versions.length; offset += 1_000) {
      const deleted = await storage.client.send(
        new DeleteObjectsCommand({
          Bucket: storage.bucket,
          Delete: { Objects: versions.slice(offset, offset + 1_000) },
        }),
      );
      if (deleted.Errors?.length) {
        throw new Error(`Private object deletion failed for ${objectKey}.`);
      }
    }
  }
}

export async function permanentlyDeleteWardrobeItem(
  database: Database,
  storage: PrivateObjectStorage,
  input: {
    accountId: string;
    wardrobeItemId: string;
    expectedRecordVersion: number;
    idempotencyKey: string;
  },
): Promise<DeletionResponse> {
  const request = {
    wardrobeItemId: input.wardrobeItemId,
    expectedRecordVersion: input.expectedRecordVersion,
  };
  const body = await withTransaction(database, async (client) => {
    const replay = await beginCommand<DeletionResponse>(client, {
      accountId: input.accountId,
      key: input.idempotencyKey,
      kind: 'permanently-delete-wardrobe-item',
      request,
    });
    if (replay.replayed) return replay.body;
    const item = await client.query<WardrobeItemRow>(
      `SELECT ${itemColumns} FROM wardrobe_items
       WHERE id = $1 AND account_id = $2 AND deleted_at IS NULL FOR UPDATE`,
      [input.wardrobeItemId, input.accountId],
    );
    const itemRow = item.rows[0];
    if (!itemRow) throw new OwnedResourceNotFoundError();
    if (itemRow.record_version !== input.expectedRecordVersion) throw new StaleRecordVersionError();

    const assetCandidates = await client.query<{ id: string }>(
      `SELECT DISTINCT id FROM private_assets WHERE account_id = $1 AND id IN (
         SELECT reference_asset_id FROM generation_attempts WHERE wardrobe_item_id = $2
         UNION SELECT keyed_asset_id FROM generation_attempts WHERE wardrobe_item_id = $2
         UNION SELECT transparent_asset_id FROM generation_attempts WHERE wardrobe_item_id = $2
       )`,
      [input.accountId, input.wardrobeItemId],
    );
    await client.query(
      `UPDATE wardrobe_items SET current_shelf_image_version_id = NULL
       WHERE id = $1 AND account_id = $2`,
      [input.wardrobeItemId, input.accountId],
    );
    await client.query(
      `DELETE FROM shelf_image_versions WHERE wardrobe_item_id = $1 AND account_id = $2`,
      [input.wardrobeItemId, input.accountId],
    );
    await client.query(
      `DELETE FROM generation_attempts WHERE wardrobe_item_id = $1 AND account_id = $2`,
      [input.wardrobeItemId, input.accountId],
    );
    await client.query(
      `DELETE FROM wardrobe_items WHERE id = $1 AND account_id = $2`,
      [input.wardrobeItemId, input.accountId],
    );
    const remaining = await client.query<{ count: string }>(
      `SELECT count(*) FROM wardrobe_items
       WHERE source_photo_id = $1 AND account_id = $2 AND deleted_at IS NULL`,
      [itemRow.source_photo_id, input.accountId],
    );
    const sourcePhotoDeleted = Number(remaining.rows[0]!.count) === 0;
    if (sourcePhotoDeleted) {
      const sourceAsset = await client.query<{ asset_id: string }>(
        `SELECT asset_id FROM source_photos WHERE id = $1 AND account_id = $2`,
        [itemRow.source_photo_id, input.accountId],
      );
      if (sourceAsset.rows[0]) assetCandidates.rows.push({ id: sourceAsset.rows[0].asset_id });
      await client.query(
        `DELETE FROM source_photos WHERE id = $1 AND account_id = $2`,
        [itemRow.source_photo_id, input.accountId],
      );
    }
    const candidateIds = [...new Set(assetCandidates.rows.map(({ id }) => id))];
    const deletedAssets = await client.query<{ id: string }>(
      `UPDATE private_assets SET state = 'deleted', deleted_at = now()
       WHERE account_id = $1 AND id = ANY($2::uuid[])
         AND NOT EXISTS (SELECT 1 FROM source_photos WHERE asset_id = private_assets.id)
         AND NOT EXISTS (
           SELECT 1 FROM generation_attempts WHERE
             reference_asset_id = private_assets.id OR keyed_asset_id = private_assets.id
             OR transparent_asset_id = private_assets.id
         )
         AND NOT EXISTS (
           SELECT 1 FROM shelf_image_versions WHERE
             keyed_asset_id = private_assets.id OR transparent_asset_id = private_assets.id
         )
       RETURNING id`,
      [input.accountId, candidateIds],
    );
    const response: DeletionResponse = {
      wardrobeItemId: input.wardrobeItemId,
      sourcePhotoDeleted,
      deletedAssetIds: deletedAssets.rows.map(({ id }) => id).sort(),
    };
    await finishCommand(client, {
      accountId: input.accountId,
      key: input.idempotencyKey,
      kind: 'permanently-delete-wardrobe-item',
      request,
      body: response,
    });
    return response;
  });
  await deleteStoredAssets(database, storage, input.accountId, body.deletedAssetIds);
  return body;
}

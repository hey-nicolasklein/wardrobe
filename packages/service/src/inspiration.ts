import { createHash, randomUUID } from 'node:crypto';

import { GetObjectCommand, PutObjectCommand } from '@aws-sdk/client-s3';
import type { CharacterSheet, Look, LookConcept, SupportedCategory } from '@form/contracts';

import {
  calculateCostMicrounits,
  type CatalogExecutionConfig,
  CatalogJobError,
} from './catalog.js';
import { CatalogProviderError, type CatalogProvider } from './catalog-provider.js';
import type { Database, DatabaseClient } from './database.js';
import { withTransaction } from './database.js';
import { enqueueJob, type RemoteImageJob } from './jobs.js';
import { IdempotencyConflictError, OwnedResourceNotFoundError } from './media.js';
import type { PrivateObjectStorage } from './storage.js';

export const characterSheetModel = 'gpt-image-2.5-flare';
export const characterSheetPromptVersion = 'identity-sheet-v3';
export const characterSheetRefinePromptVersion = 'identity-sheet-refine-v2';
export const lookModel = 'gpt-image-2.5-flare';
export const lookPlannerModel = 'gpt-5.4-mini';
export const lookPromptVersion = 'candid-iphone-v1';

type CharacterRow = {
  id: string;
  state: CharacterSheet['state'];
  reference_asset_ids: string[];
  note: string | null;
  parent_character_sheet_id: string | null;
  refinement_instruction: string | null;
  asset_id: string | null;
  active: boolean;
  model: string;
  quality: 'high';
  output_size: '864x1536';
  provider_request_id: string | null;
  cost_microunits: string | null;
  failure_category: string | null;
  created_at: Date;
  finished_at: Date | null;
};
type LookRow = {
  id: string;
  state: Look['state'];
  asset_id: string | null;
  character_sheet_id: string;
  parent_look_id: string | null;
  planned_concept: LookConcept | null;
  model: string;
  quality: 'medium';
  output_size: '1024x1280';
  provider_request_id: string | null;
  cost_microunits: string | null;
  failure_category: string | null;
  created_at: Date;
  finished_at: Date | null;
  wardrobe_item_ids: string[];
};

const characterColumns = `id, state, reference_asset_ids, note, parent_character_sheet_id,
  refinement_instruction, asset_id, active, model, quality,
  output_size, provider_request_id, cost_microunits, failure_category, created_at, finished_at`;
const lookColumns = `l.id, l.state, l.asset_id, l.character_sheet_id, l.parent_look_id,
  l.planned_concept, l.model, l.quality, l.output_size, l.provider_request_id,
  l.cost_microunits, l.failure_category, l.created_at, l.finished_at,
  COALESCE(array_agg(li.wardrobe_item_id ORDER BY li.ordinal) FILTER (WHERE li.wardrobe_item_id IS NOT NULL), '{}') AS wardrobe_item_ids`;

const mapCharacter = (row: CharacterRow): CharacterSheet => ({
  id: row.id,
  state: row.state,
  referenceAssetIds: row.reference_asset_ids,
  note: row.note,
  parentCharacterSheetId: row.parent_character_sheet_id,
  refinementInstruction: row.refinement_instruction,
  assetId: row.asset_id,
  active: row.active,
  model: row.model,
  quality: row.quality,
  size: row.output_size,
  providerRequestId: row.provider_request_id,
  costMicrounits: row.cost_microunits === null ? null : Number(row.cost_microunits),
  failureCategory: row.failure_category,
  createdAt: row.created_at.toISOString(),
  finishedAt: row.finished_at?.toISOString() ?? null,
});
const mapLook = (row: LookRow): Look => ({
  id: row.id,
  state: row.state,
  assetId: row.asset_id,
  wardrobeItemIds: row.wardrobe_item_ids,
  characterSheetId: row.character_sheet_id,
  parentLookId: row.parent_look_id,
  concept: row.planned_concept,
  model: row.model,
  quality: row.quality,
  size: row.output_size,
  providerRequestId: row.provider_request_id,
  costMicrounits: row.cost_microunits === null ? null : Number(row.cost_microunits),
  failureCategory: row.failure_category,
  createdAt: row.created_at.toISOString(),
  finishedAt: row.finished_at?.toISOString() ?? null,
});
const hash = (value: unknown) => createHash('sha256').update(JSON.stringify(value)).digest('hex');

async function replay<T>(
  client: DatabaseClient,
  accountId: string,
  key: string,
  kind: string,
  request: unknown,
): Promise<T | null> {
  await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [
    `${accountId}:${key}`,
  ]);
  const found = await client.query<{
    command_kind: string;
    request_hash: string;
    response_body: T;
  }>(
    'SELECT command_kind, request_hash, response_body FROM idempotency_commands WHERE account_id = $1 AND key = $2',
    [accountId, key],
  );
  if (!found.rows[0]) return null;
  if (found.rows[0].command_kind !== kind || found.rows[0].request_hash !== hash(request))
    throw new IdempotencyConflictError();
  return found.rows[0].response_body;
}
async function remember(
  client: DatabaseClient,
  accountId: string,
  key: string,
  kind: string,
  request: unknown,
  body: unknown,
) {
  await client.query(
    `INSERT INTO idempotency_commands(account_id,key,command_kind,request_hash,response_status,response_body,expires_at) VALUES($1,$2,$3,$4,202,$5,now()+interval '7 days')`,
    [accountId, key, kind, hash(request), JSON.stringify(body)],
  );
}

export async function listCharacterSheets(
  database: Database,
  accountId: string,
): Promise<CharacterSheet[]> {
  const rows = await database.query<CharacterRow>(
    `SELECT ${characterColumns} FROM character_sheets
     WHERE account_id = $1 AND deleted_at IS NULL ORDER BY created_at DESC`,
    [accountId],
  );
  return rows.rows.map(mapCharacter);
}
async function assertOwnedAssets(client: DatabaseClient, accountId: string, assetIds: string[]) {
  const owned = await client.query(
    `SELECT 1 FROM private_assets WHERE account_id=$1 AND state='ready' AND id=ANY($2::uuid[])`,
    [accountId, assetIds],
  );
  if (owned.rowCount !== assetIds.length) throw new OwnedResourceNotFoundError();
}

// Writes the sheet row and its generation job. Callers validate the references first.
// A non-null instruction marks the row as a refinement of `parentCharacterSheetId`.
async function queueCharacterSheet(
  client: DatabaseClient,
  input: {
    accountId: string;
    referenceAssetIds: string[];
    note: string | null;
    parentCharacterSheetId: string | null;
    instruction: string | null;
    idempotencyKey: string;
  },
) {
  const characterSheetId = randomUUID();
  await client.query(
    `INSERT INTO character_sheets(id,account_id,reference_asset_ids,note,parent_character_sheet_id,refinement_instruction,state,model,quality,output_size,prompt_version) VALUES($1,$2,$3,$4,$5,$6,'queued',$7,'high','864x1536',$8)`,
    [
      characterSheetId,
      input.accountId,
      input.referenceAssetIds,
      input.note,
      input.parentCharacterSheetId,
      input.instruction,
      characterSheetModel,
      input.instruction === null ? characterSheetPromptVersion : characterSheetRefinePromptVersion,
    ],
  );
  const jobId = await enqueueJob(client, {
    accountId: input.accountId,
    kind: 'generate-character-sheet',
    payload: { characterSheetId },
    idempotencyKey: `character:${input.idempotencyKey}`,
  });
  await client.query('UPDATE remote_image_jobs SET character_sheet_id=$1 WHERE id=$2', [
    characterSheetId,
    jobId,
  ]);
  return { jobId, characterSheetId };
}

export async function createCharacterSheet(
  database: Database,
  input: {
    accountId: string;
    referenceAssetIds: string[];
    note: string | null;
    idempotencyKey: string;
  },
) {
  const request = {
    referenceAssetIds: input.referenceAssetIds,
    note: input.note,
  };
  return withTransaction(database, async (client) => {
    const prior = await replay<{ jobId: string; characterSheetId: string }>(
      client,
      input.accountId,
      input.idempotencyKey,
      'create-character-sheet',
      request,
    );
    if (prior) return prior;
    await assertOwnedAssets(client, input.accountId, input.referenceAssetIds);
    const body = await queueCharacterSheet(client, {
      ...input,
      parentCharacterSheetId: null,
      instruction: null,
    });
    await remember(
      client,
      input.accountId,
      input.idempotencyKey,
      'create-character-sheet',
      request,
      body,
    );
    return body;
  });
}

// Renders a new sheet from a finished one plus fresh photos, so a promising identity can be
// corrected instead of started over. Each round carries the parent render into the next
// generation, which is how the reference set grows past the four images one call accepts.
// The result stays inactive until it is activated, so a worse angle cannot replace a working sheet.
export async function refineCharacterSheet(
  database: Database,
  input: {
    accountId: string;
    characterSheetId: string;
    referenceAssetIds: string[];
    instruction: string;
    idempotencyKey: string;
  },
) {
  const request = {
    characterSheetId: input.characterSheetId,
    referenceAssetIds: input.referenceAssetIds,
    instruction: input.instruction,
  };
  return withTransaction(database, async (client) => {
    const prior = await replay<{ jobId: string; characterSheetId: string }>(
      client,
      input.accountId,
      input.idempotencyKey,
      'refine-character-sheet',
      request,
    );
    if (prior) return prior;
    const found = await client.query<{
      state: CharacterSheet['state'];
      asset_id: string | null;
      note: string | null;
    }>(
      `SELECT state, asset_id, note FROM character_sheets
       WHERE id = $1 AND account_id = $2 AND deleted_at IS NULL`,
      [input.characterSheetId, input.accountId],
    );
    const parent = found.rows[0];
    if (!parent) throw new OwnedResourceNotFoundError();
    if (parent.state !== 'ready' || !parent.asset_id)
      throw new InspirationValidationError(
        'character-sheet-not-refinable',
        'Nur ein fertiges Character Sheet kann verfeinert werden.',
      );
    await assertOwnedAssets(client, input.accountId, input.referenceAssetIds);
    const body = await queueCharacterSheet(client, {
      accountId: input.accountId,
      // The parent render leads so the model reads it as the sheet to edit.
      referenceAssetIds: [parent.asset_id, ...input.referenceAssetIds],
      note: parent.note,
      parentCharacterSheetId: input.characterSheetId,
      instruction: input.instruction,
      idempotencyKey: input.idempotencyKey,
    });
    await remember(
      client,
      input.accountId,
      input.idempotencyKey,
      'refine-character-sheet',
      request,
      body,
    );
    return body;
  });
}
export async function activateCharacterSheet(
  database: Database,
  input: { accountId: string; characterSheetId: string },
) {
  return withTransaction(database, async (client) => {
    const found = await client.query(
      `SELECT 1 FROM character_sheets
       WHERE id = $1 AND account_id = $2 AND state = 'ready' AND deleted_at IS NULL
       FOR UPDATE`,
      [input.characterSheetId, input.accountId],
    );
    if (!found.rows[0]) throw new OwnedResourceNotFoundError();
    await client.query('UPDATE character_sheets SET active=false WHERE account_id=$1 AND active', [
      input.accountId,
    ]);
    await client.query('UPDATE character_sheets SET active=true WHERE id=$1 AND account_id=$2', [
      input.characterSheetId,
      input.accountId,
    ]);
  });
}

export async function removeCharacterSheet(
  database: Database,
  input: { accountId: string; characterSheetId: string },
): Promise<void> {
  await withTransaction(database, async (client) => {
    const result = await client.query<{ active: boolean; state: CharacterSheet['state'] }>(
      `SELECT active, state FROM character_sheets
       WHERE id = $1 AND account_id = $2 AND deleted_at IS NULL FOR UPDATE`,
      [input.characterSheetId, input.accountId],
    );
    const sheet = result.rows[0];
    if (!sheet) throw new OwnedResourceNotFoundError();
    if (sheet.active)
      throw new InspirationValidationError(
        'active-character-sheet',
        'Das aktive Character Sheet kann nicht gelöscht werden.',
      );
    if (sheet.state === 'queued' || sheet.state === 'processing')
      throw new InspirationValidationError(
        'character-sheet-processing',
        'Ein laufendes Character Sheet kann nicht gelöscht werden.',
      );
    await client.query(
      'UPDATE character_sheets SET deleted_at = now() WHERE id = $1 AND account_id = $2',
      [input.characterSheetId, input.accountId],
    );
  });
}

async function candidateItems(
  client: Database | DatabaseClient,
  accountId: string,
  deliberate: boolean,
) {
  return client.query<{
    id: string;
    name: string;
    category: SupportedCategory;
    colors: string[];
    notes: string | null;
    asset_id: string;
  }>(
    `SELECT i.id,i.name,i.category,i.colors,i.notes,v.transparent_asset_id AS asset_id FROM wardrobe_items i JOIN shelf_image_versions v ON v.id=i.current_shelf_image_version_id WHERE i.account_id=$1 AND i.deleted_at IS NULL AND i.state ${deliberate ? "IN ('owning','wanting')" : "='owning'"} ORDER BY i.created_at`,
    [accountId],
  );
}
function hasCore(items: Array<{ category: string }>) {
  const cats = new Set(items.map((i) => i.category));
  return cats.has('dress') || (cats.has('top') && (cats.has('pants') || cats.has('skirt')));
}

export async function listLooks(database: Database, accountId: string): Promise<Look[]> {
  const rows = await database.query<LookRow>(
    `SELECT ${lookColumns} FROM looks l LEFT JOIN look_items li ON li.look_id=l.id LEFT JOIN wardrobe_items wi ON wi.id=li.wardrobe_item_id AND wi.deleted_at IS NULL WHERE l.account_id=$1 AND l.deleted_at IS NULL GROUP BY l.id ORDER BY l.created_at DESC`,
    [accountId],
  );
  return rows.rows.map(mapLook);
}
export async function createLook(
  database: Database,
  input: {
    accountId: string;
    exactItemIds: string[];
    categories: SupportedCategory[];
    parentLookId: string | null;
    idempotencyKey: string;
  },
) {
  const request = {
    exactItemIds: input.exactItemIds,
    categories: input.categories,
    parentLookId: input.parentLookId,
  };
  return withTransaction(database, async (client) => {
    const prior = await replay<{ jobId: string; lookId: string }>(
      client,
      input.accountId,
      input.idempotencyKey,
      'create-look',
      request,
    );
    if (prior) return prior;
    const active = await client.query<{ id: string }>(
      `SELECT id FROM character_sheets
       WHERE account_id = $1 AND active AND state = 'ready' AND deleted_at IS NULL`,
      [input.accountId],
    );
    if (!active.rows[0])
      throw new InspirationValidationError(
        'character-sheet-required',
        'Erstelle zuerst ein Character Sheet in den Einstellungen.',
      );
    let exactIds = input.exactItemIds;
    let parentId = input.parentLookId;
    if (parentId) {
      const parent = await client.query<{ ids: string[] }>(
        `SELECT COALESCE(array_agg(li.wardrobe_item_id ORDER BY li.ordinal),'{}') ids FROM looks l LEFT JOIN look_items li ON li.look_id=l.id WHERE l.id=$1 AND l.account_id=$2 AND l.state='ready' GROUP BY l.id`,
        [parentId, input.accountId],
      );
      if (!parent.rows[0]) throw new OwnedResourceNotFoundError();
      exactIds = parent.rows[0].ids;
    }
    const candidates = await candidateItems(
      client,
      input.accountId,
      exactIds.length > 0 || input.categories.length > 0,
    );
    if (!exactIds.length && !input.categories.length && !hasCore(candidates.rows))
      throw new InspirationValidationError(
        'core-outfit-required',
        'Für eine Überraschung brauchst du ein Kleid oder ein Oberteil plus Hose oder Rock mit aktivem Katalogbild.',
      );
    if (exactIds.some((id) => !candidates.rows.some((row) => row.id === id)))
      throw new InspirationValidationError(
        'item-not-eligible',
        'Mindestens ein gewähltes Stück hat kein aktives Katalogbild.',
      );
    for (const category of input.categories)
      if (!candidates.rows.some((row) => row.category === category))
        throw new InspirationValidationError(
          'category-unavailable',
          `Für ${category} fehlt ein nutzbares Stück mit aktivem Katalogbild.`,
        );
    const lookId = randomUUID();
    await client.query(
      `INSERT INTO looks(id,account_id,character_sheet_id,parent_look_id,state,exact_item_ids,category_constraints,model,quality,output_size,prompt_version) VALUES($1,$2,$3,$4,'queued',$5,$6,$7,'medium','1024x1280',$8)`,
      [
        lookId,
        input.accountId,
        active.rows[0].id,
        parentId,
        exactIds,
        input.categories,
        lookModel,
        lookPromptVersion,
      ],
    );
    const jobId = await enqueueJob(client, {
      accountId: input.accountId,
      kind: 'generate-look',
      payload: { lookId },
      idempotencyKey: `look:${input.idempotencyKey}`,
    });
    await client.query('UPDATE remote_image_jobs SET look_id=$1 WHERE id=$2', [lookId, jobId]);
    const body = { jobId, lookId };
    await remember(client, input.accountId, input.idempotencyKey, 'create-look', request, body);
    return body;
  });
}
export async function retryLook(
  database: Database,
  input: { accountId: string; lookId: string; idempotencyKey: string },
) {
  return withTransaction(database, async (client) => {
    const row = await client.query(
      `UPDATE looks SET state='queued',failure_category=NULL,failure_detail=NULL,started_at=NULL,finished_at=NULL WHERE id=$1 AND account_id=$2 AND state='failed' RETURNING id`,
      [input.lookId, input.accountId],
    );
    if (!row.rows[0])
      throw new InspirationValidationError(
        'look-not-retryable',
        'Dieser Look kann nicht erneut versucht werden.',
      );
    const jobId = await enqueueJob(client, {
      accountId: input.accountId,
      kind: 'generate-look',
      payload: { lookId: input.lookId },
      idempotencyKey: `look-retry:${input.idempotencyKey}`,
    });
    await client.query('UPDATE remote_image_jobs SET look_id=$1 WHERE id=$2', [
      input.lookId,
      jobId,
    ]);
    return { jobId, lookId: input.lookId };
  });
}
export async function deleteLook(database: Database, input: { accountId: string; lookId: string }) {
  const result = await database.query(
    `UPDATE looks SET deleted_at=now() WHERE id=$1 AND account_id=$2 AND deleted_at IS NULL`,
    [input.lookId, input.accountId],
  );
  if (!result.rowCount) throw new OwnedResourceNotFoundError();
}
export async function generationCosts(database: Database, accountId: string) {
  const result = await database.query<{
    look_total: string;
    successful: string;
    character_total: string;
  }>(
    `SELECT COALESCE((SELECT sum(cost_microunits) FROM looks WHERE account_id=$1),0) look_total,COALESCE((SELECT count(*) FROM looks WHERE account_id=$1 AND state='ready'),0) successful,COALESCE((SELECT sum(cost_microunits) FROM character_sheets WHERE account_id=$1),0) character_total`,
    [accountId],
  );
  const r = result.rows[0]!;
  const total = Number(r.look_total),
    successful = Number(r.successful);
  return {
    lookTotalMicrounits: total,
    successfulLookCount: successful,
    averageSuccessfulLookMicrounits: successful ? Math.round(total / successful) : 0,
    characterSheetTotalMicrounits: Number(r.character_total),
  };
}

export class InspirationValidationError extends Error {
  constructor(
    readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = 'InspirationValidationError';
  }
}

async function readAsset(
  database: Database,
  storage: PrivateObjectStorage,
  accountId: string,
  assetId: string,
) {
  const result = await database.query<{
    object_key: string;
    object_version_id: string;
  }>(
    `SELECT object_key,object_version_id FROM private_assets WHERE id=$1 AND account_id=$2 AND state='ready'`,
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
  return Buffer.from(await object.Body!.transformToByteArray());
}
async function writeAsset(
  database: Database,
  storage: PrivateObjectStorage,
  accountId: string,
  purpose: 'character-sheet' | 'look',
  bytes: Buffer,
  width: number,
  height: number,
) {
  const id = randomUUID(),
    objectKey = `accounts/${accountId}/inspiration/${purpose}/${id}`;
  const result = await storage.client.send(
    new PutObjectCommand({
      Bucket: storage.bucket,
      Key: objectKey,
      Body: bytes,
      ContentType: 'image/png',
      ContentLength: bytes.byteLength,
    }),
  );
  if (!result.VersionId)
    throw new CatalogJobError(
      'internal',
      'Object storage did not version the inspiration asset.',
      false,
    );
  await database.query(
    `INSERT INTO private_assets(id,account_id,purpose,object_key,object_version_id,content_type,byte_size,pixel_width,pixel_height,state,ready_at) VALUES($1,$2,$3,$4,$5,'image/png',$6,$7,$8,'ready',now())`,
    [id, accountId, purpose, objectKey, result.VersionId, bytes.byteLength, width, height],
  );
  return id;
}
const characterPrompt = (note: string | null) =>
  `Create one high-quality 9:16 identity Character Sheet of the same person shown in all reference photos, laid out as two rows of three views each. Top row: three large close-ups of the face in this exact left-to-right order: strict left-side profile with the nose pointing towards the left edge, direct front-facing view looking into the camera, strict right-side profile with the nose pointing towards the right edge. Bottom row: three full-body views in the same left-profile, front-facing, right-profile order. The two profile views must show opposite sides of the face and must not duplicate the same three-quarter angle. Never show a three-quarter rear angle or the back of the person. Use neutral fitted clothing, consistent soft studio lighting, and a plain background. Preserve identity, body proportions, skin, hair, and stable features${note ? `. Stable details: ${note}` : ''}. No text, labels, callouts, collage borders, decoration, or watermark.`;
const refinementPrompt = (note: string | null, instruction: string) =>
  `The first reference image is an existing 9:16 identity Character Sheet. The remaining reference photos show the same real person and are the ground truth for identity. Redraw the sheet with the same layout, the same views in the same positions, the same neutral fitted clothing, lighting, and plain background. Correct only this: ${instruction}. Keep every other region identical to the first reference and preserve identity, body proportions, skin, and hair. If it does not already show a row of three face close-ups above a row of three full-body views, rebuild it into that layout. In each row, use this exact left-to-right order: strict left-side profile with the nose pointing towards the left edge, direct front-facing view looking into the camera, strict right-side profile with the nose pointing towards the right edge. The two profile views must show opposite sides of the face and must not duplicate the same three-quarter angle${note ? `. Stable details: ${note}` : ''}. No text, labels, callouts, collage borders, decoration, or watermark.`;
function lookPrompt(
  concept: LookConcept,
  items: Array<{ name: string; category: string; colors: string[] }>,
) {
  return `Create one photorealistic 4:5 iPhone-style snapshot as if a friend naturally photographed the referenced person while ${concept.activity}, in ${concept.scene}. Mood: ${concept.mood}. ${concept.framing} framing. The person must not look directly at the camera. Dress the person in exactly these referenced major garments: ${items.map((i) => `${i.name} (${i.category}; ${i.colors.join(', ')})`).join('; ')}. Every selected garment must be fully visible and faithful to its reference. Do not invent other major garments; plain incidental basics such as socks are allowed. Avoid selfies, posed portraits, illustrations, runway staging, extreme editorial styling, text, watermarks, and collages. Shoes, trousers, skirts, and dresses must never be cropped when selected.`;
}

export async function executeInspirationJob(
  database: Database,
  storage: PrivateObjectStorage,
  provider: CatalogProvider,
  job: RemoteImageJob,
  config: CatalogExecutionConfig,
) {
  const controller = new AbortController(),
    timer = setTimeout(() => controller.abort(), config.requestTimeoutMs);
  try {
    if (job.kind === 'generate-character-sheet') {
      const id = (job.payload as { characterSheetId: string }).characterSheetId;
      const started = await database.query<CharacterRow>(
        `UPDATE character_sheets SET state='processing',started_at=COALESCE(started_at,now()) WHERE id=$1 AND account_id=$2 AND state IN ('queued','processing') RETURNING ${characterColumns}`,
        [id, job.accountId],
      );
      const row = started.rows[0];
      if (!row) {
        const done = await database.query(
          `SELECT 1 FROM character_sheets WHERE id=$1 AND account_id=$2 AND state='ready'`,
          [id, job.accountId],
        );
        if (done.rows[0]) return;
        throw new CatalogJobError('internal', 'Character Sheet cannot be started.', false);
      }
      const refs = await Promise.all(
        row.reference_asset_ids.map((asset) => readAsset(database, storage, job.accountId, asset)),
      );
      const result = await provider.generateComposite({
        references: refs,
        prompt:
          row.refinement_instruction === null
            ? characterPrompt(row.note)
            : refinementPrompt(row.note, row.refinement_instruction),
        model: row.model,
        quality: 'high',
        size: '864x1536',
        signal: controller.signal,
      });
      const assetId = await writeAsset(
        database,
        storage,
        job.accountId,
        'character-sheet',
        result.pngBytes,
        864,
        1536,
      );
      const cost = calculateCostMicrounits(result.usage, config.pricing);
      const finish = `UPDATE character_sheets SET state='ready',asset_id=$3,provider_request_id=$4,provider_usage=$5,cost_microunits=$6,finished_at=now()`;
      const params = [
        id,
        job.accountId,
        assetId,
        result.requestId,
        JSON.stringify(result.usage.raw),
        cost,
      ];
      // A refinement waits for an explicit activation so it can be compared against its parent.
      if (row.refinement_instruction !== null) {
        await database.query(`${finish} WHERE id=$1 AND account_id=$2`, params);
        return;
      }
      await withTransaction(database, async (client) => {
        await client.query(
          'UPDATE character_sheets SET active=false WHERE account_id=$1 AND active',
          [job.accountId],
        );
        await client.query(`${finish},active=true WHERE id=$1 AND account_id=$2`, params);
      });
      return;
    }
    if (job.kind !== 'generate-look')
      throw new CatalogJobError('internal', 'Unsupported inspiration job.', false);
    const id = (job.payload as { lookId: string }).lookId;
    const started = await database.query<{
      character_sheet_id: string;
      exact_item_ids: string[];
      category_constraints: SupportedCategory[];
      model: string;
      planned_concept: LookConcept | null;
      state: string;
    }>(
      `UPDATE looks SET state=CASE WHEN planned_concept IS NULL THEN 'planning' ELSE 'generating' END,started_at=COALESCE(started_at,now()) WHERE id=$1 AND account_id=$2 AND state IN ('queued','planning','generating') RETURNING character_sheet_id,exact_item_ids,category_constraints,model,planned_concept,state`,
      [id, job.accountId],
    );
    const row = started.rows[0];
    if (!row) {
      const done = await database.query(
        `SELECT 1 FROM looks WHERE id=$1 AND account_id=$2 AND state='ready'`,
        [id, job.accountId],
      );
      if (done.rows[0]) return;
      throw new CatalogJobError('internal', 'Look cannot be started.', false);
    }
    const candidates = await candidateItems(
      database,
      job.accountId,
      row.exact_item_ids.length > 0 || row.category_constraints.length > 0,
    );
    const recent = await database.query<{
      ids: string[];
      planned_concept: LookConcept | null;
    }>(
      `SELECT COALESCE(array_agg(li.wardrobe_item_id),'{}') ids,l.planned_concept FROM looks l LEFT JOIN look_items li ON li.look_id=l.id WHERE l.account_id=$1 AND l.id<>$2 AND l.state='ready' GROUP BY l.id ORDER BY max(l.created_at) DESC LIMIT 12`,
      [job.accountId, id],
    );
    let concept = row.planned_concept,
      itemIds: string[] = [];
    if (concept) {
      const links = await database.query<{ wardrobe_item_id: string }>(
        'SELECT wardrobe_item_id FROM look_items WHERE look_id=$1 ORDER BY ordinal',
        [id],
      );
      itemIds = links.rows.map((r) => r.wardrobe_item_id);
    } else {
      const planned = await provider.planLook({
        candidates: candidates.rows.map((i) => ({
          id: i.id,
          metadata: {
            name: i.name,
            category: i.category,
            colors: i.colors,
            notes: i.notes,
          },
        })),
        recent: recent.rows.map((r) => ({
          itemIds: r.ids,
          concept: r.planned_concept,
        })),
        exactItemIds: row.exact_item_ids,
        categories: row.category_constraints,
        model: lookPlannerModel,
        signal: controller.signal,
      });
      concept = planned.concept;
      itemIds = planned.itemIds;
      const plannedItems = candidates.rows.filter((item) => itemIds.includes(item.id));
      const missingCategory = row.category_constraints.find(
        (category) => !plannedItems.some((item) => item.category === category),
      );
      if (missingCategory)
        throw new CatalogJobError(
          'validation',
          `The Look plan omitted the ${missingCategory} constraint.`,
          false,
        );
      if (
        row.exact_item_ids.length === 0 &&
        row.category_constraints.length === 0 &&
        !hasCore(plannedItems)
      )
        throw new CatalogJobError(
          'validation',
          'The random Look plan did not select a core outfit.',
          false,
        );
      await withTransaction(database, async (client) => {
        await client.query(
          `UPDATE looks SET state='generating',planned_concept=$3 WHERE id=$1 AND account_id=$2`,
          [id, job.accountId, JSON.stringify(concept)],
        );
        for (const [ordinal, itemId] of itemIds.entries())
          await client.query(
            'INSERT INTO look_items(look_id,wardrobe_item_id,ordinal) VALUES($1,$2,$3) ON CONFLICT DO NOTHING',
            [id, itemId, ordinal],
          );
      });
    }
    const character = await database.query<{ asset_id: string }>(
      'SELECT asset_id FROM character_sheets WHERE id=$1 AND account_id=$2',
      [row.character_sheet_id, job.accountId],
    );
    const selected = candidates.rows
      .filter((i) => itemIds.includes(i.id))
      .sort((a, b) => itemIds.indexOf(a.id) - itemIds.indexOf(b.id));
    if (!character.rows[0]?.asset_id || selected.length !== itemIds.length)
      throw new CatalogJobError('internal', 'Look references are no longer available.', false);
    const refs = await Promise.all(
      [character.rows[0].asset_id, ...selected.map((i) => i.asset_id)].map((asset) =>
        readAsset(database, storage, job.accountId, asset),
      ),
    );
    const result = await provider.generateComposite({
      references: refs,
      prompt: lookPrompt(concept, selected),
      model: row.model,
      quality: 'medium',
      size: '1024x1280',
      signal: controller.signal,
    });
    const assetId = await writeAsset(
      database,
      storage,
      job.accountId,
      'look',
      result.pngBytes,
      1024,
      1280,
    );
    const cost = calculateCostMicrounits(result.usage, config.pricing);
    await database.query(
      `UPDATE looks SET state='ready',asset_id=$3,provider_request_id=$4,provider_usage=$5,cost_microunits=$6,finished_at=now() WHERE id=$1 AND account_id=$2`,
      [id, job.accountId, assetId, result.requestId, JSON.stringify(result.usage.raw), cost],
    );
  } finally {
    clearTimeout(timer);
  }
}
export async function failInspirationAttempt(
  database: Database,
  job: RemoteImageJob,
  error: unknown,
) {
  const e =
    error instanceof CatalogProviderError || error instanceof CatalogJobError
      ? error
      : new CatalogJobError('internal', 'Unexpected inspiration failure.', false);
  if (job.kind === 'generate-character-sheet')
    await database.query(
      `UPDATE character_sheets SET state='failed',failure_category=$3,failure_detail=$4,finished_at=now() WHERE id=$1 AND account_id=$2`,
      [
        (job.payload as { characterSheetId: string }).characterSheetId,
        job.accountId,
        e.category,
        e.message,
      ],
    );
  if (job.kind === 'generate-look')
    await database.query(
      `UPDATE looks SET state='failed',failure_category=$3,failure_detail=$4,finished_at=now() WHERE id=$1 AND account_id=$2`,
      [(job.payload as { lookId: string }).lookId, job.accountId, e.category, e.message],
    );
}

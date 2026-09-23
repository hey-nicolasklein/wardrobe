import { createHash, randomUUID } from 'node:crypto';

import sharp from 'sharp';

import { GetObjectCommand, PutObjectCommand } from '@aws-sdk/client-s3';
import type { CharacterSheet, Look, LookConcept, SupportedCategory } from '@form/contracts';

import {
  calculateCostMicrounits,
  type CatalogExecutionConfig,
  CatalogJobError,
} from './catalog.js';
import { CatalogProviderError, type CatalogProvider } from './catalog-provider.js';
import type { Database, DatabaseClient } from './database.js';
import {
  createGarmentReferenceCollage,
  writeGarmentReferenceDebugGallery,
} from './garment-reference-collage.js';
import { withTransaction } from './database.js';
import { enqueueJob, type RemoteImageJob } from './jobs.js';
import { collageModel, createIdentityCollage } from './identity-collage.js';
import { IdempotencyConflictError, OwnedResourceNotFoundError } from './media.js';
import type { PrivateObjectStorage } from './storage.js';

export const lookModel = 'gpt-image-2.5-flare';
export const lookPlannerModel = 'gpt-5.4-mini';
export const lookPromptVersion = 'candid-iphone-identity-v3';

type CharacterRow = {
  id: string;
  state: CharacterSheet['state'];
  reference_asset_ids: string[];
  note: string | null;
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
  quality: Look['quality'];
  output_size: '1024x1280';
  provider_request_id: string | null;
  cost_microunits: string | null;
  failure_category: string | null;
  created_at: Date;
  finished_at: Date | null;
  wardrobe_item_ids: string[];
  item_bounding_boxes: Look['itemBoundingBoxes'];
};

const characterColumns = `id, state, reference_asset_ids, note, asset_id, active, model, quality,
  output_size, provider_request_id, cost_microunits, failure_category, created_at, finished_at`;
const lookColumns = `l.id, l.state, l.asset_id, l.character_sheet_id, l.parent_look_id,
  l.item_bounding_boxes, l.planned_concept, l.model, l.quality, l.output_size, l.provider_request_id,
  l.cost_microunits, l.failure_category, l.created_at, l.finished_at,
  COALESCE(array_agg(li.wardrobe_item_id ORDER BY li.ordinal) FILTER (WHERE li.wardrobe_item_id IS NOT NULL), '{}') AS wardrobe_item_ids`;

const mapCharacter = (row: CharacterRow): CharacterSheet => ({
  id: row.id,
  state: row.state,
  referenceAssetIds: row.reference_asset_ids,
  note: row.note,
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
  itemBoundingBoxes: row.item_bounding_boxes,
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
    const characterSheetId = randomUUID();
    // A photo collage is the reference asset. Do not enqueue a render or create a
    // derivative image: that would change the pixels the person approved.
    await client.query(
      `UPDATE character_sheets SET active=false WHERE account_id=$1 AND active`,
      [input.accountId],
    );
    await client.query(
      `INSERT INTO character_sheets(id,account_id,reference_asset_ids,note,state,model,quality,output_size,prompt_version,asset_id,active,cost_microunits,finished_at)
       VALUES($1,$2,$3,$4,'ready',$5,'high','864x1536',$5,$6,true,0,now())`,
      [
        characterSheetId,
        input.accountId,
        input.referenceAssetIds,
        input.note,
        collageModel,
        input.referenceAssetIds[0],
      ],
    );
    const body = { characterSheetId };
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
    original_asset_id: string;
  }>(
    `SELECT i.id,i.name,i.category,i.colors,i.notes,
       v.transparent_asset_id AS asset_id,
       COALESCE(a.reference_asset_id,sp.asset_id) AS original_asset_id
     FROM wardrobe_items i
     JOIN shelf_image_versions v ON v.id=i.current_shelf_image_version_id
     JOIN generation_attempts a ON a.id=v.generation_attempt_id
     JOIN source_photos sp ON sp.id=i.source_photo_id
     WHERE i.account_id=$1 AND i.deleted_at IS NULL AND i.state ${deliberate ? "IN ('owning','wanting')" : "='owning'"}
     ORDER BY i.created_at`,
    [accountId],
  );
}
function hasCore(items: Array<{ category: string }>) {
  const cats = new Set(items.map((i) => i.category));
  return cats.has('dress') || (cats.has('top') && (cats.has('pants') || cats.has('skirt')));
}

// The planner can suggest layers, but an automatic outfit must not turn into a
// pile of alternatives. Explicitly selected pieces stay untouched: the user is
// allowed to request an unusual combination on purpose.
export function normalizeAutomaticLookItems(
  itemIds: string[],
  candidates: Array<{ id: string; category: SupportedCategory }>,
  exactItemIds: string[],
) {
  const byId = new Map(candidates.map((item) => [item.id, item]));
  const exact = new Set(exactItemIds);
  const exactCategories = new Set(
    exactItemIds.map((id) => byId.get(id)?.category).filter(Boolean),
  );
  const automaticDress = itemIds.some((id) => !exact.has(id) && byId.get(id)?.category === 'dress');
  const useDress = !exactCategories.has('top') && !exactCategories.has('pants') && !exactCategories.has('skirt') && automaticDress;
  const used = new Set<string>();
  const result: string[] = [];
  // Process mandatory pieces first so an optional duplicate can never crowd one
  // of them out merely because the model listed it earlier.
  for (const id of [...itemIds.filter((id) => exact.has(id)), ...itemIds.filter((id) => !exact.has(id))]) {
    if (used.has(id)) continue;
    const item = byId.get(id);
    if (!item) continue;
    const { category } = item;
    if (exact.has(id)) {
      used.add(id);
      used.add(category === 'pants' || category === 'skirt' ? 'lower' : category);
      result.push(id);
      continue;
    }
    if (useDress && (category === 'top' || category === 'pants' || category === 'skirt')) continue;
    if (!useDress && category === 'dress') continue;
    const slot = category === 'pants' || category === 'skirt' ? 'lower' : category;
    if (used.has(slot)) continue;
    used.add(id);
    used.add(slot);
    result.push(id);
  }
  return result;
}

export function candidatesForLookPlan<T extends { id: string }>(
  candidates: T[],
  exactItemIds: string[],
  completeWithWardrobe: boolean,
) {
  if (completeWithWardrobe) return candidates;
  const exact = new Set(exactItemIds);
  return candidates.filter((item) => exact.has(item.id));
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
    occasion?: string | null;
    parentLookId: string | null;
    quality?: Look['quality'];
    preserveComposition?: boolean;
    completeWithWardrobe?: boolean;
    idempotencyKey: string;
  },
) {
  const completeWithWardrobe = input.completeWithWardrobe ?? true;
  const request = {
    exactItemIds: input.exactItemIds,
    categories: input.categories,
    ...(input.occasion ? { occasion: input.occasion } : {}),
    parentLookId: input.parentLookId,
    quality: input.quality ?? 'low',
    preserveComposition: input.preserveComposition ?? false,
    completeWithWardrobe,
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
    let preserved: { concept: LookConcept; characterId: string; assetId: string } | null = null;
    if (input.preserveComposition && !parentId)
      throw new InspirationValidationError('parent-required', 'Wähle einen fertigen Look.');
    if (parentId) {
      const parent = await client.query<{ ids: string[] }>(
        `SELECT COALESCE(array_agg(li.wardrobe_item_id ORDER BY li.ordinal),'{}') ids FROM looks l LEFT JOIN look_items li ON li.look_id=l.id WHERE l.id=$1 AND l.account_id=$2 AND l.state='ready' GROUP BY l.id`,
        [parentId, input.accountId],
      );
      if (!parent.rows[0]) throw new OwnedResourceNotFoundError();
      exactIds = parent.rows[0].ids;
      if (input.preserveComposition) {
        const original = await client.query<{
          planned_concept: LookConcept; character_sheet_id: string; asset_id: string;
        }>("SELECT planned_concept,character_sheet_id,asset_id FROM looks WHERE id=$1 AND account_id=$2 AND deleted_at IS NULL AND state='ready'", [parentId, input.accountId]);
        const row = original.rows[0];
        if (!row?.planned_concept || !row.asset_id) throw new OwnedResourceNotFoundError();
        preserved = { concept: row.planned_concept, characterId: row.character_sheet_id, assetId: row.asset_id };
      }
    }
    const candidates = await candidateItems(
      client,
      input.accountId,
      exactIds.length > 0 || input.categories.length > 0,
    );
    if (!completeWithWardrobe && !exactIds.length)
      throw new InspirationValidationError(
        'item-required',
        'Wähle mindestens ein Stück aus, bevor das Bildmodell den Look ergänzt.',
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
    if (!completeWithWardrobe && input.categories.length)
      throw new InspirationValidationError(
        'categories-require-wardrobe',
        'Kategorien können nur mit Stücken aus dem Schrank ergänzt werden.',
      );
    for (const category of input.categories)
      if (!candidates.rows.some((row) => row.category === category))
        throw new InspirationValidationError(
          'category-unavailable',
          `Für ${category} fehlt ein nutzbares Stück mit aktivem Katalogbild.`,
        );
    const lookId = randomUUID();
    await client.query(
      `INSERT INTO looks(id,account_id,character_sheet_id,parent_look_id,state,exact_item_ids,category_constraints,model,quality,output_size,prompt_version,planned_concept) VALUES($1,$2,$3,$4,'queued',$5,$6,$7,$9,'1024x1280',$8,$10)`,
      [
        lookId,
        input.accountId,
        preserved?.characterId ?? active.rows[0].id,
        parentId,
        exactIds,
        input.categories,
        lookModel,
        lookPromptVersion,
        input.quality ?? 'low',
        preserved ? JSON.stringify(preserved.concept) : null,
      ],
    );
    if (preserved)
      for (const [ordinal, itemId] of exactIds.entries())
        await client.query('INSERT INTO look_items(look_id,wardrobe_item_id,ordinal) VALUES($1,$2,$3)', [lookId, itemId, ordinal]);
    const jobId = await enqueueJob(client, {
      accountId: input.accountId,
      kind: 'generate-look',
      payload: { lookId, occasion: input.occasion ?? null, completeWithWardrobe, ...(preserved ? { referenceAssetId: preserved.assetId } : {}) },
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
    const request = { lookId: input.lookId };
    const prior = await replay<{ jobId: string; lookId: string }>(
      client,
      input.accountId,
      input.idempotencyKey,
      'retry-look',
      request,
    );
    if (prior) return prior;
    const row = await client.query(
      `UPDATE looks SET state='queued',failure_category=NULL,failure_detail=NULL,started_at=NULL,finished_at=NULL WHERE id=$1 AND account_id=$2 AND state='failed' RETURNING id`,
      [input.lookId, input.accountId],
    );
    if (!row.rows[0])
      throw new InspirationValidationError(
        'look-not-retryable',
        'Dieser Look kann nicht erneut versucht werden.',
      );
    const previous = await client.query<{ payload: { occasion?: string | null; referenceAssetId?: string; completeWithWardrobe?: boolean } }>(
      `SELECT payload FROM remote_image_jobs WHERE look_id=$1 AND account_id=$2 ORDER BY created_at DESC LIMIT 1`,
      [input.lookId, input.accountId],
    );
    const jobId = await enqueueJob(client, {
      accountId: input.accountId,
      kind: 'generate-look',
      payload: { ...previous.rows[0]?.payload, lookId: input.lookId, occasion: previous.rows[0]?.payload.occasion ?? null },
      idempotencyKey: `look-retry:${input.idempotencyKey}`,
    });
    await client.query('UPDATE remote_image_jobs SET look_id=$1 WHERE id=$2', [
      input.lookId,
      jobId,
    ]);
    const body = { jobId, lookId: input.lookId };
    await remember(client, input.accountId, input.idempotencyKey, 'retry-look', request, body);
    return body;
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
export function lookPrompt(
  concept: LookConcept,
  items: Array<{ name: string; category: string; colors: string[] }>,
  identityNote: string | null,
  completeWithWardrobe: boolean,
) {
  const garments = items.map((i) => `${i.name} (${i.category}; ${i.colors.join(', ')})`).join('; ');
  const garmentInstruction = completeWithWardrobe
    ? `Dress the person in exactly these referenced major garments: ${garments}.`
    : `Dress the person in these referenced garments: ${garments}.`;
  const completion = completeWithWardrobe
    ? 'Do not invent other major garments; plain incidental basics such as socks are allowed.'
    : 'Complete the outfit with coherent unreferenced garments where needed. Do not replace, restyle, hide, or obscure any referenced garment.';
  return `The first reference is an identity reference of one person, possibly a collage of cropped original photos. Every panel shows the same person. Preserve their facial likeness, hair, skin, and body proportions from those photos. Use it only for identity, not for its clothes, layout, or background.${identityNote ? ` Additional identity details: ${identityNote}.` : ''} Each remaining reference is one garment shown as a side-by-side reference: the clean generated shelf view is on the left and the cropped original photo is on the right. Use both views together for that one garment. Treat the original photo as the ground truth for colors, material, texture, construction, and distinctive details; use the shelf view to clarify its complete silhouette. Create one photorealistic 4:5 iPhone-style snapshot as if a friend naturally photographed the referenced person while ${concept.activity}, in ${concept.scene}. Mood: ${concept.mood}. ${concept.framing} framing. The person must not look directly at the camera. ${garmentInstruction} Every referenced garment must be fully visible and faithful to its reference. ${completion} Avoid selfies, posed portraits, illustrations, runway staging, extreme editorial styling, text, watermarks, and collages in the output. Shoes, trousers, skirts, and dresses must never be cropped when selected.`;
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
      // Only legacy queued collage jobs still reach this branch. New collages are ready as
      // soon as their single, finished collage asset is saved.
      const result = {
        pngBytes: await createIdentityCollage(refs),
        requestId: null,
        usage: { textInputTokens: 0, imageInputTokens: 0, outputTokens: 0, serviceTier: 'default', raw: { method: collageModel } },
      };
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
    const completeWithWardrobe =
      (job.payload as { completeWithWardrobe?: boolean }).completeWithWardrobe ?? true;
    const started = await database.query<{
      character_sheet_id: string;
      exact_item_ids: string[];
      category_constraints: SupportedCategory[];
      quality: Look['quality'];
      model: string;
      planned_concept: LookConcept | null;
      state: string;
    }>(
      `UPDATE looks SET state=CASE WHEN planned_concept IS NULL THEN 'planning' ELSE 'generating' END,started_at=COALESCE(started_at,now()) WHERE id=$1 AND account_id=$2 AND state IN ('queued','planning','generating') RETURNING character_sheet_id,exact_item_ids,category_constraints,model,quality,planned_concept,state`,
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
      const planningCandidates = candidatesForLookPlan(
        candidates.rows,
        row.exact_item_ids,
        completeWithWardrobe,
      );
      const planned = await provider.planLook({
        candidates: planningCandidates.map((i) => ({
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
        occasion: (job.payload as { occasion?: string | null }).occasion ?? null,
        model: lookPlannerModel,
        signal: controller.signal,
      });
      concept = planned.concept;
      itemIds = normalizeAutomaticLookItems(
        planned.itemIds,
        planningCandidates,
        row.exact_item_ids,
      );
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
    const character = await database.query<{ asset_id: string; note: string | null }>(
      'SELECT asset_id, note FROM character_sheets WHERE id=$1 AND account_id=$2',
      [row.character_sheet_id, job.accountId],
    );
    const selected = candidates.rows
      .filter((i) => itemIds.includes(i.id))
      .sort((a, b) => itemIds.indexOf(a.id) - itemIds.indexOf(b.id));
    if (!character.rows[0]?.asset_id || selected.length !== itemIds.length)
      throw new CatalogJobError('internal', 'Look references are no longer available.', false);
    const identityReference = await readAsset(
      database,
      storage,
      job.accountId,
      character.rows[0].asset_id,
    );
    const garmentReferences = await Promise.all(selected.map(async (item) => {
      const [shelfImage, originalImage] = await Promise.all([
        readAsset(database, storage, job.accountId, item.asset_id),
        readAsset(database, storage, job.accountId, item.original_asset_id),
      ]);
      return createGarmentReferenceCollage(shelfImage, originalImage);
    }));
    const debugDirectory = process.env.FORM_GARMENT_REFERENCE_DEBUG_DIR;
    if (debugDirectory) {
      try {
        const files = await writeGarmentReferenceDebugGallery({
          directory: debugDirectory,
          lookId: id,
          garments: selected.map((item, index) => ({
            id: item.id,
            name: item.name,
            collage: garmentReferences[index]!,
          })),
        });
        console.log(`Garment reference collages for look ${id}: ${files.join(', ')}`);
      } catch (error) {
        console.error(`Could not write garment reference collages for look ${id}.`, error);
      }
    }
    const refs = [identityReference, ...garmentReferences];
    const referenceAssetId = (job.payload as { referenceAssetId?: string }).referenceAssetId;
    if (referenceAssetId)
      refs.unshift(await readAsset(database, storage, job.accountId, referenceAssetId));
    const result = await provider.generateComposite({
      references: refs,
      prompt: referenceAssetId
        ? 'Recreate the first reference image with improved detail as one photorealistic 4:5 image. Preserve its composition, pose, outfit, person, lighting and background. The second reference shows the same person and is only for identity detail. References after the second show the garments and are only for fabric and construction detail. Do not change the scene or add garments, text, watermarks or collage panels.'
        : lookPrompt(concept, selected, character.rows[0].note, completeWithWardrobe),
      model: row.model,
      quality: row.quality,
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
    // Detection is best effort: never regenerate a paid image because localization failed.
    let itemBoundingBoxes: Look['itemBoundingBoxes'] = [];
    try {
      const localized = await provider.detect({
        jpegBytes: await sharp(result.pngBytes).jpeg({ quality: 90 }).toBuffer(),
        targets: selected.map(({ id, name, category, colors }) => ({ id, name, category, colors })),
        model: lookPlannerModel,
        signal: AbortSignal.timeout(30_000),
      });
      const seen = new Set<string>();
      itemBoundingBoxes = localized.detections.flatMap((detection) => {
        if (!itemIds.includes(detection.id) || seen.has(detection.id)) return [];
        seen.add(detection.id);
        return [{ wardrobeItemId: detection.id, boundingBox: detection.boundingBox }];
      });
    } catch (error) {
      console.warn('Look item detection failed; using category origins.', { lookId: id, error });
    }
    const cost = calculateCostMicrounits(result.usage, config.pricing);
    await database.query(
      `UPDATE looks SET state='ready',asset_id=$3,provider_request_id=$4,provider_usage=$5,cost_microunits=$6,item_bounding_boxes=$7,finished_at=now() WHERE id=$1 AND account_id=$2`,
      [id, job.accountId, assetId, result.requestId, JSON.stringify(result.usage.raw), cost, JSON.stringify(itemBoundingBoxes)],
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

import { createHash, randomUUID } from 'node:crypto';

import { GetObjectCommand, PutObjectCommand } from '@aws-sdk/client-s3';
import {
  lookSettingsSchema,
  type CharacterSheet,
  type Look,
  type LookCompletion,
  type LookConcept,
  type LookOccasion,
  type LookReason,
  type LookStyle,
  type SupportedCategory,
} from '@form/contracts';

import {
  calculateCostMicrounits,
  type CatalogExecutionConfig,
  CatalogJobError,
} from './catalog.js';
import { CatalogProviderError, type CatalogProvider, type Warmth } from './catalog-provider.js';
import type { Database, DatabaseClient } from './database.js';
import {
  createGarmentReferenceCollage,
  createGarmentReferenceBoard,
  writeGarmentReferenceDebugGallery,
} from './garment-reference-collage.js';
import { withTransaction } from './database.js';
import { adjustOutfit, pickAnchor, warmthClash, type PieceUsage } from './look-proposals.js';
import { pickShot, shotPrompt, shotStyle, shotWeights } from './look-shots.js';
import { enqueueJob, type RemoteImageJob } from './jobs.js';
import { collageModel, prepareIdentityReference, createIdentityCollage } from './identity-collage.js';
import { IdempotencyConflictError, OwnedResourceNotFoundError } from './media.js';
import type { PrivateObjectStorage } from './storage.js';
import sharp from 'sharp';

export const lookModel = 'gpt-image-2.5-flare';
export const lookPlannerModel = 'gpt-5.4-mini';
export const lookPromptVersion = 'real-camera-identity-v6';
export const tryOnPromptVersion = 'try-on-v1';

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
  feed_asset_id: string | null;
  character_sheet_id: string;
  parent_look_id: string | null;
  base_asset_id: string | null;
  liked: boolean;
  planned_concept: LookConcept | null;
  category_constraints: string[];
  job_payload: Record<string, unknown> | null;
  model: string;
  quality: Look['quality'];
  output_size: '1024x1280' | '768x960';
  provider_request_id: string | null;
  cost_microunits: string | null;
  failure_category: string | null;
  created_at: Date;
  finished_at: Date | null;
  wardrobe_item_ids: string[];
  proposal: boolean;
  proposal_reasons: LookReason[] | null;
};

const characterColumns = `id, state, reference_asset_ids, note, asset_id, active, model, quality,
  output_size, provider_request_id, cost_microunits, failure_category, created_at, finished_at`;
const lookColumns = `l.id, l.state, l.asset_id, l.feed_asset_id, l.character_sheet_id, l.parent_look_id,
  l.base_asset_id, l.liked_at IS NOT NULL AS liked, l.planned_concept, l.category_constraints, l.proposal, l.proposal_reasons,
  (SELECT payload FROM remote_image_jobs rj WHERE rj.look_id=l.id ORDER BY rj.created_at DESC LIMIT 1) AS job_payload,
  l.model, l.quality,
  COALESCE(pa.pixel_width::text || 'x' || pa.pixel_height::text,
    CASE WHEN (SELECT payload->>'outputSize' FROM remote_image_jobs rj WHERE rj.look_id=l.id ORDER BY rj.created_at DESC LIMIT 1) = '768x960'
      THEN '768x960' ELSE '1024x1280' END) AS output_size,
  l.provider_request_id,
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
  feedAssetId: row.feed_asset_id,
  wardrobeItemIds: row.wardrobe_item_ids,
  characterSheetId: row.character_sheet_id,
  parentLookId: row.parent_look_id,
  baseAssetId: row.base_asset_id,
  liked: row.liked,
  concept: row.planned_concept,
  settings: lookSettings(row),
  model: row.model,
  quality: row.quality,
  size: row.output_size,
  providerRequestId: row.provider_request_id,
  costMicrounits: row.cost_microunits === null ? null : Number(row.cost_microunits),
  failureCategory: row.failure_category,
  createdAt: row.created_at.toISOString(),
  finishedAt: row.finished_at?.toISOString() ?? null,
  ...(row.proposal ? { reasons: row.proposal_reasons ?? [] } : {}),
});
// Reads the composer choices back from the look's job payload, see createLook.
const lookSettings = (row: LookRow): Look['settings'] => {
  const payload = row.job_payload;
  if (row.base_asset_id || !payload) return null;
  const parsed = lookSettingsSchema.safeParse({
    occasion: payload.occasion ?? null,
    // Upgrades do not repeat the style, but their shot still implies it.
    style: shotStyle(row.planned_concept?.shot) ?? payload.style ?? 'candid',
    completion: payload.focus ? 'selected' : payload.completeWithWardrobe === false ? 'model' : 'wardrobe',
    categories: row.category_constraints,
  });
  return parsed.success ? parsed.data : null;
};
const hash = (value: unknown) => createHash('sha256').update(JSON.stringify(value)).digest('hex');
// Looks render at a reduced size. Older looks keep their stored 1024x1280.
const lookOutputSize = '768x960' as const;

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
    created_at: Date;
    state: string;
  }>(
    `SELECT i.id,i.name,i.category,i.colors,i.notes,i.created_at,i.state,
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

/**
 * Two proposals read as the same outfit when the pieces added around the
 * user's exact pieces change in at most one slot, e.g. only the necklace.
 */
export function similarOutfit(a: string[], b: string[], exact: string[]) {
  const added = (ids: string[]) => ids.filter((id) => !exact.includes(id));
  const [left, right] = [added(a), added(b)];
  const size = Math.max(left.length, right.length);
  const shared = left.filter((id) => right.includes(id)).length;
  return size >= 2 && size - shared <= 1;
}

/**
 * Warmth of [items], tagging the ones never tagged before in one call. A
 * failed call only costs the warmth hints, never the plan.
 */
async function warmthOf(
  database: Database,
  provider: CatalogProvider,
  accountId: string,
  items: Array<{ id: string; name: string; category: SupportedCategory; colors: string[]; notes: string | null }>,
  signal?: AbortSignal,
): Promise<Map<string, Warmth>> {
  const known = await database.query<{ wardrobe_item_id: string; warmth: Warmth }>(
    'SELECT wardrobe_item_id, warmth FROM item_warmth WHERE account_id=$1 AND wardrobe_item_id = ANY($2::uuid[])',
    [accountId, items.map((item) => item.id)],
  );
  const warmth = new Map(known.rows.map((row) => [row.wardrobe_item_id, row.warmth]));
  const untagged = items.filter((item) => !warmth.has(item.id));
  if (!untagged.length) return warmth;
  try {
    const tagged = await provider.classifyWarmth({
      items: untagged.map((item) => ({
        id: item.id,
        metadata: { name: item.name, category: item.category, colors: item.colors, notes: item.notes },
      })),
      model: lookPlannerModel,
      signal,
    });
    for (const [id, level] of tagged) {
      if (!untagged.some((item) => item.id === id)) continue;
      warmth.set(id, level);
      await database.query(
        'INSERT INTO item_warmth (wardrobe_item_id, account_id, warmth) VALUES ($1,$2,$3) ON CONFLICT DO NOTHING',
        [id, accountId, level],
      );
    }
  } catch (error) {
    console.warn('Warmth tagging failed; planning without it.', error);
  }
  return warmth;
}

/** How often each piece appeared in finished looks, and whether among [recent]. */
async function pieceUsage(
  database: Database,
  accountId: string,
  recent: Array<{ ids: string[] }>,
): Promise<Map<string, PieceUsage>> {
  const latest = new Set(recent.flatMap((look) => look.ids));
  const counts = await database.query<{ id: string; uses: string }>(
    `SELECT li.wardrobe_item_id id,count(*) uses FROM look_items li JOIN looks l ON l.id=li.look_id
     WHERE l.account_id=$1 AND l.state='ready' AND l.deleted_at IS NULL GROUP BY li.wardrobe_item_id`,
    [accountId],
  );
  const usage = new Map<string, PieceUsage>();
  for (const row of counts.rows) usage.set(row.id, { uses: Number(row.uses), recent: latest.has(row.id) });
  return usage;
}

export type LookFocus = 'upper' | 'lower' | 'feet';

/**
 * The body zone a `selected` completion photo frames, from the picked pieces'
 * categories. Null when the pieces span zones (a jacket with shoes, or a dress)
 * and only a full-body photo could show them. Bags and accessories fit any zone.
 */
export function lookFocus(categories: string[]): LookFocus | null {
  const has = (...wanted: string[]) => categories.some((c) => wanted.includes(c));
  const upper = has('top', 'jacket', 'hat', 'scarf');
  const lower = has('pants', 'skirt');
  const shoes = has('shoes');
  if (has('dress') || (upper && (lower || shoes))) return null;
  if (lower) return 'lower';
  if (shoes) return 'feet';
  return 'upper';
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

// History handed to the planner as combinations to avoid. Mandated items are
// stripped out: otherwise "avoid recent combinations" fights "exact item IDs are
// mandatory" once the same pinned items were worn before, and the planner drops
// them, which fails the plan. Scene and mood stay avoidable through the concept.
export function recentForLookPlan(
  recent: Array<{ ids: string[]; planned_concept: LookConcept | null }>,
  exactItemIds: string[],
) {
  const exact = new Set(exactItemIds);
  return recent.map((look) => ({
    itemIds: look.ids.filter((itemId) => !exact.has(itemId)),
    concept: look.planned_concept,
  }));
}

export async function listLooks(database: Database, accountId: string): Promise<Look[]> {
  const rows = await database.query<LookRow>(
    `SELECT ${lookColumns} FROM looks l LEFT JOIN private_assets pa ON pa.id=l.asset_id LEFT JOIN look_items li ON li.look_id=l.id LEFT JOIN wardrobe_items wi ON wi.id=li.wardrobe_item_id AND wi.deleted_at IS NULL WHERE l.account_id=$1 AND l.deleted_at IS NULL AND NOT l.proposal GROUP BY l.id, pa.pixel_width, pa.pixel_height ORDER BY l.created_at DESC`,
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
    style?: LookStyle;
    parentLookId: string | null;
    quality?: Look['quality'];
    preserveComposition?: boolean;
    completeWithWardrobe?: boolean;
    completion?: LookCompletion;
    baseAssetId?: string;
    reshoot?: boolean;
    // Plan only and stop at `proposed`, see renderLookProposal.
    propose?: boolean;
    // Pieces the planner must leave out, see proposeLooks.
    excludedItemIds?: string[];
    idempotencyKey: string;
  },
) {
  const completion =
    input.completion ?? ((input.completeWithWardrobe ?? true) ? 'wardrobe' : 'model');
  const completeWithWardrobe = completion === 'wardrobe';
  const request = {
    exactItemIds: input.exactItemIds,
    categories: input.categories,
    ...(input.occasion ? { occasion: input.occasion } : {}),
    ...(input.style && input.style !== 'candid' ? { style: input.style } : {}),
    parentLookId: input.parentLookId,
    quality: input.quality ?? 'low',
    preserveComposition: input.preserveComposition ?? false,
    completeWithWardrobe,
    // Only when new, so replays of requests made before `completion` still match.
    ...(completion === 'selected' ? { completion } : {}),
    ...(input.baseAssetId ? { baseAssetId: input.baseAssetId } : {}),
    ...(input.reshoot ? { reshoot: true } : {}),
    ...(input.propose ? { propose: true } : {}),
    ...(input.excludedItemIds?.length ? { excludedItemIds: input.excludedItemIds } : {}),
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
    if (input.baseAssetId) {
      if (!input.exactItemIds.length)
        throw new InspirationValidationError('item-required', 'Wähle mindestens ein Stück zum Anprobieren.');
      if (input.parentLookId || input.categories.length)
        throw new InspirationValidationError('try-on-invalid', 'Eine Anprobe nutzt nur dein Foto und die gewählten Stücke.');
      const base = await client.query(
        `SELECT 1 FROM private_assets WHERE id=$1 AND account_id=$2 AND purpose='source-photo' AND state='ready' AND deleted_at IS NULL`,
        [input.baseAssetId, input.accountId],
      );
      if (!base.rows[0])
        throw new InspirationValidationError('try-on-photo-missing', 'Dein Foto ist nicht mehr verfügbar. Lade es neu hoch.');
    }
    let exactIds = input.exactItemIds;
    let parentId = input.parentLookId;
    let preserved: { concept: LookConcept; characterId: string; assetId: string } | null = null;
    // "Same outfit, other perspective": the parent's concept with a new shot,
    // and the parent's job settings, so only the camera changes.
    let reshot: { concept: LookConcept; payload: Record<string, unknown> } | null = null;
    if (input.propose && (parentId || input.baseAssetId))
      throw new InspirationValidationError('proposal-invalid', 'Vorschläge gibt es nur für neue Looks.');
    if ((input.preserveComposition || input.reshoot) && !parentId)
      throw new InspirationValidationError('parent-required', 'Wähle einen fertigen Look.');
    if (input.reshoot && input.preserveComposition)
      throw new InspirationValidationError('reshoot-invalid', 'Wähle entweder eine neue Perspektive oder bessere Qualität.');
    if (parentId) {
      const parent = await client.query<{ ids: string[] }>(
        `SELECT COALESCE(array_agg(li.wardrobe_item_id ORDER BY li.ordinal),'{}') ids FROM looks l LEFT JOIN look_items li ON li.look_id=l.id WHERE l.id=$1 AND l.account_id=$2 AND l.state='ready' GROUP BY l.id`,
        [parentId, input.accountId],
      );
      if (!parent.rows[0]) throw new OwnedResourceNotFoundError();
      exactIds = parent.rows[0].ids;
      if (input.reshoot) {
        const original = await client.query<{ planned_concept: LookConcept | null; base_asset_id: string | null; payload: Record<string, unknown> | null }>(
          `SELECT l.planned_concept,l.base_asset_id,(SELECT payload FROM remote_image_jobs rj WHERE rj.look_id=l.id ORDER BY rj.created_at DESC LIMIT 1) payload FROM looks l WHERE l.id=$1 AND l.account_id=$2 AND l.deleted_at IS NULL`,
          [parentId, input.accountId],
        );
        const row = original.rows[0];
        if (!row?.planned_concept || row.base_asset_id)
          throw new InspirationValidationError('reshoot-unavailable', 'Für diesen Look gibt es keine andere Perspektive.');
        const { lookId: _lookId, referenceAssetId: _reference, ...payload } = row.payload ?? {};
        const style = shotStyle(row.planned_concept.shot) ?? (payload.style as LookStyle | undefined) ?? 'candid';
        reshot = {
          concept: {
            ...row.planned_concept,
            shot: pickShot(await shotWeights(client, input.accountId), style, row.planned_concept.shot),
          },
          payload: { ...payload, style },
        };
      }
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
    const focus =
      completion === 'selected'
        ? lookFocus(
            exactIds.map((id) => candidates.rows.find((row) => row.id === id)?.category ?? ''),
          )
        : null;
    if (completion === 'selected' && !focus)
      throw new InspirationValidationError(
        'focus-unavailable',
        'Nur deine Stücke geht, wenn alle im selben Bildausschnitt liegen, etwa nur Oberteile oder nur Schuhe.',
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
    // The legacy column is constrained to 1024x1280. The job payload records the
    // requested size; ready looks report the actual dimensions of their asset.
    await client.query(
      `INSERT INTO looks(id,account_id,character_sheet_id,parent_look_id,state,exact_item_ids,category_constraints,model,quality,output_size,prompt_version,planned_concept,base_asset_id,proposal) VALUES($1,$2,$3,$4,'queued',$5,$6,$7,$9,'1024x1280',$8,$10,$11,$12)`,
      [
        lookId,
        input.accountId,
        preserved?.characterId ?? active.rows[0].id,
        parentId,
        exactIds,
        input.categories,
        lookModel,
        input.baseAssetId ? tryOnPromptVersion : lookPromptVersion,
        input.quality ?? 'low',
        preserved || reshot ? JSON.stringify((preserved ?? reshot)!.concept) : null,
        input.baseAssetId ?? null,
        input.propose ?? false,
      ],
    );
    // The photo stays pickable, and deletable, from the try-on photo list.
    if (input.baseAssetId)
      await client.query(
        `INSERT INTO try_on_photos (account_id, asset_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`,
        [input.accountId, input.baseAssetId],
      );
    if (preserved || reshot)
      for (const [ordinal, itemId] of exactIds.entries())
        await client.query('INSERT INTO look_items(look_id,wardrobe_item_id,ordinal) VALUES($1,$2,$3)', [lookId, itemId, ordinal]);
    const jobId = await enqueueJob(client, {
      accountId: input.accountId,
      kind: input.propose ? 'plan-look' : 'generate-look',
      payload: {
        lookId,
        occasion: input.occasion ?? null,
        style: input.style ?? 'candid',
        completeWithWardrobe,
        ...(focus ? { focus } : {}),
        ...(input.excludedItemIds?.length ? { excludedItemIds: input.excludedItemIds } : {}),
        outputSize: lookOutputSize,
        ...(preserved ? { referenceAssetId: preserved.assetId } : {}),
        ...reshot?.payload,
      },
      idempotencyKey: `look:${input.idempotencyKey}`,
    });
    await client.query('UPDATE remote_image_jobs SET look_id=$1 WHERE id=$2', [lookId, jobId]);
    const body = { jobId, lookId };
    await remember(client, input.accountId, input.idempotencyKey, 'create-look', request, body);
    return body;
  });
}
/** Hearts a look. The heart also weights its shot type for future looks. */
export async function setLookLiked(
  database: Database,
  input: { accountId: string; lookId: string; liked: boolean },
) {
  const row = await database.query(
    `UPDATE looks SET liked_at=CASE WHEN $3 THEN COALESCE(liked_at, now()) ELSE NULL END WHERE id=$1 AND account_id=$2 AND deleted_at IS NULL RETURNING id`,
    [input.lookId, input.accountId, input.liked],
  );
  if (!row.rows[0]) throw new OwnedResourceNotFoundError();
  return { liked: input.liked };
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
// Proposals of the last batch, newest first. Failed ones stay so the client can drop them.
export async function listLookProposals(database: Database, accountId: string): Promise<Look[]> {
  const rows = await database.query<LookRow>(
    `SELECT ${lookColumns} FROM looks l LEFT JOIN private_assets pa ON pa.id=l.asset_id LEFT JOIN look_items li ON li.look_id=l.id LEFT JOIN wardrobe_items wi ON wi.id=li.wardrobe_item_id AND wi.deleted_at IS NULL WHERE l.account_id=$1 AND l.deleted_at IS NULL AND l.proposal GROUP BY l.id, pa.pixel_width, pa.pixel_height ORDER BY l.created_at DESC`,
    [accountId],
  );
  return rows.rows.map(mapLook);
}

/** Replaces the open proposals with `count` freshly planned ones. Nothing is rendered or charged. */
export async function proposeLooks(
  database: Database,
  input: Omit<Parameters<typeof createLook>[1], 'propose' | 'parentLookId'> & {
    count: number;
    append?: boolean;
    discardLookIds?: string[];
  },
) {
  const { count, append, discardLookIds, ...look } = input;
  await database.query(
    // A replayed batch keeps its own proposals.
    `UPDATE looks l SET deleted_at=now() WHERE l.account_id=$1 AND l.proposal AND l.deleted_at IS NULL
     AND ($3 OR l.id = ANY($4::uuid[]))
     AND NOT EXISTS (SELECT 1 FROM remote_image_jobs rj WHERE rj.look_id=l.id AND rj.idempotency_key LIKE $2)`,
    [input.accountId, `look:${input.idempotencyKey}:%`, !append, discardLookIds ?? []],
  );
  await database.query(
    `UPDATE remote_image_jobs rj SET state='cancelled' FROM looks l
     WHERE rj.look_id=l.id AND rj.kind='plan-look' AND rj.state='queued' AND l.account_id=$1 AND l.deleted_at IS NOT NULL`,
    [input.accountId],
  );
  const lookIds: string[] = [];
  // Sequential, so each planning job sees the same inputs but its own idempotency key.
  for (let index = 0; index < count; index += 1) {
    const created = await createLook(database, {
      ...look,
      parentLookId: null,
      propose: true,
      idempotencyKey: `${input.idempotencyKey}:${index}`,
    });
    lookIds.push(created.lookId);
  }
  return { lookIds };
}

/**
 * Applies swipe marks to every open proposal right away, see adjustOutfit.
 * No planner call: a swap or a kept piece shows up in milliseconds.
 */
export async function adjustLookProposals(
  database: Database,
  input: { accountId: string; keepItemIds: string[]; excludeItemIds: string[] },
) {
  await withTransaction(database, async (client) => {
    // Quick taps arrive back to back; one adjustment at a time per account.
    await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [`${input.accountId}:proposals`]);
    const pool = await candidateItems(client, input.accountId, true);
    const warmth = await client.query<{ wardrobe_item_id: string; warmth: Warmth }>(
      'SELECT wardrobe_item_id, warmth FROM item_warmth WHERE account_id=$1',
      [input.accountId],
    );
    const uses = await client.query<{ id: string; uses: string }>(
      `SELECT li.wardrobe_item_id id,count(*) uses FROM look_items li JOIN looks l ON l.id=li.look_id
       WHERE l.account_id=$1 AND l.state='ready' AND l.deleted_at IS NULL GROUP BY li.wardrobe_item_id`,
      [input.accountId],
    );
    const warmthById = new Map(warmth.rows.map((row) => [row.wardrobe_item_id, row.warmth]));
    const usesById = new Map(uses.rows.map((row) => [row.id, Number(row.uses)]));
    const pieces = new Map(
      pool.rows
        .filter((item) => item.state === 'owning' || input.keepItemIds.includes(item.id))
        .map((item) => [
          item.id,
          { id: item.id, category: item.category, warmth: warmthById.get(item.id) ?? null, uses: usesById.get(item.id) ?? 0 },
        ]),
    );
    const keep = input.keepItemIds.flatMap((id) => pieces.get(id) ?? []);
    const open = await client.query<{ id: string; ids: string[] }>(
      `SELECT l.id, COALESCE(array_agg(li.wardrobe_item_id ORDER BY li.ordinal) FILTER (WHERE li.wardrobe_item_id IS NOT NULL),'{}') ids
       FROM looks l LEFT JOIN look_items li ON li.look_id=l.id
       WHERE l.account_id=$1 AND l.proposal AND l.state='proposed' AND l.deleted_at IS NULL GROUP BY l.id`,
      [input.accountId],
    );
    for (const look of open.rows) {
      const outfit = look.ids.flatMap((id) => pieces.get(id) ?? []);
      const next = adjustOutfit({ outfit, keep, exclude: input.excludeItemIds, pool: [...pieces.values()] });
      if (next.length === look.ids.length && next.every((id) => look.ids.includes(id))) continue;
      await client.query('DELETE FROM look_items WHERE look_id=$1', [look.id]);
      for (const [ordinal, itemId] of next.entries())
        await client.query('INSERT INTO look_items(look_id,wardrobe_item_id,ordinal) VALUES($1,$2,$3)', [look.id, itemId, ordinal]);
    }
  });
  return listLookProposals(database, input.accountId);
}

/** Renders a picked proposal: it leaves the proposals and is charged like any new look. */
export async function renderLookProposal(
  database: Database,
  input: { accountId: string; lookId: string; quality?: Look['quality']; idempotencyKey: string },
) {
  return withTransaction(database, async (client) => {
    const request = { lookId: input.lookId, quality: input.quality ?? 'low' };
    const prior = await replay<{ jobId: string; lookId: string }>(
      client, input.accountId, input.idempotencyKey, 'render-look-proposal', request,
    );
    if (prior) return prior;
    const row = await client.query(
      `UPDATE looks SET proposal=false,state='queued',quality=$3,finished_at=NULL WHERE id=$1 AND account_id=$2 AND proposal AND state='proposed' AND deleted_at IS NULL RETURNING id`,
      [input.lookId, input.accountId, request.quality],
    );
    if (!row.rows[0])
      throw new InspirationValidationError('proposal-unavailable', 'Dieser Vorschlag ist nicht mehr verfügbar.');
    const plan = await client.query<{ payload: Record<string, unknown> }>(
      `SELECT payload FROM remote_image_jobs WHERE look_id=$1 AND account_id=$2 ORDER BY created_at DESC LIMIT 1`,
      [input.lookId, input.accountId],
    );
    const jobId = await enqueueJob(client, {
      accountId: input.accountId,
      kind: 'generate-look',
      payload: { ...plan.rows[0]?.payload, lookId: input.lookId },
      idempotencyKey: `look-render:${input.idempotencyKey}`,
    });
    await client.query('UPDATE remote_image_jobs SET look_id=$1 WHERE id=$2', [input.lookId, jobId]);
    const body = { jobId, lookId: input.lookId };
    await remember(client, input.accountId, input.idempotencyKey, 'render-look-proposal', request, body);
    return body;
  });
}
export async function generationCosts(database: Database, accountId: string, week?: string) {
  const timeFilter = weekToRange(week);
  const params: (string | Date)[] = [accountId];
  let dateClause = '';
  if (timeFilter) {
    params.push(timeFilter.start, timeFilter.end);
    dateClause = ' AND created_at >= $2 AND created_at < $3';
  }
  const result = await database.query<{
    look_total: string;
    successful: string;
    character_total: string;
    wardrobe_total: string;
    wardrobe_requests: string;
    detection_total: string;
    detection_requests: string;
  }>(
    `SELECT
       COALESCE((SELECT sum(cost_microunits) FROM looks WHERE account_id=$1${dateClause}),0) look_total,
       COALESCE((SELECT count(*) FROM looks WHERE account_id=$1 AND state='ready'${dateClause}),0) successful,
       COALESCE((SELECT sum(cost_microunits) FROM character_sheets WHERE account_id=$1${dateClause}),0) character_total,
       COALESCE((SELECT sum(cost_microunits) FROM generation_attempts WHERE account_id=$1${dateClause}),0) wardrobe_total,
       COALESCE((SELECT count(*) FROM generation_attempts WHERE account_id=$1 AND cost_microunits IS NOT NULL${dateClause}),0) wardrobe_requests,
       COALESCE((SELECT sum(cost_microunits) FROM detection_attempts WHERE account_id=$1${dateClause}),0) detection_total,
       COALESCE((SELECT count(*) FROM detection_attempts WHERE account_id=$1 AND cost_microunits IS NOT NULL${dateClause}),0) detection_requests`,
    params,
  );
  const r = result.rows[0]!;
  const total = Number(r.look_total),
    successful = Number(r.successful);
  return {
    lookTotalMicrounits: total,
    successfulLookCount: successful,
    averageSuccessfulLookMicrounits: successful ? Math.round(total / successful) : 0,
    characterSheetTotalMicrounits: Number(r.character_total),
    wardrobeTotalMicrounits: Number(r.wardrobe_total),
    wardrobeRequestCount: Number(r.wardrobe_requests),
    detectionTotalMicrounits: Number(r.detection_total),
    detectionRequestCount: Number(r.detection_requests),
  };
}

function weekToRange(week?: string): { start: Date; end: Date } | null {
  if (!week) return null;
  const match = week.match(/^(\d{4})-W(\d{2})$/);
  if (!match) return null;
  const year = Number(match[1]);
  const weekNum = Number(match[2]);
  if (weekNum < 1 || weekNum > 53) return null;
  // ISO week: week 1 contains the year's first Thursday.
  // Jan 4 is always in week 1. Find the Monday of week 1, then offset.
  const jan4 = new Date(Date.UTC(year, 0, 4));
  const dayOfWeek = jan4.getUTCDay() || 7; // Mon=1 … Sun=7
  const week1Monday = new Date(Date.UTC(year, 0, 4 - dayOfWeek + 1));
  const start = new Date(week1Monday.getTime() + (weekNum - 1) * 7 * 86400000);
  const end = new Date(start.getTime() + 7 * 86400000);
  return { start, end };
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
  contentType = 'image/png',
) {
  const id = randomUUID(),
    objectKey = `accounts/${accountId}/inspiration/${purpose}/${id}`;
  const result = await storage.client.send(
    new PutObjectCommand({
      Bucket: storage.bucket,
      Key: objectKey,
      Body: bytes,
      ContentType: contentType,
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
    `INSERT INTO private_assets(id,account_id,purpose,object_key,object_version_id,content_type,byte_size,pixel_width,pixel_height,state,ready_at) VALUES($1,$2,$3,$4,$5,$9,$6,$7,$8,'ready',now())`,
    [id, accountId, purpose, objectKey, result.VersionId, bytes.byteLength, width, height, contentType],
  );
  return id;
}
// Feed cards show looks at phone width, so the multi-megabyte PNG original is
// shrunk to a WebP of this width for them.
const feedWidth = 800;
async function writeFeedAsset(
  database: Database,
  storage: PrivateObjectStorage,
  accountId: string,
  original: Buffer,
) {
  const { data, info } = await sharp(original)
    .resize({ width: feedWidth, withoutEnlargement: true })
    .webp({ quality: 82 })
    .toBuffer({ resolveWithObject: true });
  return writeAsset(database, storage, accountId, 'look', data, info.width, info.height, 'image/webp');
}
// Gives every ready look made before feed assets existed its feed copy.
export async function backfillLookFeedAssets(
  database: Database,
  storage: PrivateObjectStorage,
): Promise<{ created: number; failed: number }> {
  const { rows } = await database.query<{ id: string; account_id: string; asset_id: string }>(
    `SELECT id,account_id,asset_id FROM looks WHERE state='ready' AND asset_id IS NOT NULL AND feed_asset_id IS NULL`,
  );
  let created = 0;
  let failed = 0;
  for (const row of rows) {
    try {
      const original = await readAsset(database, storage, row.account_id, row.asset_id);
      const feedAssetId = await writeFeedAsset(database, storage, row.account_id, original);
      await database.query(`UPDATE looks SET feed_asset_id=$2 WHERE id=$1`, [row.id, feedAssetId]);
      created += 1;
    } catch (error) {
      failed += 1;
      console.error(`Look ${row.id}: ${error instanceof Error ? error.message : error}`);
    }
  }
  return { created, failed };
}
// The camera sentence of the Look prompt per style. All three read as photos a
// friend took on a phone, not a photographer's shoot. `framing` is null for a
// full outfit and a body-zone sentence for a `selected` completion.
const lookStylePrompts: Record<LookStyle, (concept: LookConcept, framing: string | null) => string> = {
  candid: (c, framing) =>
    `Create one photorealistic 4:5 snapshot as if a friend casually took it on an iPhone while the referenced person was ${c.activity}, in ${c.scene}. ${framing ?? `${c.framing} framing.`} Keep the moment casual and avoid runway staging. Preserve the primary identity photo's head angle, gaze, and expression; looking toward the camera is allowed when the reference does.`,
  street: (c, framing) =>
    `Create one photorealistic 4:5 outfit photo that a friend took on an iPhone of the referenced person in ${c.scene}, casually posing for a fit pic while ${c.activity}. ${framing ?? 'Full-body framing, head to shoes, slightly off-centre, with a slightly tilted horizon.'} Smartphone look: deep depth of field with the background mostly in focus and typical phone processing, no telephoto compression or creamy bokeh.`,
  mirror: (c, framing) =>
    `Create one photorealistic 4:5 mirror selfie: the referenced person holds a smartphone and photographs their reflection in a mirror in ${c.scene}. ${framing ? `In the mirror: ${framing}` : 'The phone partly covers one side of the face. Show the full outfit in the mirror, head to shoes.'} Casual real-world surroundings.`,
};

// Light follows the occasion: parties and nights out get the direct-flash
// point-and-shoot look, everything else stays in available light. Without an
// occasion the scene decides.
const flashLight =
  'a direct on-camera flash like a compact point-and-shoot or Fujifilm X100 at night: hard flash on the person, crisp flash shadows behind them, the background falling off into darkness with warm ambient light, visible film-like grain, and a hint of motion blur';
function lookLighting(occasion: string | null) {
  if (occasion === 'party' || occasion === 'night-out') return `Light it with ${flashLight}.`;
  if (occasion) return 'Use natural available light as it happens, with no added studio lighting.';
  return `If the scene is at night or at an indoor event, light it with ${flashLight}. Otherwise use natural available light.`;
}

const unpolished =
  'It must look like a real, unretouched snapshot, not an AI image: natural skin texture, sensor noise or grain, framing that is a little off with the horizon slightly crooked, a stranger or an object cut off at the edge, some motion blur, blown highlights or crushed shadows where the camera would clip. The person stands or moves; they are not seated. Avoid cinematic color grading, creamy bokeh, perfect composition, studio lighting, retouched skin, perfect symmetry, and any commercial, editorial or stock-photo look.';

// The two cameras feed photos are taken with. Drawn per look, so the feed
// mixes both; nights and parties always get the flash.
export const lookCameras = {
  iphone:
    'Shot on an iPhone main camera by a friend: deep depth of field, typical phone HDR and sharpening, slightly flat colors, nothing staged.',
  flash:
    'Shot on a Fujifilm X100 with the built-in flash fired directly, also in daylight: hard frontal flash, a crisp flash shadow behind the person, slightly blown skin highlights, punchy colors, visible grain.',
} as const;
export type LookCamera = keyof typeof lookCameras;

export function pickCamera(occasion: string | null, random: () => number = Math.random): LookCamera {
  if (occasion === 'party' || occasion === 'night-out') return 'flash';
  return random() < 0.5 ? 'flash' : 'iphone';
}

const lookFocusFraming: Record<LookFocus, string> = {
  upper: 'Frame from about the waist up so the referenced garments fill the frame; nothing below the waist is visible.',
  lower: 'Frame from the waist down to the feet so the referenced garments fill the frame; the face and upper body stay out of frame.',
  feet: 'Frame close on the lower legs and feet so the referenced shoes fill the frame; the upper body stays out of frame.',
};

const garmentPairing = 'Each view pairs the clean generated shelf view on the left with the cropped original photo on the right. Treat the original photo as the ground truth for colors, material, texture, construction, and distinctive details; use the shelf view to clarify its complete silhouette.';

/**
 * The prompt of a try-on: the first reference is the user's own photo.
 * Worded as recreating that photo with a given outfit, like the quality
 * upgrade. Asking to change the clothes on a real photo was rejected as sexual
 * by the image model's safety filter every time, whatever the photo showed.
 */
export function tryOnPrompt(items: Array<{ name: string; category: string; colors: string[] }>) {
  const garments = items.map((i) => `${i.name} (${i.category}; ${i.colors.join(', ')})`).join('; ');
  const references = items.length > 1
    ? `The second reference is one ordered board of clothing items. Its cells are row-major, from left to right and then top to bottom, matching this order: ${items.map((item, index) => `${index + 1}. ${item.name}`).join('; ')}. ${garmentPairing} Use each cell only for its matching item.`
    : `The second reference shows the clothing item. ${garmentPairing}`;
  return `Recreate the first reference as one new photorealistic 4:5 photo that matches it closely: the same person, face, hairstyle, build, pose, framing, camera angle, background, light, and photo quality. The outfit is the one from the first reference, styled with ${garments} in that category. ${references} The referenced items are faithful in color, material, and details and sit naturally on the pose. No text, watermarks, or collage panels.`;
}

export function lookPrompt(
  concept: LookConcept,
  items: Array<{ name: string; category: string; colors: string[] }>,
  identityNote: string | null,
  completeWithWardrobe: boolean,
  { style = 'candid', focus = null, occasion = null }: {
    style?: LookStyle;
    focus?: LookFocus | null;
    occasion?: string | null;
  } = {},
) {
  const garments = items.map((i) => `${i.name} (${i.category}; ${i.colors.join(', ')})`).join('; ');
  const garmentInstruction = completeWithWardrobe || focus
    ? `Dress the person in exactly these referenced major garments: ${garments}.`
    : `Dress the person in these referenced garments: ${garments}.`;
  const completion = focus
    ? 'Do not add other visible garments; only a plain, neutral base layer such as a simple T-shirt is allowed where skin would otherwise show.'
    : completeWithWardrobe
      ? 'Do not invent other major garments; plain incidental basics such as socks are allowed.'
      : 'Complete the outfit with coherent unreferenced garments where needed. Do not replace, restyle, hide, or obscure any referenced garment.';
  const pairing = garmentPairing;
  const garmentReferences = items.length > 1
    ? `The final garment reference is one ordered board. Its cells are row-major, from left to right and then top to bottom, matching this garment order: ${items.map((item, index) => `${index + 1}. ${item.name}`).join('; ')}. ${pairing} Use each cell only for its matching garment.`
    : `The final reference shows the garment. ${pairing}`;
  return `The first reference shows the person whose identity must be preserved. It may be a single photo or a card containing several photos of the same person. Ignore background people and partial faces at the edges. For a single photo, use that photo as the primary identity reference. For a card, choose the photo with the clearest unobstructed face as the primary identity reference, regardless of its position in the card. Preserve its actual expression, whether smiling, laughing, or neutral; do not impose a preferred expression. Use the other photos only to confirm identity details, not to blend their expressions or head angles. Preserving the exact facial likeness of the person in this reference card is the highest priority. Use the original photos as the ground truth for identity. Preserve their facial proportions, face shape, jaw, cheeks, eyes, nose, mouth, hairline, facial hair, glasses when present, natural asymmetry, skin texture, and body proportions. Do not beautify, slim, symmetrize, or redesign their face. Copy the primary identity photo's head angle, gaze, and facial expression. Vary the outfit, body stance, and surroundings while keeping those facial details stable. Never borrow a face or identity from the clothing references. Use it only for identity, not for its clothes, layout, or background.${identityNote ? ` Additional identity details: ${identityNote}.` : ''} ${garmentReferences} ${lookStylePrompts[style](concept, focus ? lookFocusFraming[focus] : null)}${shotPrompt(concept.shot) ? ` Camera: ${shotPrompt(concept.shot)}` : ''} ${concept.camera ? lookCameras[concept.camera] : lookLighting(occasion)} ${unpolished} Mood of the scene: ${concept.mood}. The activity, camera shot, and mood describe the body and surroundings only. If they suggest laughing, looking down or away, or turning the head differently from the primary identity photo, adapt them to preserve that photo's head angle, gaze, and expression. ${garmentInstruction} Every referenced garment must be fully visible and faithful to its reference. ${completion} Avoid ${style === 'mirror' ? '' : 'selfies, '}illustrations, text, watermarks, and collages in the output. Keep the background free of readable lettering: no café menus, chalkboards, shop signs, posters, or storefront text. Where such surfaces appear naturally, keep them blank, out of focus, or turned away. Shoes, trousers, skirts, and dresses must never be cropped when selected.`;
}

async function imageDimensions(bytes: Uint8Array, expected: '1024x1280' | '768x960') {
  const metadata = await sharp(bytes, { failOn: 'error' }).metadata().catch(() => null);
  if (metadata?.width && metadata.height) return { width: metadata.width, height: metadata.height };
  throw new CatalogJobError('internal', `Generated Look image has no readable dimensions (expected ${expected}).`, false);
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
    if (job.kind !== 'generate-look' && job.kind !== 'plan-look')
      throw new CatalogJobError('internal', 'Unsupported inspiration job.', false);
    const id = (job.payload as { lookId: string }).lookId;
    const completeWithWardrobe =
      (job.payload as { completeWithWardrobe?: boolean }).completeWithWardrobe ?? true;
    const outputSize = (job.payload as { outputSize?: '1024x1280' | '768x960' }).outputSize ?? lookOutputSize;
    // Jobs queued before styles existed carry no style and stay candid.
    const style = (job.payload as { style?: LookStyle }).style ?? 'candid';
    const focus = (job.payload as { focus?: LookFocus }).focus ?? null;
    const started = await database.query<{
      character_sheet_id: string;
      exact_item_ids: string[];
      category_constraints: SupportedCategory[];
      quality: Look['quality'];
      model: string;
      planned_concept: LookConcept | null;
      base_asset_id: string | null;
      state: string;
    }>(
      `UPDATE looks SET state=CASE WHEN planned_concept IS NULL AND base_asset_id IS NULL THEN 'planning' ELSE 'generating' END,started_at=COALESCE(started_at,now()) WHERE id=$1 AND account_id=$2 AND state IN ('queued','planning','generating') RETURNING character_sheet_id,exact_item_ids,category_constraints,model,quality,planned_concept,base_asset_id,state`,
      [id, job.accountId],
    );
    const row = started.rows[0];
    if (!row) {
      const done = await database.query(
        `SELECT 1 FROM looks WHERE id=$1 AND account_id=$2 AND state IN ('ready','proposed')`,
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
    const baseAssetId = row.base_asset_id;
    if (baseAssetId) {
      // A try-on wears exactly the picked pieces; there is no scene to plan.
      itemIds = row.exact_item_ids;
      for (const [ordinal, itemId] of itemIds.entries())
        await database.query(
          'INSERT INTO look_items(look_id,wardrobe_item_id,ordinal) VALUES($1,$2,$3) ON CONFLICT DO NOTHING',
          [id, itemId, ordinal],
        );
    } else if (concept) {
      const links = await database.query<{ wardrobe_item_id: string }>(
        'SELECT wardrobe_item_id FROM look_items WHERE look_id=$1 ORDER BY ordinal',
        [id],
      );
      itemIds = links.rows.map((r) => r.wardrobe_item_id);
    } else {
      const excluded = (job.payload as { excludedItemIds?: string[] }).excludedItemIds ?? [];
      const planningCandidates = candidatesForLookPlan(
        candidates.rows,
        row.exact_item_ids,
        completeWithWardrobe,
      ).filter((item) => !excluded.includes(item.id) || row.exact_item_ids.includes(item.id));
      // Proposals of the same batch, planned one after another per account.
      const siblings =
        job.kind === 'plan-look'
          ? (
              await database.query<{ ids: string[]; planned_concept: LookConcept | null }>(
                `SELECT COALESCE(array_agg(li.wardrobe_item_id),'{}') ids,l.planned_concept FROM looks l LEFT JOIN look_items li ON li.look_id=l.id WHERE l.account_id=$1 AND l.id<>$2 AND l.proposal AND l.state='proposed' AND l.deleted_at IS NULL GROUP BY l.id`,
                [job.accountId, id],
              )
            ).rows
          : [];
      const usage =
        job.kind === 'plan-look' ? await pieceUsage(database, job.accountId, recent.rows) : null;
      const anchor =
        usage && completeWithWardrobe && !row.category_constraints.length
          ? pickAnchor({
              candidates: planningCandidates.map((item) => ({
                id: item.id,
                category: item.category,
                createdAt: item.created_at,
              })),
              usage,
              exactItemIds: row.exact_item_ids,
              siblingItemIds: siblings.flatMap((sibling) => sibling.ids),
            })
          : null;
      const warmth = await warmthOf(database, provider, job.accountId, planningCandidates, controller.signal);
      const planned = await provider.planLook({
        candidates: planningCandidates.map((i) => ({
          id: i.id,
          metadata: {
            name: i.name,
            category: i.category,
            colors: i.colors,
            notes: i.notes,
          },
          ...(warmth.has(i.id) ? { warmth: warmth.get(i.id) } : {}),
        })),
        recent: recentForLookPlan(recent.rows, row.exact_item_ids),
        ...(siblings.length ? { siblings: recentForLookPlan(siblings, row.exact_item_ids) } : {}),
        ...(anchor ? { anchorItemId: anchor.itemId } : {}),
        exactItemIds: row.exact_item_ids,
        categories: row.category_constraints,
        occasion: (job.payload as { occasion?: string | null }).occasion ?? null,
        style,
        // Drawn by weight here, so hearts and hidden shots take effect; the
        // planner then fits the activity to this one shot.
        shots: [pickShot(await shotWeights(database, job.accountId), style)].map((id) => ({
          id,
          description: shotPrompt(id)!,
        })),
        model: lookPlannerModel,
        signal: controller.signal,
      });
      // The camera is drawn here, not by the planner, so both stay in the mix.
      concept = {
        ...planned.concept,
        ...(style === 'mirror' ? {} : { camera: pickCamera((job.payload as { occasion?: string | null }).occasion ?? null) }),
      };
      itemIds = normalizeAutomaticLookItems(
        planned.itemIds,
        planningCandidates,
        row.exact_item_ids,
      );
      // Repeats are only accepted on the last attempt, so a small closet or a
      // mostly kept outfit still gets its proposal.
      const lastAttempt = job.attempts >= job.maxAttempts;
      if (!lastAttempt && siblings.some((sibling) => similarOutfit(sibling.ids, itemIds, row.exact_item_ids)))
        throw new CatalogJobError('validation', 'The proposal repeats a sibling outfit.', true);
      const repeatsRecent = recent.rows.some((look) =>
        similarOutfit(look.ids, itemIds, row.exact_item_ids),
      );
      if (!lastAttempt && warmthClash(itemIds.map((itemId) => ({ warmth: warmth.get(itemId) }))))
        throw new CatalogJobError('validation', 'The plan mixes warm and light pieces.', true);
      if (job.kind === 'plan-look' && repeatsRecent && !lastAttempt)
        throw new CatalogJobError('validation', 'The proposal repeats a recent look.', true);
      const occasion = (job.payload as { occasion?: LookOccasion | null }).occasion ?? null;
      const reasons: LookReason[] = [
        ...(row.exact_item_ids.length ? [{ kind: 'your-pick' as const, itemIds: row.exact_item_ids }] : []),
        ...(anchor?.reason && itemIds.includes(anchor.itemId) ? [anchor.reason] : []),
        ...(occasion ? [{ kind: 'occasion' as const, occasion }] : []),
      ];
      if (!repeatsRecent && reasons.length < 2) reasons.push({ kind: 'fresh' });
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
          `UPDATE looks SET state=$4,planned_concept=$3,proposal_reasons=$5,finished_at=CASE WHEN $4='proposed' THEN now() END WHERE id=$1 AND account_id=$2`,
          [
            id,
            job.accountId,
            JSON.stringify(concept),
            job.kind === 'plan-look' ? 'proposed' : 'generating',
            job.kind === 'plan-look' ? JSON.stringify(reasons) : null,
          ],
        );
        for (const [ordinal, itemId] of itemIds.entries())
          await client.query(
            'INSERT INTO look_items(look_id,wardrobe_item_id,ordinal) VALUES($1,$2,$3) ON CONFLICT DO NOTHING',
            [id, itemId, ordinal],
          );
      });
    }
    if (job.kind === 'plan-look') return;
    const character = await database.query<{ asset_id: string; note: string | null }>(
      'SELECT asset_id, note FROM character_sheets WHERE id=$1 AND account_id=$2',
      [row.character_sheet_id, job.accountId],
    );
    const selected = candidates.rows
      .filter((i) => itemIds.includes(i.id))
      .sort((a, b) => itemIds.indexOf(a.id) - itemIds.indexOf(b.id));
    const characterAssetId = character.rows[0]?.asset_id;
    if ((!baseAssetId && !characterAssetId) || selected.length !== itemIds.length)
      throw new CatalogJobError('internal', 'Look references are no longer available.', false);
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
    const board = await createGarmentReferenceBoard(garmentReferences);
    const refs = baseAssetId
      ? [await readAsset(database, storage, job.accountId, baseAssetId), board]
      : [
          await prepareIdentityReference(
            await readAsset(database, storage, job.accountId, characterAssetId!),
          ),
          board,
        ];
    const referenceAssetId = (job.payload as { referenceAssetId?: string }).referenceAssetId;
    if (referenceAssetId)
      refs.unshift(await readAsset(database, storage, job.accountId, referenceAssetId));
    const result = await provider.generateComposite({
      references: refs,
      prompt: baseAssetId
        ? tryOnPrompt(selected)
        : referenceAssetId
        ? `Recreate the first reference image with improved detail as one photorealistic 4:5 image. Preserve its composition, pose, outfit, person, lighting and background. The second reference is the original identity card and is the ground truth for facial likeness. Prioritize matching this person exactly: preserve facial proportions, face shape, eyes, nose, mouth, hairline, facial hair, glasses, and natural asymmetry. Correct any facial drift in the first image using this card; do not beautify or redesign the face. ${selected.length > 1 ? 'The final reference is an ordered garment board whose cells match the garments in the requested order. Each cell contains a paired shelf view and original garment photo.' : 'The final reference shows the garment and is only for fabric and construction detail.'} Do not change the scene or add garments, text, watermarks or collage panels.`
        : lookPrompt(concept!, selected, character.rows[0]?.note ?? null, completeWithWardrobe, {
            style,
            focus,
            occasion: (job.payload as { occasion?: string | null }).occasion ?? null,
          }),
      model: row.model,
      quality: row.quality,
      size: outputSize,
      ...(baseAssetId ? { moderation: 'low' as const } : {}),
      signal: controller.signal,
    });
    const dimensions = await imageDimensions(result.pngBytes, outputSize);
    const assetId = await writeAsset(
      database,
      storage,
      job.accountId,
      'look',
      result.pngBytes,
      dimensions.width,
      dimensions.height,
    );
    const feedAssetId = await writeFeedAsset(database, storage, job.accountId, result.pngBytes);
    const cost = calculateCostMicrounits(result.usage, config.pricing);
    await database.query(
      `UPDATE looks SET state='ready',asset_id=$3,feed_asset_id=$7,provider_request_id=$4,provider_usage=$5,cost_microunits=$6,finished_at=now() WHERE id=$1 AND account_id=$2`,
      [id, job.accountId, assetId, result.requestId, JSON.stringify(result.usage.raw), cost, feedAssetId],
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
  if (job.kind === 'generate-look' || job.kind === 'plan-look')
    await database.query(
      `UPDATE looks SET state='failed',failure_category=$3,failure_detail=$4,finished_at=now() WHERE id=$1 AND account_id=$2`,
      [(job.payload as { lookId: string }).lookId, job.accountId, e.category, e.message],
    );
}

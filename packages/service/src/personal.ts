import { GetObjectCommand } from '@aws-sdk/client-s3';
import sharp from 'sharp';
import type { ItemMetadata, ItemState } from '@form/contracts';
import type { Database } from './database.js';
import { withTransaction } from './database.js';
import type { PrivateObjectStorage } from './storage.js';
import { OwnedResourceNotFoundError } from './media.js';
import {
  createWardrobeItemFromDetection,
  recordDetectionProposals,
  deleteStoredAssets,
  InvalidWardrobeTransitionError,
} from './wardrobe.js';

export async function createPhotoItem(
  database: Database,
  input: {
    accountId: string;
    sourcePhotoId: string;
    metadata: ItemMetadata;
    state: Exclude<ItemState, 'archived'>;
    idempotencyKey: string;
  },
) {
  // A stable proposal makes a repeated save reuse the existing item command.
  const proposalId = input.idempotencyKey;
  await recordDetectionProposals(database, {
    accountId: input.accountId,
    sourcePhotoId: input.sourcePhotoId,
    detections: [
      {
        id: proposalId,
        ...input.metadata,
        boundingBox: { x: 0, y: 0, width: 1000, height: 1000 },
      },
    ],
  });
  return createWardrobeItemFromDetection(database, {
    ...input,
    detectionProposalId: proposalId,
  });
}

// `display` returns the wardrobe tile image: the kept or pending catalog cutout
// when one exists, otherwise the source photo cropped to the detected garment.
// `source` always returns the full, uncropped source photo, the image the item
// was created from (typically the person wearing the piece).
export async function itemPreview(
  database: Database,
  storage: PrivateObjectStorage,
  accountId: string,
  itemId: string,
  variant: 'display' | 'source' = 'display',
): Promise<Buffer> {
  const result = await database.query<{
    object_key: string;
    object_version_id: string;
    bounding_box: {
      x: number;
      y: number;
      width: number;
      height: number;
    } | null;
    generated: boolean;
  }>(
    variant === 'source'
      ? `SELECT a.object_key, a.object_version_id, NULL::jsonb AS bounding_box, true AS generated
         FROM wardrobe_items i JOIN source_photos s ON s.id = i.source_photo_id
         JOIN private_assets a ON a.id = s.asset_id
         WHERE i.id = $1 AND i.account_id = $2 AND i.deleted_at IS NULL AND a.state = 'ready'`
      : `SELECT a.object_key, a.object_version_id, d.bounding_box, (v.id IS NOT NULL OR pending.transparent_asset_id IS NOT NULL) AS generated
     FROM wardrobe_items i JOIN source_photos s ON s.id = i.source_photo_id
     LEFT JOIN shelf_image_versions v ON v.id = i.current_shelf_image_version_id
     LEFT JOIN LATERAL (
       SELECT transparent_asset_id FROM generation_attempts
       WHERE wardrobe_item_id = i.id AND account_id = i.account_id
         AND state = 'needs-review' AND i.status = 'needs-review'
       ORDER BY created_at DESC LIMIT 1
     ) pending ON true
     LEFT JOIN detection_proposals d ON d.id = i.detection_proposal_id
     JOIN private_assets a ON a.id = COALESCE(v.transparent_asset_id, pending.transparent_asset_id, s.asset_id)
     WHERE i.id = $1 AND i.account_id = $2 AND i.deleted_at IS NULL AND a.state = 'ready'`,
    [itemId, accountId],
  );
  const row = result.rows[0];
  if (!row) throw new OwnedResourceNotFoundError();
  const object = await storage.client.send(
    new GetObjectCommand({
      Bucket: storage.bucket,
      Key: row.object_key,
      VersionId: row.object_version_id,
    }),
  );
  const bytes = await object.Body!.transformToByteArray();
  const normalized = await sharp(bytes, { limitInputPixels: 40_000_000 }).rotate().toBuffer();
  let image = sharp(normalized);
  if (!row.generated && row.bounding_box) {
    const { width = 1, height = 1 } = await image.metadata();
    const b = row.bounding_box;
    const left = Math.floor((b.x * width) / 1000);
    const top = Math.floor((b.y * height) / 1000);
    image = image.extract({
      left,
      top,
      width: Math.max(1, Math.min(width - left, Math.ceil((b.width * width) / 1000))),
      height: Math.max(1, Math.min(height - top, Math.ceil((b.height * height) / 1000))),
    });
  }
  return image
    .resize(640, 800, { fit: 'inside', withoutEnlargement: true })
    .webp({ quality: 82 })
    .toBuffer();
}

export async function resetPersonalWardrobe(
  database: Database,
  storage: PrivateObjectStorage,
  accountId: string,
): Promise<void> {
  const assets = await withTransaction(database, async (client) => {
    // Prevent new jobs from being enqueued or leased while clearing their records.
    await client.query('LOCK TABLE remote_image_jobs IN SHARE ROW EXCLUSIVE MODE');
    const active = await client.query(
      "SELECT 1 FROM remote_image_jobs WHERE account_id = $1 AND state IN ('queued', 'leased') LIMIT 1",
      [accountId],
    );
    if (active.rows.length)
      throw new InvalidWardrobeTransitionError(
        'Bitte warte, bis die laufende Bildverarbeitung fertig ist.',
      );
    await client.query(
      'UPDATE wardrobe_items SET current_shelf_image_version_id = NULL WHERE account_id = $1',
      [accountId],
    );
    for (const table of [
      'remote_image_jobs',
      'looks',
      'character_sheets',
      'shelf_image_versions',
      'generation_attempts',
      'wardrobe_items',
      'detection_attempts',
      'detection_proposals',
      'source_photos',
      'idempotency_commands',
    ]) {
      await client.query(`DELETE FROM ${table} WHERE account_id = $1`, [accountId]);
    }
    const rows = await client.query<{ id: string }>(
      "UPDATE private_assets SET state = 'deleted', deleted_at = now() WHERE account_id = $1 RETURNING id",
      [accountId],
    );
    return rows.rows.map((row) => row.id);
  });
  await deleteStoredAssets(database, storage, accountId, assets);
}

// Removes the account with every record and stored object. Refuses while a
// generation is still running, like the wardrobe reset it builds on.
export async function deleteAccount(
  database: Database,
  storage: PrivateObjectStorage,
  accountId: string,
): Promise<void> {
  await resetPersonalWardrobe(database, storage, accountId);
  await database.query('DELETE FROM accounts WHERE id = $1', [accountId]);
}

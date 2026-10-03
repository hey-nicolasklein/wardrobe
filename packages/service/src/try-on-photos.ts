import type { Database, DatabaseClient } from './database.js';
import { withTransaction } from './database.js';
import { InspirationValidationError } from './inspiration.js';
import { OwnedResourceNotFoundError } from './media.js';
import type { PrivateObjectStorage } from './storage.js';
import { deleteStoredAssets } from './wardrobe.js';

export type TryOnPhoto = { assetId: string; createdAt: Date };

/** The user's try-on photos that still exist, newest first. */
export async function listTryOnPhotos(database: Database, accountId: string): Promise<TryOnPhoto[]> {
  const result = await database.query<{ asset_id: string; created_at: Date }>(
    `SELECT t.asset_id, t.created_at FROM try_on_photos t
     JOIN private_assets a ON a.id = t.asset_id
     WHERE t.account_id = $1 AND a.state = 'ready' AND a.deleted_at IS NULL
     ORDER BY t.created_at DESC`,
    [accountId],
  );
  return result.rows.map((row) => ({ assetId: row.asset_id, createdAt: row.created_at }));
}

/**
 * Keeps an uploaded source photo as a try-on photo. Adding one twice is a
 * no-op, so a retried request stays harmless.
 */
export async function addTryOnPhoto(
  database: Database | DatabaseClient,
  input: { accountId: string; assetId: string },
): Promise<void> {
  const result = await database.query(
    `INSERT INTO try_on_photos (account_id, asset_id)
     SELECT $1, id FROM private_assets
     WHERE id = $2 AND account_id = $1 AND purpose = 'source-photo'
       AND state = 'ready' AND deleted_at IS NULL
     ON CONFLICT DO NOTHING
     RETURNING asset_id`,
    [input.accountId, input.assetId],
  );
  if (result.rows[0]) return;
  const existing = await database.query('SELECT 1 FROM try_on_photos WHERE account_id = $1 AND asset_id = $2', [
    input.accountId,
    input.assetId,
  ]);
  if (!existing.rows[0]) throw new OwnedResourceNotFoundError();
}

/**
 * Deletes a try-on photo with its stored file. Finished try-on looks keep
 * their image, but can no longer be tried on again. A photo that also shows
 * a wardrobe piece only leaves the try-on list, since the piece still needs
 * it.
 */
export async function removeTryOnPhoto(
  database: Database,
  storage: PrivateObjectStorage,
  input: { accountId: string; assetId: string },
): Promise<void> {
  const deleted = await withTransaction(database, async (client) => {
    const removed = await client.query(
      'DELETE FROM try_on_photos WHERE account_id = $1 AND asset_id = $2 RETURNING asset_id',
      [input.accountId, input.assetId],
    );
    if (!removed.rows[0]) throw new OwnedResourceNotFoundError();
    const running = await client.query(
      `SELECT 1 FROM looks WHERE account_id = $1 AND base_asset_id = $2
       AND state IN ('queued', 'planning', 'generating') LIMIT 1`,
      [input.accountId, input.assetId],
    );
    if (running.rows[0])
      throw new InspirationValidationError(
        'try-on-photo-in-use',
        'Warte, bis die laufende Anprobe mit diesem Foto fertig ist.',
      );
    const piece = await client.query(
      `SELECT 1 FROM wardrobe_items i JOIN source_photos sp ON sp.id = i.source_photo_id
       WHERE i.account_id = $1 AND sp.asset_id = $2 LIMIT 1`,
      [input.accountId, input.assetId],
    );
    if (piece.rows[0]) return false;
    await client.query('DELETE FROM source_photos WHERE account_id = $1 AND asset_id = $2', [
      input.accountId,
      input.assetId,
    ]);
    await client.query(
      `UPDATE private_assets SET state = 'deleted', deleted_at = now()
       WHERE id = $1 AND account_id = $2`,
      [input.assetId, input.accountId],
    );
    return true;
  });
  if (deleted) await deleteStoredAssets(database, storage, input.accountId, [input.assetId]);
}

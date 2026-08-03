import type { Database, DatabaseClient } from './database.js';

type Queryable = Pick<Database, 'query'> | Pick<DatabaseClient, 'query'>;

export type OwnedPrivateAsset = {
  id: string;
  accountId: string;
  purpose: string;
  objectKey: string;
  objectVersionId: string | null;
  contentType: string;
  byteSize: number;
  pixelWidth: number | null;
  pixelHeight: number | null;
  state: 'pending' | 'ready' | 'deleted';
  createdAt: Date;
};

export async function findOwnedPrivateAsset(
  database: Queryable,
  accountId: string,
  assetId: string,
): Promise<OwnedPrivateAsset | null> {
  const result = await database.query<{
    id: string;
    account_id: string;
    purpose: string;
    object_key: string;
    object_version_id: string | null;
    content_type: string;
    byte_size: string;
    pixel_width: number | null;
    pixel_height: number | null;
    state: OwnedPrivateAsset['state'];
    created_at: Date;
  }>(
    `SELECT id, account_id, purpose, object_key, object_version_id, content_type, byte_size,
            pixel_width, pixel_height, state, created_at
     FROM private_assets
     WHERE id = $1 AND account_id = $2 AND state <> 'deleted'`,
    [assetId, accountId],
  );
  const asset = result.rows[0];
  return asset
    ? {
        id: asset.id,
        accountId: asset.account_id,
        purpose: asset.purpose,
        objectKey: asset.object_key,
        objectVersionId: asset.object_version_id,
        contentType: asset.content_type,
        byteSize: Number(asset.byte_size),
        pixelWidth: asset.pixel_width,
        pixelHeight: asset.pixel_height,
        state: asset.state,
        createdAt: asset.created_at,
      }
    : null;
}

import { GetObjectCommand, PutObjectCommand } from '@aws-sdk/client-s3';

import {
  createDatabase,
  createPrivateObjectStorage,
  readDatabaseConfig,
  readObjectStorageConfig,
  removeValidatedChromaBackground,
} from '../index.js';

// Re-runs chroma removal on every stored catalog cutout so the despill halo fix
// applies to items generated before it landed. Reads each transparent asset's
// original keyed source, regenerates the transparent PNG, and writes it back to
// the same object key as a new (recoverable) version. Deterministic, so it is
// safe to re-run; no provider calls, so no AI cost.
const database = createDatabase(readDatabaseConfig());
const storage = createPrivateObjectStorage(readObjectStorageConfig());

type Pair = {
  transparent_id: string;
  transparent_key: string;
  account_id: string;
  keyed_key: string;
  keyed_version: string;
};

try {
  const { rows } = await database.query<Pair>(
    `SELECT DISTINCT ON (t.id)
       t.id AS transparent_id, t.object_key AS transparent_key, t.account_id,
       k.object_key AS keyed_key, k.object_version_id AS keyed_version
     FROM (
       SELECT keyed_asset_id, transparent_asset_id FROM generation_attempts
         WHERE keyed_asset_id IS NOT NULL AND transparent_asset_id IS NOT NULL
       UNION
       SELECT keyed_asset_id, transparent_asset_id FROM shelf_image_versions
         WHERE keyed_asset_id IS NOT NULL AND transparent_asset_id IS NOT NULL
     ) pairs
     JOIN private_assets t ON t.id = pairs.transparent_asset_id AND t.state = 'ready'
     JOIN private_assets k ON k.id = pairs.keyed_asset_id AND k.state = 'ready'`,
  );
  console.log(`Found ${rows.length} catalog cutouts to reprocess.`);

  let reprocessed = 0;
  let failed = 0;
  for (const row of rows) {
    try {
      const keyed = await storage.client.send(
        new GetObjectCommand({
          Bucket: storage.bucket,
          Key: row.keyed_key,
          VersionId: row.keyed_version,
        }),
      );
      const keyedBytes = await keyed.Body?.transformToByteArray();
      if (!keyedBytes) throw new Error('keyed asset is empty');
      const { transparentPng } = await removeValidatedChromaBackground(keyedBytes);
      const put = await storage.client.send(
        new PutObjectCommand({
          Bucket: storage.bucket,
          Key: row.transparent_key,
          Body: transparentPng,
          ContentType: 'image/png',
          ContentLength: transparentPng.byteLength,
        }),
      );
      if (!put.VersionId) throw new Error('object storage did not version the rewrite');
      await database.query(
        `UPDATE private_assets SET object_version_id = $1, byte_size = $2 WHERE id = $3`,
        [put.VersionId, transparentPng.byteLength, row.transparent_id],
      );
      reprocessed += 1;
    } catch (error) {
      failed += 1;
      console.error(`Skipped ${row.transparent_id}: ${(error as Error).message}`);
    }
  }
  console.log(`Reprocessed ${reprocessed}, skipped ${failed}.`);
} finally {
  await database.end();
  storage.client.destroy();
}

import {
  DeleteObjectsCommand,
  ListObjectVersionsCommand,
  PutObjectCommand,
} from '@aws-sdk/client-s3';

import type { Database } from './database.js';
import { withTransaction } from './database.js';
import type { PrivateObjectStorage } from './storage.js';
import { hashPassword } from './auth.js';

export const fixtureIds = {
  populatedAccount: '10000000-0000-4000-8000-000000000001',
  emptyAccount: '10000000-0000-4000-8000-000000000002',
  sourceAsset: '20000000-0000-4000-8000-000000000001',
  keyedAssetOne: '20000000-0000-4000-8000-000000000002',
  transparentAssetOne: '20000000-0000-4000-8000-000000000003',
  keyedAssetTwo: '20000000-0000-4000-8000-000000000004',
  transparentAssetTwo: '20000000-0000-4000-8000-000000000005',
  sourcePhoto: '30000000-0000-4000-8000-000000000001',
  readyItem: '40000000-0000-4000-8000-000000000001',
  needsReviewItem: '40000000-0000-4000-8000-000000000002',
  queuedItem: '40000000-0000-4000-8000-000000000003',
  failedItem: '40000000-0000-4000-8000-000000000004',
  keptAttempt: '50000000-0000-4000-8000-000000000001',
  olderAttempt: '50000000-0000-4000-8000-000000000002',
  reviewAttempt: '50000000-0000-4000-8000-000000000003',
  currentVersion: '60000000-0000-4000-8000-000000000001',
  olderVersion: '60000000-0000-4000-8000-000000000002',
  queuedJob: '70000000-0000-4000-8000-000000000001',
  failedJob: '70000000-0000-4000-8000-000000000002',
} as const;

export const fixtureCredentials = {
  populated: { email: 'owner@example.test', password: 'owner-fixture-password' },
  empty: { email: 'empty@example.test', password: 'empty-fixture-password' },
} as const;

const fixturePng = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  'base64',
);

const fixtureObjects = [
  'fixtures/populated/source.png',
  'fixtures/populated/shelf-keyed-1.png',
  'fixtures/populated/shelf-transparent-1.png',
  'fixtures/populated/shelf-keyed-2.png',
  'fixtures/populated/shelf-transparent-2.png',
] as const;

async function clearFixtureObjects(storage: PrivateObjectStorage): Promise<void> {
  let keyMarker: string | undefined;
  let versionIdMarker: string | undefined;
  do {
    const page = await storage.client.send(
      new ListObjectVersionsCommand({
        Bucket: storage.bucket,
        Prefix: 'fixtures/',
        KeyMarker: keyMarker,
        VersionIdMarker: versionIdMarker,
      }),
    );
    const objects = [...(page.Versions ?? []), ...(page.DeleteMarkers ?? [])].flatMap(
      ({ Key, VersionId }) => (Key && VersionId ? [{ Key, VersionId }] : []),
    );
    if (objects.length > 0) {
      await storage.client.send(
        new DeleteObjectsCommand({ Bucket: storage.bucket, Delete: { Objects: objects } }),
      );
    }
    keyMarker = page.NextKeyMarker;
    versionIdMarker = page.NextVersionIdMarker;
  } while (pageIsTruncated(keyMarker));
}

function pageIsTruncated(nextKeyMarker: string | undefined): boolean {
  return nextKeyMarker !== undefined;
}

export async function resetFixtures(
  database: Database,
  storage: PrivateObjectStorage,
): Promise<void> {
  await clearFixtureObjects(storage);
  const fixtureObjectVersions = new Map(
    await Promise.all(
      fixtureObjects.map(async (key) => {
        const result = await storage.client.send(
          new PutObjectCommand({
            Bucket: storage.bucket,
            Key: key,
            Body: fixturePng,
            ContentType: 'image/png',
          }),
        );
        if (!result.VersionId) throw new Error(`Fixture object ${key} has no version ID.`);
        return [key, result.VersionId] as const;
      }),
    ),
  );

  const timestamp = new Date('2026-01-15T12:00:00.000Z');
  const [populatedPasswordHash, emptyPasswordHash] = await Promise.all([
    hashPassword(fixtureCredentials.populated.password),
    hashPassword(fixtureCredentials.empty.password),
  ]);
  await withTransaction(database, async (client) => {
    await client.query(`
      TRUNCATE TABLE
        idempotency_commands, remote_image_jobs, shelf_image_versions,
        generation_attempts, detection_proposals, wardrobe_items,
        source_photos, private_assets, sessions, accounts
      CASCADE
    `);

    await client.query(
      `INSERT INTO accounts (id, email, password_hash, created_at) VALUES
        ($1, $3, $4, $7),
        ($2, $5, $6, $7)`,
      [
        fixtureIds.populatedAccount,
        fixtureIds.emptyAccount,
        fixtureCredentials.populated.email,
        populatedPasswordHash,
        fixtureCredentials.empty.email,
        emptyPasswordHash,
        timestamp,
      ],
    );

    const assetRows = [
      [fixtureIds.sourceAsset, 'source-photo', fixtureObjects[0]],
      [fixtureIds.keyedAssetOne, 'shelf-image-keyed', fixtureObjects[1]],
      [fixtureIds.transparentAssetOne, 'shelf-image-transparent', fixtureObjects[2]],
      [fixtureIds.keyedAssetTwo, 'shelf-image-keyed', fixtureObjects[3]],
      [fixtureIds.transparentAssetTwo, 'shelf-image-transparent', fixtureObjects[4]],
    ] as const;
    for (const [id, purpose, objectKey] of assetRows) {
      await client.query(
        `INSERT INTO private_assets (
          id, account_id, purpose, object_key, object_version_id, content_type, byte_size,
          pixel_width, pixel_height, state, created_at, ready_at
        ) VALUES ($1, $2, $3, $4, $5, 'image/png', $6, 1, 1, 'ready', $7, $7)`,
        [
          id,
          fixtureIds.populatedAccount,
          purpose,
          objectKey,
          fixtureObjectVersions.get(objectKey)!,
          fixturePng.byteLength,
          timestamp,
        ],
      );
    }

    await client.query(
      `INSERT INTO source_photos (id, account_id, asset_id, created_at)
       VALUES ($1, $2, $3, $4)`,
      [fixtureIds.sourcePhoto, fixtureIds.populatedAccount, fixtureIds.sourceAsset, timestamp],
    );

    const items = [
      [fixtureIds.readyItem, 'owning', 'ready', 'Navy overshirt', 'jacket', ['navy']],
      [fixtureIds.needsReviewItem, 'wanting', 'needs-review', 'Canvas tote', 'bag', ['cream']],
      [fixtureIds.queuedItem, 'owning', 'queued', 'Black trousers', 'pants', ['black']],
      [fixtureIds.failedItem, 'archived', 'failed', 'Red scarf', 'scarf', ['red']],
    ];
    for (const [id, state, status, name, category, colors] of items) {
      await client.query(
        `INSERT INTO wardrobe_items (
          id, account_id, source_photo_id, state, status, name, category,
          colors, notes, created_at, updated_at
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NULL, $9, $9)`,
        [id, fixtureIds.populatedAccount, fixtureIds.sourcePhoto, state, status, name, category, colors, timestamp],
      );
    }

    const attemptMetadata = JSON.stringify({
      name: 'Navy overshirt',
      category: 'jacket',
      colors: ['navy'],
      notes: null,
    });
    await client.query(
      `INSERT INTO generation_attempts (
        id, account_id, wardrobe_item_id, source_photo_id, keyed_asset_id,
        transparent_asset_id, state, reviewed_metadata, model, quality,
        output_size, prompt_version, cost_microunits, created_at, finished_at
      ) VALUES
        ($1, $4, $5, $6, $7, $8, 'kept', $10, 'gpt-image-2', 'low', '816x816', 'laid-flat-v1', 12000, $11, $11),
        ($2, $4, $5, $6, $8, $7, 'kept', $10, 'gpt-image-2', 'low', '816x816', 'laid-flat-v1', 12000, $11 - interval '1 day', $11 - interval '1 day'),
        ($3, $4, $9, $6, $7, $8, 'needs-review', $10, 'gpt-image-2', 'low', '816x816', 'laid-flat-v1', 12000, $11, $11)`,
      [
        fixtureIds.keptAttempt,
        fixtureIds.olderAttempt,
        fixtureIds.reviewAttempt,
        fixtureIds.populatedAccount,
        fixtureIds.readyItem,
        fixtureIds.sourcePhoto,
        fixtureIds.keyedAssetOne,
        fixtureIds.transparentAssetOne,
        fixtureIds.needsReviewItem,
        attemptMetadata,
        timestamp,
      ],
    );

    await client.query(
      `INSERT INTO shelf_image_versions (
        id, account_id, wardrobe_item_id, generation_attempt_id, keyed_asset_id,
        transparent_asset_id, quality, output_size, prompt_version, kept_at, created_at
      ) VALUES
        ($1, $3, $4, $5, $6, $7, 'low', '816x816', 'laid-flat-v1', $8, $8),
        ($2, $3, $4, $9, $7, $6, 'low', '816x816', 'laid-flat-v1', $8 - interval '1 day', $8 - interval '1 day')`,
      [
        fixtureIds.currentVersion,
        fixtureIds.olderVersion,
        fixtureIds.populatedAccount,
        fixtureIds.readyItem,
        fixtureIds.keptAttempt,
        fixtureIds.keyedAssetOne,
        fixtureIds.transparentAssetOne,
        timestamp,
        fixtureIds.olderAttempt,
      ],
    );
    await client.query(
      `UPDATE wardrobe_items
       SET current_shelf_image_version_id = $1, record_version = 2
       WHERE id = $2`,
      [fixtureIds.currentVersion, fixtureIds.readyItem],
    );

    await client.query(
      `INSERT INTO remote_image_jobs (
        id, account_id, wardrobe_item_id, kind, payload, state, attempts,
        max_attempts, idempotency_key, created_at, updated_at,
        last_error_category, last_error_detail, finished_at
      ) VALUES
        ($1, $3, $4, 'generate-shelf-image', '{}', 'queued', 0, 2, 'fixture-queued-job-key', $6, $6, NULL, NULL, NULL),
        ($2, $3, $5, 'generate-shelf-image', '{}', 'failed', 1, 2, 'fixture-failed-job-key', $6, $6, 'moderation', 'Fixture failure', $6)`,
      [
        fixtureIds.queuedJob,
        fixtureIds.failedJob,
        fixtureIds.populatedAccount,
        fixtureIds.queuedItem,
        fixtureIds.failedItem,
        timestamp,
      ],
    );
  });
}

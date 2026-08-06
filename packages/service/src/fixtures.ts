import {
  DeleteObjectsCommand,
  ListObjectVersionsCommand,
  PutObjectCommand,
} from '@aws-sdk/client-s3';
import sharp from 'sharp';

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
  populated: { email: 'test@example.test', password: 'test' },
  empty: { email: 'empty@example.test', password: 'empty-fixture-password' },
} as const;

const fixtureObjects = [
  'fixtures/populated/source.png',
  'fixtures/populated/shelf-keyed-1.png',
  'fixtures/populated/shelf-transparent-1.png',
  'fixtures/populated/shelf-keyed-2.png',
  'fixtures/populated/shelf-transparent-2.png',
] as const;

function fixtureSvg(key: (typeof fixtureObjects)[number]): string {
  const chroma = key.includes('keyed') ? '#00ff00' : 'transparent';
  if (key.endsWith('source.png')) {
    return `<svg width="960" height="720" xmlns="http://www.w3.org/2000/svg">
      <rect width="960" height="720" fill="#e8e2d8"/>
      <rect x="40" y="40" width="880" height="640" rx="32" fill="#f8f5ef"/>
      <path d="M230 190 L335 130 L455 130 L560 190 L675 320 L585 375 L525 290 L525 590 L265 590 L265 290 L205 375 L115 320 Z" fill="#24385f"/>
      <path d="M335 130 Q395 235 455 130" fill="none" stroke="#d9d5ca" stroke-width="18"/>
      <path d="M665 290 Q775 205 865 305 L835 535 Q750 585 650 535 Z" fill="#d7c5a4"/>
      <path d="M690 305 Q755 200 825 305" fill="none" stroke="#9a7b55" stroke-width="18"/>
    </svg>`;
  }
  const older = key.endsWith('-2.png');
  return `<svg width="816" height="816" xmlns="http://www.w3.org/2000/svg">
    <rect width="816" height="816" fill="${chroma}"/>
    <path d="M190 200 L310 128 L506 128 L626 200 L748 340 L650 410 L570 302 L570 694 L246 694 L246 302 L166 410 L68 340 Z" fill="${older ? '#304873' : '#24385f'}" stroke="#18243e" stroke-width="8"/>
    <path d="M310 128 Q408 290 506 128" fill="none" stroke="#ddd8cc" stroke-width="24"/>
    <path d="M408 286 L408 694" stroke="#c7c2b8" stroke-width="8"/>
    <circle cx="385" cy="355" r="8" fill="#d8d3c8"/><circle cx="385" cy="420" r="8" fill="#d8d3c8"/><circle cx="385" cy="485" r="8" fill="#d8d3c8"/>
  </svg>`;
}

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
  const fixturePngs = new Map(
    await Promise.all(
      fixtureObjects.map(async (key) => [
        key,
        await sharp(Buffer.from(fixtureSvg(key))).png().toBuffer(),
      ] as const),
    ),
  );
  const fixtureObjectVersions = new Map(
    await Promise.all(
      fixtureObjects.map(async (key) => {
        const fixturePng = fixturePngs.get(key)!;
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
      const fixturePng = fixturePngs.get(objectKey)!;
      await client.query(
        `INSERT INTO private_assets (
          id, account_id, purpose, object_key, object_version_id, content_type, byte_size,
          pixel_width, pixel_height, state, created_at, ready_at
        ) VALUES ($1, $2, $3, $4, $5, 'image/png', $6, $7, $8, 'ready', $9, $9)`,
        [
          id,
          fixtureIds.populatedAccount,
          purpose,
          objectKey,
          fixtureObjectVersions.get(objectKey)!,
          fixturePng.byteLength,
          objectKey === fixtureObjects[0] ? 960 : 816,
          objectKey === fixtureObjects[0] ? 720 : 816,
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
        ($1, $4, $5, $6, $7, $8, 'kept', $12, 'gpt-image-2', 'low', '816x816', 'laid-flat-v1', 12000, $13, $13),
        ($2, $4, $5, $6, $9, $10, 'kept', $12, 'gpt-image-2', 'low', '816x816', 'laid-flat-v1', 12000, $13 - interval '1 day', $13 - interval '1 day'),
        ($3, $4, $11, $6, $7, $8, 'needs-review', $12, 'gpt-image-2', 'low', '816x816', 'laid-flat-v1', 12000, $13, $13)`,
      [
        fixtureIds.keptAttempt,
        fixtureIds.olderAttempt,
        fixtureIds.reviewAttempt,
        fixtureIds.populatedAccount,
        fixtureIds.readyItem,
        fixtureIds.sourcePhoto,
        fixtureIds.keyedAssetOne,
        fixtureIds.transparentAssetOne,
        fixtureIds.keyedAssetTwo,
        fixtureIds.transparentAssetTwo,
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
        ($2, $3, $4, $9, $10, $11, 'low', '816x816', 'laid-flat-v1', $8 - interval '1 day', $8 - interval '1 day')`,
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
        fixtureIds.keyedAssetTwo,
        fixtureIds.transparentAssetTwo,
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

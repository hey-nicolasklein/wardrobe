import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import test from 'node:test';

import { PutObjectCommand } from '@aws-sdk/client-s3';
import sharp from 'sharp';

import {
  claimJobs,
  createDatabase,
  createPrivateObjectStorage,
  createWardrobeItemFromDetection,
  enqueueShelfImageGeneration,
  enqueueSourcePhotoDetection,
  ensurePrivateBucket,
  enqueueJob,
  executeCatalogJob,
  fixtureIds,
  migrateDatabase,
  readDatabaseConfig,
  readObjectStorageConfig,
  recoverExpiredLeases,
  ReplayCatalogProvider,
  resetFixtures,
} from './index.js';

const enabled = process.env.FORM_RUN_SERVICE_INTEGRATION === 'true';

test('migrations, fixtures, account guards, and durable leases work together', { skip: !enabled }, async () => {
  const database = createDatabase(readDatabaseConfig());
  const storage = createPrivateObjectStorage(readObjectStorageConfig());
  try {
    await migrateDatabase(database);
    await ensurePrivateBucket(storage);
    await resetFixtures(database, storage);
    await resetFixtures(database, storage);

    const counts = await database.query<{ accounts: number; items: number; versions: number }>(`
      SELECT
        (SELECT count(*)::integer FROM accounts) AS accounts,
        (SELECT count(*)::integer FROM wardrobe_items) AS items,
        (SELECT count(*)::integer FROM shelf_image_versions) AS versions
    `);
    assert.deepEqual(counts.rows[0], { accounts: 2, items: 4, versions: 2 });

    await database.query(
      `INSERT INTO detection_proposals (
         id, account_id, source_photo_id, name, category, colors, bounding_box
       ) VALUES ($1, $2, $3, 'Fixture cap', 'hat', ARRAY['blue'], $4)`,
      [
        '80000000-0000-4000-8000-000000000002',
        fixtureIds.populatedAccount,
        fixtureIds.sourcePhoto,
        { x: 100, y: 100, width: 200, height: 200 },
      ],
    );
    await assert.rejects(
      database.query(
        `UPDATE detection_proposals SET name = 'Rewritten' WHERE id = $1`,
        ['80000000-0000-4000-8000-000000000002'],
      ),
      /detection proposals are immutable/,
    );
    await assert.rejects(
      database.query(
        `UPDATE generation_attempts SET reviewed_metadata = $2 WHERE id = $1`,
        [
          fixtureIds.keptAttempt,
          { name: 'Rewritten', category: 'jacket', colors: ['navy'], notes: null },
        ],
      ),
      /generation attempt inputs are immutable/,
    );
    await assert.rejects(
      database.query(
        `UPDATE shelf_image_versions SET prompt_version = 'rewritten' WHERE id = $1`,
        [fixtureIds.currentVersion],
      ),
      /shelf image versions are immutable/,
    );

    await assert.rejects(
      database.query(
        `INSERT INTO wardrobe_items (
          id, account_id, source_photo_id, state, status, name, category, colors
        ) VALUES (gen_random_uuid(), $1, $2, 'owning', 'reviewing-metadata', 'Nope', 'top', ARRAY['black'])`,
        [fixtureIds.emptyAccount, fixtureIds.sourcePhoto],
      ),
      /cross-account relationship rejected/,
    );

    const firstJobId = await enqueueJob(database, {
      accountId: fixtureIds.emptyAccount,
      kind: 'detect-source-photo',
      payload: { sourcePhotoId: 'placeholder' },
      idempotencyKey: 'integration-idempotency-key-0001',
    });
    const replayedJobId = await enqueueJob(database, {
      accountId: fixtureIds.emptyAccount,
      kind: 'detect-source-photo',
      payload: { sourcePhotoId: 'placeholder' },
      idempotencyKey: 'integration-idempotency-key-0001',
    });
    assert.equal(replayedJobId, firstJobId);

    const claimed = await claimJobs(database, {
      workerId: 'integration-worker',
      limit: 2,
      perAccountLimit: 1,
      leaseSeconds: 60,
    });
    assert.equal(claimed.length, 2);
    assert.equal(new Set(claimed.map(({ accountId }) => accountId)).size, 2);

    await database.query(
      `UPDATE remote_image_jobs SET lease_expires_at = now() - interval '1 second'
       WHERE lease_owner = 'integration-worker'`,
    );
    assert.equal(await recoverExpiredLeases(database), 2);
    const recovered = await database.query<{ state: string }>(
      `SELECT state FROM remote_image_jobs WHERE id = $1`,
      [firstJobId],
    );
    assert.equal(recovered.rows[0]?.state, 'queued');
  } finally {
    storage.client.destroy();
    await database.end();
  }
});

test('replay pipeline detects, crops, accounts, and stores review assets', { skip: !enabled }, async () => {
  const database = createDatabase(readDatabaseConfig());
  const storage = createPrivateObjectStorage(readObjectStorageConfig());
  try {
    await migrateDatabase(database);
    await ensurePrivateBucket(storage);
    await resetFixtures(database, storage);
    const sourceAssetId = randomUUID();
    const sourcePhotoId = randomUUID();
    const objectKey = `fixtures/pipeline/${sourceAssetId}.jpg`;
    const sourceBytes = await sharp({
      create: { width: 300, height: 400, channels: 3, background: '#dddddd' },
    })
      .jpeg()
      .toBuffer();
    const stored = await storage.client.send(
      new PutObjectCommand({
        Bucket: storage.bucket,
        Key: objectKey,
        Body: sourceBytes,
        ContentType: 'image/jpeg',
      }),
    );
    assert.ok(stored.VersionId);
    await database.query(
      `INSERT INTO private_assets (
         id, account_id, purpose, object_key, object_version_id, content_type, byte_size,
         pixel_width, pixel_height, state, ready_at
       ) VALUES ($1, $2, 'source-photo', $3, $4, 'image/jpeg', $5, 300, 400, 'ready', now())`,
      [
        sourceAssetId,
        fixtureIds.populatedAccount,
        objectKey,
        stored.VersionId,
        sourceBytes.byteLength,
      ],
    );
    await database.query(
      `INSERT INTO source_photos (id, account_id, asset_id) VALUES ($1, $2, $3)`,
      [sourcePhotoId, fixtureIds.populatedAccount, sourceAssetId],
    );

    const detectionId = randomUUID();
    const keyedOutput = await sharp({
      create: { width: 816, height: 816, channels: 3, background: '#00ff00' },
    })
      .composite([
        {
          input: await sharp({
            create: { width: 240, height: 320, channels: 3, background: '#223366' },
          })
            .png()
            .toBuffer(),
          left: 288,
          top: 248,
        },
      ])
      .png()
      .toBuffer();
    const provider = new ReplayCatalogProvider([
      {
        key: 'detect:gpt-5.4-mini',
        detection: {
          requestId: 'replay-detection-request',
          detections: [
            {
              id: detectionId,
              name: 'Navy overshirt',
              category: 'jacket',
              colors: ['navy'],
              boundingBox: { x: 100, y: 100, width: 700, height: 700 },
            },
          ],
        },
      },
      {
        key: 'generate:gpt-image-2:low',
        generation: {
          requestId: 'replay-generation-request',
          pngBytes: keyedOutput,
          usage: {
            textInputTokens: 10,
            imageInputTokens: 20,
            outputTokens: 30,
            serviceTier: 'default',
            raw: { fixture: true },
          },
        },
      },
    ]);
    const executionConfig = {
      requestTimeoutMs: 10_000,
      pricing: {
        effectiveDate: '2026-08-03',
        textInputMicrodollarsPerMillion: 1_000_000,
        imageInputMicrodollarsPerMillion: 2_000_000,
        imageOutputMicrodollarsPerMillion: 3_000_000,
      },
    };
    const detection = await enqueueSourcePhotoDetection(database, {
      accountId: fixtureIds.populatedAccount,
      sourcePhotoId,
      model: 'gpt-5.4-mini',
      idempotencyKey: 'pipeline-detection-command-0001',
    });
    await executeCatalogJob(
      database,
      storage,
      provider,
      {
        id: detection.jobId,
        accountId: fixtureIds.populatedAccount,
        wardrobeItemId: null,
        generationAttemptId: null,
        kind: 'detect-source-photo',
        payload: { sourcePhotoId, detectionAttemptId: detection.detectionAttemptId },
        attempts: 1,
        maxAttempts: 2,
        leaseExpiresAt: new Date(Date.now() + 60_000),
      },
      executionConfig,
    );
    const item = await createWardrobeItemFromDetection(database, {
      accountId: fixtureIds.populatedAccount,
      detectionProposalId: detectionId,
      state: 'owning',
      idempotencyKey: 'pipeline-create-item-command-001',
    });
    const generation = await enqueueShelfImageGeneration(database, {
      accountId: fixtureIds.populatedAccount,
      wardrobeItemId: item.id,
      quality: 'low',
      size: '816x816',
      idempotencyKey: 'pipeline-generation-command-0001',
    });
    await executeCatalogJob(
      database,
      storage,
      provider,
      {
        id: generation.jobId,
        accountId: fixtureIds.populatedAccount,
        wardrobeItemId: item.id,
        generationAttemptId: generation.generationAttemptId,
        kind: 'generate-shelf-image',
        payload: { generationAttemptId: generation.generationAttemptId },
        attempts: 1,
        maxAttempts: 2,
        leaseExpiresAt: new Date(Date.now() + 60_000),
      },
      executionConfig,
    );
    const attempt = await database.query<{
      state: string;
      text_input_tokens: number;
      image_input_tokens: number;
      output_tokens: number;
      cost_microunits: string;
      resolved_chroma_key: string;
      assets: number;
    }>(
      `SELECT attempts.state, attempts.text_input_tokens, attempts.image_input_tokens,
         attempts.output_tokens, attempts.cost_microunits, attempts.resolved_chroma_key,
         (SELECT count(*)::integer FROM private_assets assets WHERE assets.id IN (
           attempts.reference_asset_id, attempts.keyed_asset_id, attempts.transparent_asset_id
         )) AS assets
       FROM generation_attempts attempts WHERE attempts.id = $1`,
      [generation.generationAttemptId],
    );
    assert.deepEqual(attempt.rows[0], {
      state: 'needs-review',
      text_input_tokens: 10,
      image_input_tokens: 20,
      output_tokens: 30,
      cost_microunits: '140',
      resolved_chroma_key: '#00ff00',
      assets: 3,
    });

    const nonUniformOutput = await sharp({
      create: { width: 816, height: 816, channels: 3, background: '#00ff00' },
    })
      .composite([
        {
          input: await sharp({
            create: { width: 408, height: 816, channels: 3, background: '#0066ff' },
          })
            .png()
            .toBuffer(),
          left: 408,
          top: 0,
        },
      ])
      .png()
      .toBuffer();
    const failingProvider = new ReplayCatalogProvider([
      {
        key: 'generate:gpt-image-2:low',
        generation: {
          requestId: 'replay-billed-chroma-failure',
          pngBytes: nonUniformOutput,
          usage: {
            textInputTokens: 11,
            imageInputTokens: 22,
            outputTokens: 33,
            serviceTier: 'default',
            raw: { fixture: 'billed-chroma-failure' },
          },
        },
      },
    ]);
    const failedGeneration = await enqueueShelfImageGeneration(database, {
      accountId: fixtureIds.populatedAccount,
      wardrobeItemId: item.id,
      quality: 'low',
      size: '816x816',
      idempotencyKey: 'pipeline-generation-command-0002',
    });
    await assert.rejects(
      executeCatalogJob(
        database,
        storage,
        failingProvider,
        {
          id: failedGeneration.jobId,
          accountId: fixtureIds.populatedAccount,
          wardrobeItemId: item.id,
          generationAttemptId: failedGeneration.generationAttemptId,
          kind: 'generate-shelf-image',
          payload: { generationAttemptId: failedGeneration.generationAttemptId },
          attempts: 1,
          maxAttempts: 2,
          leaseExpiresAt: new Date(Date.now() + 60_000),
        },
        executionConfig,
      ),
      (error: unknown) =>
        (error as { category?: string }).category === 'chroma-validation',
    );
    const billedFailure = await database.query<{
      provider_request_id: string;
      text_input_tokens: number;
      cost_microunits: string;
      reference_asset_id: string;
      keyed_asset_id: string;
      transparent_asset_id: string | null;
    }>(
      `SELECT provider_request_id, text_input_tokens, cost_microunits,
         reference_asset_id, keyed_asset_id, transparent_asset_id
       FROM generation_attempts WHERE id = $1`,
      [failedGeneration.generationAttemptId],
    );
    assert.equal(billedFailure.rows[0]?.provider_request_id, 'replay-billed-chroma-failure');
    assert.equal(billedFailure.rows[0]?.text_input_tokens, 11);
    assert.equal(billedFailure.rows[0]?.cost_microunits, '154');
    assert.ok(billedFailure.rows[0]?.reference_asset_id);
    assert.ok(billedFailure.rows[0]?.keyed_asset_id);
    assert.equal(billedFailure.rows[0]?.transparent_asset_id, null);
  } finally {
    storage.client.destroy();
    await database.end();
  }
});

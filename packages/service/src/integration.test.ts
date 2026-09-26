import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import test from 'node:test';

import { GetObjectCommand, PutObjectCommand } from '@aws-sdk/client-s3';
import sharp from 'sharp';

import {
  claimJobs,
  createDatabase,
  createPrivateObjectStorage,
  createLook,
  createCharacterSheet,
  executeInspirationJob,
  generationCosts,
  retryLook,
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
  listLooks,
  listCharacterSheets,
  removeCharacterSheet,
  creditBalance,
  creditSummary,
  deleteAccount,
  failJob,
  grantCredits,
  InsufficientCreditsError,
  signInWithIdentity,
  signupCredits,
} from './index.js';
import { compactIdentityReference } from './identity-collage.js';

const enabled = process.env.FORM_RUN_SERVICE_INTEGRATION === 'true';

test('photo collages cost zero and become the first reference for a priced feed look', { skip: !enabled }, async () => {
  const database = createDatabase(readDatabaseConfig());
  const storage = createPrivateObjectStorage(readObjectStorageConfig());
  const config = { requestTimeoutMs: 10_000, pricing: {
    effectiveDate: '2026-08-03', textInputMicrodollarsPerMillion: 1_000_000,
    imageInputMicrodollarsPerMillion: 2_000_000, imageOutputMicrodollarsPerMillion: 3_000_000,
  }, detectionPricing: {
    model: 'gpt-5.6-luna', effectiveDate: '2026-07-30',
    inputMicrodollarsPerMillion: 200_000, cachedInputMicrodollarsPerMillion: 20_000,
    cacheWriteInputMicrodollarsPerMillion: 250_000,
    outputMicrodollarsPerMillion: 1_200_000,
  } };
  try {
    await migrateDatabase(database);
    await ensurePrivateBucket(storage);
    await resetFixtures(database, storage);
    const input = { accountId: fixtureIds.populatedAccount, referenceAssetIds: [fixtureIds.sourceAsset], note: 'braunes Haar', idempotencyKey: 'collage-integration-create-0001' };
    const created = await createCharacterSheet(database, input);
    assert.deepEqual(await createCharacterSheet(database, input), created);
    await assert.rejects(createCharacterSheet(database, { ...input, accountId: fixtureIds.emptyAccount }));
    const makeJob = (id: string, kind: 'generate-look', payload: unknown) => ({
      id, accountId: input.accountId, kind, payload, wardrobeItemId: null, generationAttemptId: null,
      attempts: 1, maxAttempts: 3, leaseExpiresAt: new Date(Date.now() + 60_000),
    });
    // An empty replay provider fails on every paid operation.
    const provider = new ReplayCatalogProvider([]);
    const sheet = (await listCharacterSheets(database, input.accountId))[0]!;
    assert.equal(sheet.model, 'photo-collage-v1');
    assert.equal(sheet.state, 'ready');
    assert.equal(sheet.active, true);
    assert.equal(sheet.costMicrounits, 0);
    assert.equal(sheet.providerRequestId, null);
    assert.equal(sheet.assetId, fixtureIds.sourceAsset);
    const asset = (await database.query<{ object_key: string; object_version_id: string; pixel_width: number; pixel_height: number }>('SELECT object_key,object_version_id,pixel_width,pixel_height FROM private_assets WHERE id=$1', [sheet.assetId])).rows[0]!;
    // The reference remains the uploaded collage asset; no 864×1536 sheet is
    // rendered or written as a replacement.
    assert.ok(asset.pixel_width > 0);
    assert.ok(asset.pixel_height > 0);
    const object = await storage.client.send(new GetObjectCommand({ Bucket: storage.bucket, Key: asset.object_key, VersionId: asset.object_version_id }));
    const collageBytes = Buffer.from(await object.Body!.transformToByteArray());
    const concept = { activity: 'walking', scene: 'a quiet street', mood: 'relaxed', framing: 'full-body' as const };
    const look = await createLook(database, { accountId: input.accountId, exactItemIds: [fixtureIds.readyItem], categories: [], parentLookId: null, idempotencyKey: 'collage-integration-look-0001' });
    let referenceChecked = false;
    const lookProvider = Object.assign(provider, {
      planLook: async () => ({ requestId: 'plan-collage', itemIds: [fixtureIds.readyItem], concept }),
      generateComposite: async (request: { references: Uint8Array[]; prompt: string; quality: string }) => {
        assert.equal(request.quality, 'low');
        assert.ok(Buffer.from(request.references[0]!).equals(await compactIdentityReference(collageBytes)));
        assert.equal(request.references.length, 2);
        const garmentReference = await sharp(request.references[1]!).metadata();
        assert.equal(garmentReference.width, 512);
        assert.equal(garmentReference.height, 256);
        assert.match(request.prompt, /collage of cropped original photos/);
        assert.match(request.prompt, /shelf view on the left/);
        assert.match(request.prompt, /braunes Haar/);
        referenceChecked = true;
        return { requestId: 'look-collage', pngBytes: await sharp(collageBytes).resize(768, 960).png().toBuffer(), usage: { textInputTokens: 10, imageInputTokens: 200, outputTokens: 30, serviceTier: 'default', raw: { fixture: true } } };
      },
    });
    await executeInspirationJob(database, storage, lookProvider, makeJob(look.jobId, 'generate-look', { lookId: look.lookId }), config);
    assert.ok(referenceChecked);
    const feed = await listLooks(database, input.accountId);
    assert.equal(feed[0]!.characterSheetId, sheet.id);
    assert.equal(feed[0]!.state, 'ready');
    assert.equal(feed[0]!.costMicrounits, 500);
    const costs = await generationCosts(database, input.accountId);
    assert.equal(costs.characterSheetTotalMicrounits, 0);
    assert.equal(costs.lookTotalMicrounits, 500);
    assert.equal(costs.wardrobeTotalMicrounits, 36_000);
    assert.equal(costs.wardrobeRequestCount, 3);
    assert.equal(costs.detectionTotalMicrounits, 0);
    assert.equal(costs.detectionRequestCount, 0);
    assert.equal(feed[0]!.quality, 'low');
    const upgradeCommand = { accountId: input.accountId, exactItemIds: [], categories: [], parentLookId: look.lookId, quality: 'high' as const, preserveComposition: true, idempotencyKey: randomUUID() };
    const upgraded = await createLook(database, upgradeCommand);
    assert.deepEqual(await createLook(database, upgradeCommand), upgraded);
    await assert.rejects(createLook(database, { ...upgradeCommand, quality: 'medium' }), /idempotency/i);
    const upgrade = (await listLooks(database, input.accountId)).find((entry) => entry.id === upgraded.lookId)!;
    assert.equal(upgrade.quality, 'high');
    assert.equal(upgrade.characterSheetId, sheet.id);
    assert.deepEqual(upgrade.concept, concept);
    assert.deepEqual(upgrade.wardrobeItemIds, feed[0]!.wardrobeItemIds);
    await database.query("UPDATE looks SET state='failed' WHERE id=$1", [upgraded.lookId]);
    const retry = await retryLook(database, { accountId: input.accountId, lookId: upgraded.lookId, idempotencyKey: randomUUID() });
    const retryPayload = (await database.query<{ payload: { referenceAssetId: string } }>('SELECT payload FROM remote_image_jobs WHERE id=$1', [retry.jobId])).rows[0]!.payload;
    assert.equal(retryPayload.referenceAssetId, feed[0]!.assetId);
    let upgradeChecked = false;
    const upgradeProvider = Object.assign(new ReplayCatalogProvider([]), {
      planLook: async () => { throw new Error('An upgrade must not re-plan the look'); },
      generateComposite: async (request: { references: Uint8Array[]; prompt: string; quality: string }) => {
        assert.equal(request.quality, 'high');
        assert.equal(request.references.length, 3);
        assert.ok(Buffer.from(request.references[0]!).equals(await sharp(collageBytes).resize(768, 960).png().toBuffer()));
        assert.ok(Buffer.from(request.references[1]!).equals(await compactIdentityReference(collageBytes)));
        assert.match(request.prompt, /Preserve its composition/);
        upgradeChecked = true;
        return { requestId: 'upgraded-look', pngBytes: await sharp(collageBytes).resize(768, 960).png().toBuffer(), usage: { textInputTokens: 10, imageInputTokens: 200, outputTokens: 30, serviceTier: 'default', raw: { fixture: true } } };
      },
    });
    await executeInspirationJob(database, storage, upgradeProvider, makeJob(retry.jobId, 'generate-look', retryPayload), config);
    assert.ok(upgradeChecked);
    const upgradedFeed = await listLooks(database, input.accountId);
    assert.equal(upgradedFeed.filter((entry) => entry.state === 'ready').length, 2);

  } finally {
    storage.client.destroy();
    await database.end();
  }
});

test(
  'migrations, fixtures, account guards, and durable leases work together',
  { skip: !enabled },
  async () => {
    const database = createDatabase(readDatabaseConfig());
    const storage = createPrivateObjectStorage(readObjectStorageConfig());
    try {
      await migrateDatabase(database);
      await ensurePrivateBucket(storage);
      await resetFixtures(database, storage);
      await resetFixtures(database, storage);

      const counts = await database.query<{
        accounts: number;
        items: number;
        versions: number;
      }>(`
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
        database.query(`UPDATE detection_proposals SET name = 'Rewritten' WHERE id = $1`, [
          '80000000-0000-4000-8000-000000000002',
        ]),
        /detection proposals are immutable/,
      );
      await assert.rejects(
        database.query(`UPDATE generation_attempts SET reviewed_metadata = $2 WHERE id = $1`, [
          fixtureIds.keptAttempt,
          {
            name: 'Rewritten',
            category: 'jacket',
            colors: ['navy'],
            notes: null,
          },
        ]),
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
  },
);

test(
  'Look creation is account-scoped, idempotent, and durably queued',
  { skip: !enabled },
  async () => {
    const database = createDatabase(readDatabaseConfig());
    const storage = createPrivateObjectStorage(readObjectStorageConfig());
    try {
      await migrateDatabase(database);
      await ensurePrivateBucket(storage);
      await resetFixtures(database, storage);
      const characterSheetId = randomUUID();
      await database.query(
        `INSERT INTO character_sheets (
        id, account_id, reference_asset_ids, state, asset_id, active,
        model, quality, output_size, prompt_version, finished_at
      ) VALUES ($1, $2, $3, 'ready', $4, true, 'fixture', 'high', '864x1536', 'fixture', now())`,
        [
          characterSheetId,
          fixtureIds.populatedAccount,
          [fixtureIds.transparentAssetOne],
          fixtureIds.transparentAssetOne,
        ],
      );
      const command = {
        accountId: fixtureIds.populatedAccount,
        exactItemIds: [fixtureIds.readyItem],
        categories: [],
        occasion: 'party',
        parentLookId: null,
        idempotencyKey: randomUUID(),
      };
      const first = await createLook(database, command);
      assert.deepEqual(await createLook(database, command), first);
      const feed = await listLooks(database, fixtureIds.populatedAccount);
      assert.equal(feed[0]?.state, 'queued');
      assert.equal(feed[0]?.characterSheetId, characterSheetId);
      const queued = await database.query<{ kind: string; look_id: string; payload: unknown }>(
        'SELECT kind, look_id, payload FROM remote_image_jobs WHERE id = $1',
        [first.jobId],
      );
      assert.deepEqual(queued.rows[0], {
        kind: 'generate-look',
        look_id: first.lookId,
        payload: { lookId: first.lookId, occasion: 'party', completeWithWardrobe: true,
          outputSize: '768x960' },
      });
      await database.query("UPDATE looks SET state='failed' WHERE id=$1", [first.lookId]);
      const retried = await retryLook(database, {
        accountId: command.accountId, lookId: first.lookId, idempotencyKey: randomUUID(),
      });
      const retryJob = await database.query<{ payload: unknown }>(
        'SELECT payload FROM remote_image_jobs WHERE id=$1', [retried.jobId],
      );
      assert.deepEqual(retryJob.rows[0]?.payload, queued.rows[0]!.payload);
      await assert.rejects(
        createLook(database, {
          ...command,
          accountId: fixtureIds.emptyAccount,
        }),
        /Character Sheet/,
      );
    } finally {
      storage.client.destroy();
      await database.end();
    }
  },
);

test('old Character Sheets can be hidden without breaking history', { skip: !enabled }, async () => {
  const database = createDatabase(readDatabaseConfig());
  const storage = createPrivateObjectStorage(readObjectStorageConfig());
  try {
    await migrateDatabase(database);
    await ensurePrivateBucket(storage);
    await resetFixtures(database, storage);
    const activeId = randomUUID();
    const oldId = randomUUID();
    await database.query(
      `INSERT INTO character_sheets (
        id, account_id, reference_asset_ids, state, asset_id, active,
        model, quality, output_size, prompt_version, cost_microunits, finished_at
      ) VALUES
        ($1, $3, $4, 'ready', $5, true, 'fixture', 'high', '864x1536', 'fixture', 10, now()),
        ($2, $3, $4, 'ready', $5, false, 'fixture', 'high', '864x1536', 'fixture', 20, now())`,
      [
        activeId,
        oldId,
        fixtureIds.populatedAccount,
        [fixtureIds.transparentAssetOne],
        fixtureIds.transparentAssetOne,
      ],
    );

    await assert.rejects(
      removeCharacterSheet(database, {
        accountId: fixtureIds.populatedAccount,
        characterSheetId: activeId,
      }),
      /aktive Character Sheet/,
    );
    await removeCharacterSheet(database, {
      accountId: fixtureIds.populatedAccount,
      characterSheetId: oldId,
    });

    assert.deepEqual(
      (await listCharacterSheets(database, fixtureIds.populatedAccount)).map(({ id }) => id),
      [activeId],
    );
    const retained = await database.query<{ deleted: boolean; cost_microunits: string }>(
      `SELECT deleted_at IS NOT NULL AS deleted, cost_microunits
       FROM character_sheets WHERE id = $1`,
      [oldId],
    );
    assert.deepEqual(retained.rows[0], { deleted: true, cost_microunits: '20' });
  } finally {
    storage.client.destroy();
    await database.end();
  }
});

test(
  'replay pipeline detects, crops, accounts, and stores review assets',
  { skip: !enabled },
  async () => {
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
              create: {
                width: 240,
                height: 320,
                channels: 3,
                background: '#223366',
              },
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
          key: 'detect:gpt-5.6-luna',
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
            usage: {
              inputTokens: 100,
              cachedInputTokens: 10,
              cacheWriteInputTokens: 20,
              outputTokens: 50,
              reasoningTokens: 0,
              serviceTier: 'default',
              raw: { fixture: 'detection' },
            },
          },
        },
        {
          key: 'generate:gpt-image-2.5-flare:low',
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
        detectionPricing: {
          model: 'gpt-5.6-luna',
          effectiveDate: '2026-07-30',
          inputMicrodollarsPerMillion: 200_000,
          cachedInputMicrodollarsPerMillion: 20_000,
          cacheWriteInputMicrodollarsPerMillion: 250_000,
          outputMicrodollarsPerMillion: 1_200_000,
        },
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
        model: 'gpt-5.6-luna',
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
          payload: {
            sourcePhotoId,
            detectionAttemptId: detection.detectionAttemptId,
          },
          attempts: 1,
          maxAttempts: 2,
          leaseExpiresAt: new Date(Date.now() + 60_000),
        },
        executionConfig,
      );
      const detectionLedger = await database.query<{
        model: string;
        input_tokens: number;
        cached_input_tokens: number;
        cache_write_input_tokens: number;
        output_tokens: number;
        reasoning_tokens: number;
        cost_microunits: string;
      }>(
        `SELECT model, input_tokens, cached_input_tokens, cache_write_input_tokens,
           output_tokens, reasoning_tokens, cost_microunits
         FROM detection_attempts WHERE id = $1`,
        [detection.detectionAttemptId],
      );
      assert.deepEqual(detectionLedger.rows[0], {
        model: 'gpt-5.6-luna',
        input_tokens: 100,
        cached_input_tokens: 10,
        cache_write_input_tokens: 20,
        output_tokens: 50,
        reasoning_tokens: 0,
        cost_microunits: '80',
      });
      await assert.rejects(
        database.query(
          'UPDATE detection_attempts SET cost_microunits = 81 WHERE id = $1',
          [detection.detectionAttemptId],
        ),
        /detection usage ledger is immutable/,
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
        autoKeep: false,
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

      const automaticGeneration = await enqueueShelfImageGeneration(database, {
        accountId: fixtureIds.populatedAccount,
        wardrobeItemId: item.id,
        quality: 'low',
        size: '816x816',
        autoKeep: true,
        idempotencyKey: 'pipeline-automatic-generation-command-0001',
      });
      await executeCatalogJob(
        database,
        storage,
        provider,
        {
          id: automaticGeneration.jobId,
          accountId: fixtureIds.populatedAccount,
          wardrobeItemId: item.id,
          generationAttemptId: automaticGeneration.generationAttemptId,
          kind: 'generate-shelf-image',
          payload: {
            generationAttemptId: automaticGeneration.generationAttemptId,
          },
          attempts: 1,
          maxAttempts: 2,
          leaseExpiresAt: new Date(Date.now() + 60_000),
        },
        executionConfig,
      );
      const automaticallyKept = await database.query<{
        attempt_state: string;
        item_status: string;
        current_version_attempt_id: string;
      }>(
        `SELECT attempts.state AS attempt_state, items.status AS item_status,
         versions.generation_attempt_id AS current_version_attempt_id
       FROM generation_attempts attempts
       JOIN wardrobe_items items ON items.id = attempts.wardrobe_item_id
       JOIN shelf_image_versions versions ON versions.id = items.current_shelf_image_version_id
       WHERE attempts.id = $1`,
        [automaticGeneration.generationAttemptId],
      );
      assert.deepEqual(automaticallyKept.rows[0], {
        attempt_state: 'kept',
        item_status: 'ready',
        current_version_attempt_id: automaticGeneration.generationAttemptId,
      });

      const nonUniformOutput = await sharp({
        create: { width: 816, height: 816, channels: 3, background: '#00ff00' },
      })
        .composite([
          {
            input: await sharp({
              create: {
                width: 408,
                height: 816,
                channels: 3,
                background: '#0066ff',
              },
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
          key: 'generate:gpt-image-2.5-flare:low',
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
        feedback: 'Farbe stimmt nicht',
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
            payload: {
              generationAttemptId: failedGeneration.generationAttemptId,
            },
            attempts: 1,
            maxAttempts: 2,
            leaseExpiresAt: new Date(Date.now() + 60_000),
          },
          executionConfig,
        ),
        (error: unknown) => (error as { category?: string }).category === 'chroma-validation',
      );
      const billedFailure = await database.query<{
        provider_request_id: string;
        text_input_tokens: number;
        cost_microunits: string;
        reference_asset_id: string;
        keyed_asset_id: string;
        transparent_asset_id: string | null;
        parent_shelf_image_version_id: string;
        refinement_instruction: string;
      }>(
        `SELECT provider_request_id, text_input_tokens, cost_microunits,
         reference_asset_id, keyed_asset_id, transparent_asset_id,
         parent_shelf_image_version_id, refinement_instruction
       FROM generation_attempts WHERE id = $1`,
        [failedGeneration.generationAttemptId],
      );
      assert.equal(billedFailure.rows[0]?.provider_request_id, 'replay-billed-chroma-failure');
      assert.equal(billedFailure.rows[0]?.text_input_tokens, 11);
      assert.equal(billedFailure.rows[0]?.cost_microunits, '154');
      assert.ok(billedFailure.rows[0]?.reference_asset_id);
      assert.ok(billedFailure.rows[0]?.keyed_asset_id);
      assert.equal(billedFailure.rows[0]?.transparent_asset_id, null);
      assert.equal(
        billedFailure.rows[0]?.parent_shelf_image_version_id,
        (await database.query<{ id: string }>(
          `SELECT id FROM shelf_image_versions WHERE generation_attempt_id = $1`,
          [automaticGeneration.generationAttemptId],
        )).rows[0]?.id,
      );
      assert.equal(billedFailure.rows[0]?.refinement_instruction, 'Farbe stimmt nicht');
    } finally {
      storage.client.destroy();
      await database.end();
    }
  },
);

test(
  'identity sign-up grants credits, jobs charge once, and failed jobs refund',
  { skip: !enabled },
  async () => {
    const database = createDatabase(readDatabaseConfig());
    const storage = createPrivateObjectStorage(readObjectStorageConfig());
    try {
      await migrateDatabase(database);
      await ensurePrivateBucket(storage);
      await resetFixtures(database, storage);
      const identity = { provider: 'dev' as const, subject: 'new@example.com', email: 'new@example.com' };
      const account = (await signInWithIdentity(database, identity))!;
      assert.deepEqual(await signInWithIdentity(database, identity), account);
      // A second provider with the same verified email joins the same account.
      assert.deepEqual(
        await signInWithIdentity(database, { ...identity, provider: 'google', subject: 'g-1' }),
        account,
      );
      assert.deepEqual(await creditSummary(database, account.id), { metered: true, balance: signupCredits });

      const look = { accountId: account.id, kind: 'generate-look' as const, payload: {} };
      const jobId = await enqueueJob(database, { ...look, idempotencyKey: 'credits-look-1' });
      assert.equal(await enqueueJob(database, { ...look, idempotencyKey: 'credits-look-1' }), jobId);
      assert.equal(await creditBalance(database, account.id), signupCredits - 2);

      await database.query(
        `UPDATE remote_image_jobs SET state = 'leased', attempts = 1, max_attempts = 1,
           lease_owner = 'credits', lease_expires_at = now() + interval '1 minute' WHERE id = $1`,
        [jobId],
      );
      assert.equal(await failJob(database, jobId, 'credits', { retryable: false, category: 'test', detail: 'test' }), 'failed');
      assert.equal(await creditBalance(database, account.id), signupCredits);

      await grantCredits(database, { accountId: account.id, amount: -(signupCredits - 1), reason: 'grant' });
      await assert.rejects(
        enqueueJob(database, { ...look, idempotencyKey: 'credits-look-2' }),
        InsufficientCreditsError,
      );
      // Unmetered accounts, like the private deployment, are never charged.
      await enqueueJob(database, { ...look, accountId: fixtureIds.emptyAccount, idempotencyKey: 'credits-free' });
      assert.equal(await creditBalance(database, fixtureIds.emptyAccount), 0);

      await deleteAccount(database, storage, account.id);
      assert.equal((await database.query('SELECT 1 FROM accounts WHERE id = $1', [account.id])).rowCount, 0);
    } finally {
      storage.client.destroy();
      await database.end();
    }
  },
);

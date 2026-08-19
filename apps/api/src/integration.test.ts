import assert from 'node:assert/strict';
import test from 'node:test';

import {
  createDatabase,
  createPrivateObjectStorage,
  ensurePrivateBucket,
  fixtureCredentials,
  fixtureIds,
  migrateDatabase,
  readDatabaseConfig,
  readObjectStorageConfig,
  recordDetectionProposals,
  resetFixtures,
} from '@form/service';

import { createApp } from './app.js';

const enabled = process.env.FORM_RUN_SERVICE_INTEGRATION === 'true';
const sessionSecret = 'integration-session-secret-at-least-32-characters';
const sourcePng = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACXBIWXMAAAPoAAAD6AG1e1JrAAAADUlEQVQImWNgYGD4DwABBAEAfbLI3wAAAABJRU5ErkJggg==',
  'base64',
);
const replacementPng = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACXBIWXMAAAPoAAAD6AG1e1JrAAAADUlEQVQImWP4////fwAJ+wP9CNHoHgAAAABJRU5ErkJggg==',
  'base64',
);
const corruptPng = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9WlKZQAAAABJRU5ErkJggg==',
  'base64',
);

test('sessions and private media deny cross-account access', { skip: !enabled }, async () => {
  const database = createDatabase(readDatabaseConfig());
  const storage = createPrivateObjectStorage(readObjectStorageConfig());
  try {
    await migrateDatabase(database);
    await ensurePrivateBucket(storage);
    await resetFixtures(database, storage);
    const app = createApp({
      checkReadiness: async () => ({ status: 'ready', database: 'up', objectStorage: 'up' }),
      database,
      storage,
      sessionSecret,
      secureCookies: false,
      detectionModel: 'fixture-vision-model',
    });

    const appFetch = async (url: string, init?: RequestInit): Promise<Response> => {
      const parsed = new URL(url);
      return app.request(`${parsed.pathname}${parsed.search}`, init);
    };

    async function signIn(credentials: { email: string; password: string }): Promise<string> {
      const response = await app.request('/v1/auth/sign-in', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ...credentials, transport: 'token' }),
      });
      assert.equal(response.status, 200);
      const body = (await response.json()) as { session: { nativeToken: string } };
      assert.ok(body.session.nativeToken);
      return body.session.nativeToken;
    }

    const ownerToken = await signIn(fixtureCredentials.populated);
    const emptyToken = await signIn(fixtureCredentials.empty);
    const ownerHeaders = { Authorization: `Bearer ${ownerToken}` };
    const emptyHeaders = { Authorization: `Bearer ${emptyToken}` };

    await database.query(
      `UPDATE generation_attempts SET pricing_effective_date = DATE '2026-08-05',
         text_input_cost_microunits = 1685, image_input_cost_microunits = 6144,
         image_output_cost_microunits = 5130, cost_microunits = 12959
       WHERE id = $1`,
      [fixtureIds.reviewAttempt],
    );
    const billedDetail = await app.request(
      `/v1/wardrobe-items/${fixtureIds.needsReviewItem}`,
      { headers: ownerHeaders },
    );
    assert.equal(billedDetail.status, 200);
    assert.equal(
      (
        (await billedDetail.json()) as {
          generationAttempts: Array<{
            costBreakdown: { pricingEffectiveDate: string } | null;
          }>;
        }
      ).generationAttempts[0]?.costBreakdown?.pricingEffectiveDate,
      '2026-08-05',
    );

    const owning = await app.request('/v1/wardrobe-items?state=owning', {
      headers: ownerHeaders,
    });
    assert.equal(owning.status, 200);
    assert.equal(
      ((await owning.json()) as { wardrobeItems: unknown[] }).wardrobeItems.length,
      2,
    );
    const emptyWardrobe = await app.request('/v1/wardrobe-items', {
      headers: emptyHeaders,
    });
    assert.equal(emptyWardrobe.status, 200);
    assert.deepEqual(await emptyWardrobe.json(), { wardrobeItems: [] });
    assert.equal(
      (
        await app.request(`/v1/wardrobe-items/${fixtureIds.readyItem}`, {
          headers: emptyHeaders,
        })
      ).status,
      404,
    );

    const stateEditBody = {
      state: 'wanting',
      expectedRecordVersion: 2,
      idempotencyKey: 'integration-item-state-edit-0001',
    };
    const stateEditRequest = () =>
      app.request(`/v1/wardrobe-items/${fixtureIds.readyItem}`, {
        method: 'PATCH',
        headers: { ...ownerHeaders, 'Content-Type': 'application/json' },
        body: JSON.stringify(stateEditBody),
      });
    const stateEdit = await stateEditRequest();
    assert.equal(stateEdit.status, 200);
    const stateEditResponse = (await stateEdit.json()) as {
      wardrobeItem: { id: string; state: string; recordVersion: number };
    };
    assert.deepEqual(
      {
        id: stateEditResponse.wardrobeItem.id,
        state: stateEditResponse.wardrobeItem.state,
        recordVersion: stateEditResponse.wardrobeItem.recordVersion,
      },
      { id: fixtureIds.readyItem, state: 'wanting', recordVersion: 3 },
    );
    assert.deepEqual(await (await stateEditRequest()).json(), stateEditResponse);
    const staleEdit = await app.request(`/v1/wardrobe-items/${fixtureIds.readyItem}`, {
      method: 'PATCH',
      headers: { ...ownerHeaders, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        state: 'archived',
        expectedRecordVersion: 2,
        idempotencyKey: 'integration-item-state-edit-stale-0001',
      }),
    });
    assert.equal(staleEdit.status, 409);
    assert.equal(
      ((await staleEdit.json()) as { error: { code: string } }).error.code,
      'stale-record-version',
    );

    const additionalReviewAttempt = '50000000-0000-4000-8000-000000000099';
    await database.query(
      `INSERT INTO generation_attempts (
         id, account_id, wardrobe_item_id, source_photo_id, detection_proposal_id,
         state, reviewed_metadata, model, quality, output_size, prompt_version,
         reference_asset_id, keyed_asset_id, transparent_asset_id, provider_request_id,
         input_tokens, output_tokens, cost_microunits, failure_category,
         created_at, started_at, finished_at, resolved_chroma_key, provider_usage,
         text_input_tokens, image_input_tokens, service_tier, pricing_effective_date,
         text_input_cost_microunits, image_input_cost_microunits, image_output_cost_microunits
       )
       SELECT $1, account_id, wardrobe_item_id, source_photo_id, detection_proposal_id,
         state, reviewed_metadata, model, quality, output_size, prompt_version,
         reference_asset_id, keyed_asset_id, transparent_asset_id, provider_request_id,
         input_tokens, output_tokens, cost_microunits, failure_category,
         created_at + interval '1 second', started_at, finished_at, resolved_chroma_key, provider_usage,
         text_input_tokens, image_input_tokens, service_tier, pricing_effective_date,
         text_input_cost_microunits, image_input_cost_microunits, image_output_cost_microunits
       FROM generation_attempts WHERE id = $2`,
      [additionalReviewAttempt, fixtureIds.reviewAttempt],
    );
    const rejectedWithReviewRemaining = await app.request(
      `/v1/wardrobe-items/${fixtureIds.needsReviewItem}/generations/reject`,
      {
        method: 'POST',
        headers: { ...ownerHeaders, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          generationAttemptId: additionalReviewAttempt,
          expectedRecordVersion: 0,
          idempotencyKey: 'integration-reject-with-review-remaining-0001',
        }),
      },
    );
    assert.equal(rejectedWithReviewRemaining.status, 200);
    const rejectedWithReviewRemainingBody = (await rejectedWithReviewRemaining.json()) as {
      wardrobeItem: { status: string; recordVersion: number };
    };
    assert.equal(rejectedWithReviewRemainingBody.wardrobeItem.status, 'needs-review');
    assert.equal(rejectedWithReviewRemainingBody.wardrobeItem.recordVersion, 1);

    const keepBody = {
      generationAttemptId: fixtureIds.reviewAttempt,
      expectedRecordVersion: 1,
      idempotencyKey: 'integration-keep-shelf-image-0001',
    };
    const keepRequest = () =>
      app.request(
        `/v1/wardrobe-items/${fixtureIds.needsReviewItem}/shelf-image-versions/keep`,
        {
          method: 'POST',
          headers: { ...ownerHeaders, 'Content-Type': 'application/json' },
          body: JSON.stringify(keepBody),
        },
      );
    const kept = await keepRequest();
    assert.equal(kept.status, 200);
    const keptResponse = (await kept.json()) as {
      wardrobeItem: { id: string; status: string; recordVersion: number };
      shelfImageVersion: { generationAttemptId: string };
    };
    assert.equal(keptResponse.wardrobeItem.status, 'ready');
    assert.equal(keptResponse.wardrobeItem.recordVersion, 2);
    assert.equal(keptResponse.shelfImageVersion.generationAttemptId, fixtureIds.reviewAttempt);
    assert.deepEqual(await (await keepRequest()).json(), keptResponse);

    const generationBody = {
      wardrobeItemId: fixtureIds.needsReviewItem,
      idempotencyKey: 'integration-generation-command-0001',
    };
    const generationRequest = () =>
      app.request('/v1/generations', {
        method: 'POST',
        headers: { ...ownerHeaders, 'Content-Type': 'application/json' },
        body: JSON.stringify(generationBody),
      });
    const generation = await generationRequest();
    assert.equal(generation.status, 202);
    const generationResponse = await generation.json();
    assert.deepEqual(await (await generationRequest()).json(), generationResponse);

    const activeGenerationDeletion = await app.request(
      `/v1/wardrobe-items/${fixtureIds.queuedItem}`,
      {
        method: 'DELETE',
        headers: { ...ownerHeaders, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          expectedRecordVersion: 0,
          idempotencyKey: 'integration-delete-active-generation-0001',
        }),
      },
    );
    assert.equal(activeGenerationDeletion.status, 409);
    assert.equal(
      ((await activeGenerationDeletion.json()) as { error: { code: string } }).error.code,
      'invalid-wardrobe-transition',
    );

    await recordDetectionProposals(database, {
      accountId: fixtureIds.populatedAccount,
      sourcePhotoId: fixtureIds.sourcePhoto,
      detections: [
        {
          id: '80000000-0000-4000-8000-000000000001',
          name: 'Blue cap',
          category: 'hat',
          colors: ['blue'],
          boundingBox: { x: 100, y: 100, width: 200, height: 200 },
        },
      ],
    });
    const detectionList = await app.request(
      `/v1/source-photos/${fixtureIds.sourcePhoto}/detections`,
      { headers: ownerHeaders },
    );
    assert.equal(detectionList.status, 200);
    assert.equal(
      ((await detectionList.json()) as { detections: unknown[] }).detections.length,
      1,
    );
    const createItemBody = {
      detectionProposalId: '80000000-0000-4000-8000-000000000001',
      state: 'wanting',
      idempotencyKey: 'integration-create-item-0001',
    };
    const createItemRequest = () =>
      app.request('/v1/wardrobe-items', {
        method: 'POST',
        headers: { ...ownerHeaders, 'Content-Type': 'application/json' },
        body: JSON.stringify(createItemBody),
      });
    const createdItem = await createItemRequest();
    assert.equal(createdItem.status, 201);
    const createdItemResponse = (await createdItem.json()) as {
      wardrobeItem: { id: string; sourcePhotoId: string; metadata: { name: string } };
    };
    assert.equal(createdItemResponse.wardrobeItem.sourcePhotoId, fixtureIds.sourcePhoto);
    assert.equal(createdItemResponse.wardrobeItem.metadata.name, 'Blue cap');
    assert.deepEqual(await (await createItemRequest()).json(), createdItemResponse);

    const deleteBody = {
      expectedRecordVersion: 0,
      idempotencyKey: 'integration-permanent-delete-0001',
    };
    assert.equal(
      (
        await app.request(`/v1/wardrobe-items/${fixtureIds.failedItem}`, {
          method: 'DELETE',
          headers: { ...emptyHeaders, 'Content-Type': 'application/json' },
          body: JSON.stringify(deleteBody),
        })
      ).status,
      404,
    );
    const deleteRequest = () =>
      app.request(`/v1/wardrobe-items/${fixtureIds.failedItem}`, {
        method: 'DELETE',
        headers: { ...ownerHeaders, 'Content-Type': 'application/json' },
        body: JSON.stringify(deleteBody),
      });
    const deletion = await deleteRequest();
    assert.equal(deletion.status, 200);
    const deletionResponse = await deletion.json();
    assert.deepEqual(deletionResponse, {
      wardrobeItemId: fixtureIds.failedItem,
      sourcePhotoDeleted: false,
      deletedAssetIds: [],
    });
    assert.deepEqual(await (await deleteRequest()).json(), deletionResponse);

    const ownerDownload = await app.request(
      `/v1/assets/${fixtureIds.sourceAsset}/download`,
      { headers: ownerHeaders },
    );
    assert.equal(ownerDownload.status, 200);
    const ownerDownloadBody = (await ownerDownload.json()) as { downloadUrl: string };
    const downloaded = await appFetch(ownerDownloadBody.downloadUrl);
    assert.equal(downloaded.status, 200);
    assert.ok(
      (await downloaded.arrayBuffer()).byteLength > 1_000,
      'The signed download should return the realistic Source Photo fixture.',
    );

    const deniedDownload = await app.request(
      `/v1/assets/${fixtureIds.sourceAsset}/download`,
      { headers: emptyHeaders },
    );
    assert.equal(deniedDownload.status, 404);

    const intentResponse = await app.request('/v1/source-photos/upload-intents', {
      method: 'POST',
      headers: { ...ownerHeaders, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        fileName: 'source.png',
        contentType: 'image/png',
        byteSize: sourcePng.byteLength,
      }),
    });
    assert.equal(intentResponse.status, 201);
    const intent = (await intentResponse.json()) as {
      assetId: string;
      uploadUrl: string;
      headers: Record<string, string>;
    };
    const upload = await appFetch(intent.uploadUrl, {
      method: 'PUT',
      headers: intent.headers,
      body: sourcePng,
    });
    assert.equal(upload.status, 200);

    const completionBody = {
      assetId: intent.assetId,
      idempotencyKey: 'integration-source-completion-0001',
    };
    const deniedCompletion = await app.request('/v1/source-photos/complete', {
      method: 'POST',
      headers: { ...emptyHeaders, 'Content-Type': 'application/json' },
      body: JSON.stringify(completionBody),
    });
    assert.equal(deniedCompletion.status, 404);

    const completionRequest = () =>
      app.request('/v1/source-photos/complete', {
        method: 'POST',
        headers: { ...ownerHeaders, 'Content-Type': 'application/json' },
        body: JSON.stringify(completionBody),
      });
    const [completion, replay] = await Promise.all([completionRequest(), completionRequest()]);
    assert.equal(completion.status, 200);
    assert.equal(replay.status, 200);
    const completionResponse = (await completion.json()) as {
      asset: { id: string };
      sourcePhoto: { id: string };
    };
    assert.deepEqual(await replay.json(), completionResponse);

    const detectionBody = { idempotencyKey: 'integration-detection-enqueue-0001' };
    const detectionRequest = (headers: Record<string, string>) =>
      app.request(`/v1/source-photos/${completionResponse.sourcePhoto.id}/detections`, {
        method: 'POST',
        headers: { ...headers, 'Content-Type': 'application/json' },
        body: JSON.stringify(detectionBody),
      });
    assert.equal((await detectionRequest(emptyHeaders)).status, 404);
    const queuedDetection = await detectionRequest(ownerHeaders);
    assert.equal(queuedDetection.status, 202);
    const queuedDetectionBody = await queuedDetection.json();
    assert.deepEqual(await (await detectionRequest(ownerHeaders)).json(), queuedDetectionBody);
    const queuedDetectionStatus = await app.request(
      `/v1/source-photos/${completionResponse.sourcePhoto.id}/detections`,
      { headers: ownerHeaders },
    );
    assert.equal(queuedDetectionStatus.status, 200);
    assert.equal(
      ((await queuedDetectionStatus.json()) as { attempt: { state: string } }).attempt.state,
      'queued',
    );
    const queuedDetectionRecord = await database.query<{ model: string }>(
      `SELECT model FROM detection_attempts WHERE id = $1`,
      [(queuedDetectionBody as { detectionAttemptId: string }).detectionAttemptId],
    );
    assert.equal(queuedDetectionRecord.rows[0]?.model, 'fixture-vision-model');

    const overwrite = await appFetch(intent.uploadUrl, {
      method: 'PUT',
      headers: intent.headers,
      body: replacementPng,
    });
    assert.equal(overwrite.status, 200);
    const immutableDownload = await app.request(
      `/v1/assets/${completionResponse.asset.id}/download`,
      { headers: ownerHeaders },
    );
    assert.equal(immutableDownload.status, 200);
    const immutableDownloadBody = (await immutableDownload.json()) as { downloadUrl: string };
    const immutableBytes = Buffer.from(await (await appFetch(immutableDownloadBody.downloadUrl)).arrayBuffer());
    assert.deepEqual(immutableBytes, sourcePng);

    async function createIntent(bytes: Buffer): Promise<{ assetId: string; uploadUrl: string; headers: Record<string, string> }> {
      const response = await app.request('/v1/source-photos/upload-intents', {
        method: 'POST',
        headers: { ...ownerHeaders, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          fileName: 'source.png',
          contentType: 'image/png',
          byteSize: bytes.byteLength,
        }),
      });
      assert.equal(response.status, 201);
      return response.json() as Promise<{
        assetId: string;
        uploadUrl: string;
        headers: Record<string, string>;
      }>;
    }

    const missingIntent = await createIntent(sourcePng);
    const missingCompletion = await app.request('/v1/source-photos/complete', {
      method: 'POST',
      headers: { ...ownerHeaders, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        assetId: missingIntent.assetId,
        idempotencyKey: 'integration-missing-upload-0001',
      }),
    });
    assert.equal(missingCompletion.status, 409);
    assert.equal(((await missingCompletion.json()) as { error: { code: string } }).error.code, 'upload-missing');

    const corruptIntent = await createIntent(corruptPng);
    assert.equal(
      (
        await appFetch(corruptIntent.uploadUrl, {
          method: 'PUT',
          headers: corruptIntent.headers,
          body: corruptPng,
        })
      ).status,
      200,
    );
    const corruptCompletion = await app.request('/v1/source-photos/complete', {
      method: 'POST',
      headers: { ...ownerHeaders, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        assetId: corruptIntent.assetId,
        idempotencyKey: 'integration-corrupt-upload-0001',
      }),
    });
    assert.equal(corruptCompletion.status, 400);
    assert.equal(((await corruptCompletion.json()) as { error: { code: string } }).error.code, 'invalid-image');

    await database.query(
      `UPDATE generation_attempts SET state = 'failed', failure_category = 'integration-cleanup'
       WHERE account_id = $1 AND state IN ('queued', 'processing')`,
      [fixtureIds.populatedAccount],
    );
    await database.query(
      `UPDATE remote_image_jobs SET state = 'failed', finished_at = now(),
         lease_owner = NULL, lease_expires_at = NULL
       WHERE account_id = $1 AND state IN ('queued', 'leased')`,
      [fixtureIds.populatedAccount],
    );

    const remainingItems = [
      { id: createdItemResponse.wardrobeItem.id, version: 0 },
      { id: fixtureIds.queuedItem, version: 0 },
      { id: fixtureIds.needsReviewItem, version: 3 },
      { id: fixtureIds.readyItem, version: 3 },
    ];
    type DeletionBody = {
      sourcePhotoDeleted: boolean;
      deletedAssetIds: string[];
    };
    let finalDeletion: DeletionBody | undefined;
    for (const [index, item] of remainingItems.entries()) {
      const response = await app.request(`/v1/wardrobe-items/${item.id}`, {
        method: 'DELETE',
        headers: { ...ownerHeaders, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          expectedRecordVersion: item.version,
          idempotencyKey: `integration-delete-remaining-${index.toString().padStart(4, '0')}`,
        }),
      });
      assert.equal(response.status, 200);
      finalDeletion = (await response.json()) as DeletionBody;
      assert.equal(finalDeletion?.sourcePhotoDeleted, index === remainingItems.length - 1);
    }
    assert.deepEqual(finalDeletion?.deletedAssetIds, [
      fixtureIds.sourceAsset,
      fixtureIds.keyedAssetOne,
      fixtureIds.transparentAssetOne,
      fixtureIds.keyedAssetTwo,
      fixtureIds.transparentAssetTwo,
    ]);
    assert.equal(
      (
        await app.request(`/v1/assets/${fixtureIds.sourceAsset}/download`, {
          headers: ownerHeaders,
        })
      ).status,
      404,
    );

    const cookieSignIn = await app.request('/v1/auth/sign-in', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ...fixtureCredentials.populated, transport: 'cookie' }),
    });
    assert.equal(cookieSignIn.status, 200);
    const cookieBody = (await cookieSignIn.json()) as { session: { nativeToken: null } };
    assert.equal(cookieBody.session.nativeToken, null);
    const setCookie = cookieSignIn.headers.get('set-cookie');
    assert.match(setCookie ?? '', /HttpOnly/i);
    assert.match(setCookie ?? '', /SameSite=Strict/i);
    const cookie = setCookie?.split(';')[0];
    const restored = await app.request('/v1/auth/session', { headers: { Cookie: cookie ?? '' } });
    assert.equal(restored.status, 200);
    const signedOut = await app.request('/v1/auth/sign-out', {
      method: 'POST',
      headers: { Cookie: cookie ?? '' },
    });
    assert.equal(signedOut.status, 204);
    const revoked = await app.request('/v1/auth/session', { headers: { Cookie: cookie ?? '' } });
    assert.equal(revoked.status, 401);
  } finally {
    storage.client.destroy();
    await database.end();
  }
});

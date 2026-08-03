import assert from 'node:assert/strict';
import test from 'node:test';

import {
  AssetNotFoundError,
  createDatabase,
  DurableJobQueue,
  fixtureAccounts,
  PrivateAssetStore,
  readServiceConfig,
  resetFixtures,
  runMigrations,
} from './index.js';

const integrationEnabled = process.env.RUN_SERVICE_INTEGRATION === 'true';

test('PostgreSQL jobs and private S3 assets survive process boundaries', {
  skip: !integrationEnabled,
}, async () => {
  const config = readServiceConfig();
  const database = createDatabase(config.DATABASE_URL);
  const assets = new PrivateAssetStore(database, config);
  const jobs = new DurableJobQueue(database);

  try {
    await runMigrations(database);
    await assets.ensurePrivateBucket();
    await resetFixtures(database, assets);

    const owner = fixtureAccounts[0];
    const stranger = fixtureAccounts[1];
    const body = new TextEncoder().encode('private fixture');
    const intent = await assets.createUploadIntent({
      accountId: owner.id,
      purpose: 'fixture',
      fileName: 'fixture.txt',
      contentType: 'text/plain',
      byteSize: body.byteLength,
    });
    const upload = await fetch(intent.uploadUrl, {
      method: 'PUT',
      headers: intent.headers,
      body,
    });
    assert.equal(upload.ok, true);
    await assets.completeUpload(owner.id, intent.assetId);
    const anonymousRead = await fetch(
      `${config.S3_ENDPOINT}/${config.S3_BUCKET}/${intent.objectKey}`,
    );
    assert.equal(anonymousRead.status, 403);
    await assert.rejects(
      assets.createDownloadUrl(stranger.id, intent.assetId),
      AssetNotFoundError,
    );
    const download = await fetch(
      await assets.createDownloadUrl(owner.id, intent.assetId),
    );
    assert.equal(await download.text(), 'private fixture');

    const first = await jobs.enqueue({
      accountId: owner.id,
      kind: 'detect-source-photo',
      payload: { assetId: intent.assetId },
      idempotencyKey: 'fixture-detection-0001',
    });
    const duplicate = await jobs.enqueue({
      accountId: owner.id,
      kind: 'detect-source-photo',
      payload: { assetId: intent.assetId },
      idempotencyKey: 'fixture-detection-0001',
    });
    assert.equal(duplicate.id, first.id);

    const claimed = await jobs.claim({
      workerId: 'integration-worker',
      kinds: ['detect-source-photo'],
      leaseSeconds: 1,
      perAccountConcurrency: 1,
    });
    assert.equal(claimed?.id, first.id);
    await database.query(
      `UPDATE remote_image_jobs SET lease_expires_at = now() - interval '1 second'
       WHERE id = $1`,
      [first.id],
    );
    assert.equal(await jobs.recoverExpiredLeases(), 1);
    const reclaimed = await jobs.claim({
      workerId: 'replacement-worker',
      kinds: ['detect-source-photo'],
      leaseSeconds: 30,
      perAccountConcurrency: 1,
    });
    assert.equal(reclaimed?.id, first.id);
    await jobs.succeed(first.id, 'replacement-worker', { detections: [] });
  } finally {
    await database.end();
  }
});

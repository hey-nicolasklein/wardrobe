import assert from 'node:assert/strict';
import test from 'node:test';

import {
  claimJobs,
  createDatabase,
  createPrivateObjectStorage,
  ensurePrivateBucket,
  enqueueJob,
  fixtureIds,
  migrateDatabase,
  readDatabaseConfig,
  readObjectStorageConfig,
  recoverExpiredLeases,
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

import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import test from 'node:test';
import sharp from 'sharp';
import {
  createDatabase,
  createPrivateObjectStorage,
  ensurePrivateBucket,
  fixtureIds,
  migrateDatabase,
  readDatabaseConfig,
  readObjectStorageConfig,
  resetFixtures,
} from '@form/service';
import { createApp } from './app.js';

const enabled = process.env.FORM_RUN_SERVICE_INTEGRATION === 'true';
test(
  'personal wardrobe needs no login, saves photos idempotently, protects reset and preserves other accounts',
  { skip: !enabled },
  async () => {
    const database = createDatabase(readDatabaseConfig());
    const storage = createPrivateObjectStorage(readObjectStorageConfig());
    try {
      await migrateDatabase(database);
      await ensurePrivateBucket(storage);
      await resetFixtures(database, storage);
      const app = createApp({
        database,
        storage,
        sessionSecret: 'personal-test-secret-at-least-32-characters',
        personalAccountId: fixtureIds.populatedAccount,
        webOrigin: 'https://wardrobe.test',
        checkReadiness: async () => ({
          status: 'ready',
          database: 'up',
          objectStorage: 'up',
        }),
      });
      const post = (
        path: string,
        body: unknown,
        origin = 'https://wardrobe.test',
      ) =>
        app.request(path, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', Origin: origin },
          body: JSON.stringify(body),
        });
      assert.equal((await app.request('/v1/auth/session')).status, 200);
      const pendingPreview = await app.request(`/v1/wardrobe-items/${fixtureIds.needsReviewItem}/preview`);
    assert.equal(pendingPreview.status, 200);
    const pendingDimensions = await sharp(Buffer.from(await pendingPreview.arrayBuffer())).metadata();
    assert.equal(pendingDimensions.width, pendingDimensions.height, 'pending catalog image is used instead of the rectangular source photo');
    const body = {
        sourcePhotoId: fixtureIds.sourcePhoto,
        metadata: {
          name: 'Mein Hemd',
          category: 'top',
          colors: ['Blau'],
          notes: null,
        },
        state: 'owning',
        idempotencyKey: randomUUID(),
      };
      const created = await post('/v1/wardrobe-items/from-photo', body);
      assert.equal(created.status, 201, await created.clone().text());
      const createdBody = (await created.json()) as {
        wardrobeItem: { id: string; recordVersion: number };
      };
      const item = createdBody.wardrobeItem;
      const replay = await post('/v1/wardrobe-items/from-photo', body);
      assert.deepEqual(await replay.json(), createdBody);
      const preview = await app.request(
        `/v1/wardrobe-items/${item.id}/preview`,
      );
      assert.equal(preview.status, 200);
      assert.equal(preview.headers.get('Content-Type'), 'image/webp');
      assert.ok((await preview.arrayBuffer()).byteLength > 100);
      assert.equal(
        (
          await post(
            '/v1/wardrobe-items/from-photo',
            { ...body, idempotencyKey: randomUUID() },
            'https://unrelated.test',
          )
        ).status,
        403,
      );
      assert.equal(
        (
          await post('/v1/generations', {
            wardrobeItemId: item.id,
            quality: 'high',
            idempotencyKey: randomUUID(),
          })
        ).status,
        400,
      );
      assert.equal(
        (await post('/v1/personal/reset', { confirmation: 'wrong' })).status,
        400,
      );
      assert.equal(
        (await post('/v1/personal/reset', { confirmation: 'ALLES LÖSCHEN' }))
          .status,
        409,
      );
      await database.query(
        "UPDATE remote_image_jobs SET state = 'cancelled', lease_owner = NULL, lease_expires_at = NULL WHERE account_id = $1",
        [fixtureIds.populatedAccount],
      );
      const reset = await post('/v1/personal/reset', {
        confirmation: 'ALLES LÖSCHEN',
      });
      assert.equal(reset.status, 204, await reset.text());
      assert.deepEqual(await (await app.request('/v1/wardrobe-items')).json(), {
        wardrobeItems: [],
      });
      assert.equal(
        (await app.request(`/v1/wardrobe-items/${item.id}/preview`)).status,
        404,
      );
      assert.equal(
        (
          await database.query('SELECT id FROM accounts WHERE id = $1', [
            fixtureIds.emptyAccount,
          ])
        ).rowCount,
        1,
      );
      assert.equal((await app.request('/v1/auth/session')).status, 200);
    } finally {
      storage.client.destroy();
      storage.signingClient.destroy();
      await database.end();
    }
  },
);

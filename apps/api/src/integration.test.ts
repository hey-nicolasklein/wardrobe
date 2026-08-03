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
  resetFixtures,
} from '@form/service';

import { createApp } from './app.js';

const enabled = process.env.FORM_RUN_SERVICE_INTEGRATION === 'true';
const sessionSecret = 'integration-session-secret-at-least-32-characters';
const fixturePng = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  'base64',
);
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
    });

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

    const ownerDownload = await app.request(
      `/v1/assets/${fixtureIds.sourceAsset}/download`,
      { headers: ownerHeaders },
    );
    assert.equal(ownerDownload.status, 200);
    const ownerDownloadBody = (await ownerDownload.json()) as { downloadUrl: string };
    const downloaded = await fetch(ownerDownloadBody.downloadUrl);
    assert.equal(downloaded.status, 200);
    assert.equal((await downloaded.arrayBuffer()).byteLength, fixturePng.byteLength);

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
    const upload = await fetch(intent.uploadUrl, {
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
    const completionResponse = (await completion.json()) as { asset: { id: string } };
    assert.deepEqual(await replay.json(), completionResponse);

    const overwrite = await fetch(intent.uploadUrl, {
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
    const immutableBytes = Buffer.from(await (await fetch(immutableDownloadBody.downloadUrl)).arrayBuffer());
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
        await fetch(corruptIntent.uploadUrl, {
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

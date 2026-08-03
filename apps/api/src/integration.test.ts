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
const onePixelPng = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
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
    assert.equal((await downloaded.arrayBuffer()).byteLength, onePixelPng.byteLength);

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
        byteSize: onePixelPng.byteLength,
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
      body: onePixelPng,
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

    const completion = await app.request('/v1/source-photos/complete', {
      method: 'POST',
      headers: { ...ownerHeaders, 'Content-Type': 'application/json' },
      body: JSON.stringify(completionBody),
    });
    assert.equal(completion.status, 200);
    const replay = await app.request('/v1/source-photos/complete', {
      method: 'POST',
      headers: { ...ownerHeaders, 'Content-Type': 'application/json' },
      body: JSON.stringify(completionBody),
    });
    assert.deepEqual(await replay.json(), await completion.json());

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

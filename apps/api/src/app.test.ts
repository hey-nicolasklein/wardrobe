import assert from 'node:assert/strict';
import test from 'node:test';

import { contractVersion } from '@form/contracts';
import type { Database, PrivateObjectStorage } from '@form/service';

import { createApp } from './app.js';

test('native clients can check the contract through the public v1 proxy', async () => {
  const response = await createApp(async () => {
    throw new Error('metadata should not require external services');
  }).request('/v1/meta');

  assert.equal(response.status, 200);
  assert.equal(response.headers.get('Cache-Control'), 'no-store');
  assert.deepEqual(await response.json(), { service: 'form-api', contractVersion });
});

test('liveness does not depend on external services', async () => {
  const response = await createApp(async () => {
    throw new Error('readiness should not run');
  }).request('/health/live');

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { service: 'form-api', status: 'alive' });
});

test('readiness reports dependency failure with 503', async () => {
  const response = await createApp(async () => ({
    status: 'not-ready',
    database: 'up',
    objectStorage: 'down',
  })).request('/health/ready');

  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), {
    status: 'not-ready',
    database: 'up',
    objectStorage: 'down',
  });
});

test('sign-in rate limit keys on the proxy-resolved address, not X-Forwarded-For', async () => {
  // The limiter answers before any route touches these, so empty stand-ins suffice.
  const app = createApp({
    checkReadiness: async () => {
      throw new Error('readiness should not run');
    },
    database: {} as Database,
    storage: {} as PrivateObjectStorage,
    sessionSecret: 'rate-limit-test-secret-at-least-32-characters',
  });
  const signIn = (realIp: string, forwardedFor: string) =>
    app.request('/v1/auth/sign-in', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Real-IP': realIp, 'X-Forwarded-For': forwardedFor },
      body: '{}',
    });

  for (let attempt = 0; attempt < 10; attempt++) await signIn('203.0.113.7', `198.51.100.${attempt}`);

  assert.equal((await signIn('203.0.113.7', '198.51.100.99')).status, 429);
  assert.notEqual((await signIn('203.0.113.8', '198.51.100.99')).status, 429);
});

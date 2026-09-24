import assert from 'node:assert/strict';
import test from 'node:test';

import { contractVersion } from '@form/contracts';

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

import assert from 'node:assert/strict';
import test from 'node:test';

import { sanitizeFileName } from './assets.js';
import { shouldRetryJob } from './jobs.js';

test('asset names cannot escape their account-scoped object prefix', () => {
  assert.equal(sanitizeFileName('../../private photo.heic'), '..-..-private-photo.heic');
  assert.equal(sanitizeFileName('💚'), 'upload');
});

test('only one transient retry is allowed', () => {
  assert.equal(shouldRetryJob('timeout', 1, 2), true);
  assert.equal(shouldRetryJob('timeout', 2, 2), false);
  assert.equal(shouldRetryJob('moderation', 1, 2), false);
});

import assert from 'node:assert/strict';
import test from 'node:test';

import { RateLimiter } from './rate-limit.js';

test('rate limiter blocks after the limit and resets with the next window', () => {
  let now = 0;
  const limiter = new RateLimiter(2, 1_000, () => now);
  assert.equal(limiter.take('a'), true);
  assert.equal(limiter.take('a'), true);
  assert.equal(limiter.take('a'), false);
  assert.equal(limiter.take('b'), true);
  now = 1_000;
  assert.equal(limiter.take('a'), true);
});

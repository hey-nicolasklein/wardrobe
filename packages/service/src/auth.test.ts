import assert from 'node:assert/strict';
import test from 'node:test';

import { hashPassword, verifyPassword } from './auth.js';

test('password hashes are salted and verify without retaining the password', async () => {
  const first = await hashPassword('correct horse battery staple');
  const second = await hashPassword('correct horse battery staple');

  assert.notEqual(first, second);
  assert.equal(first.includes('correct horse battery staple'), false);
  assert.equal(await verifyPassword('correct horse battery staple', first), true);
  assert.equal(await verifyPassword('wrong password', first), false);
  assert.equal(await verifyPassword('anything', 'not-a-password-hash'), false);
});

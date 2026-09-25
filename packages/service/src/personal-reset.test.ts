import assert from 'node:assert/strict';
import test from 'node:test';

import {
  PERSONAL_RESET_CONFIRMATION,
  PERSONAL_RESET_LEGACY_CONFIRMATION,
  isPersonalResetConfirmation,
} from './personal-reset.js';

test('accepts legacy and locale-independent reset confirmations', () => {
  assert.equal(isPersonalResetConfirmation(PERSONAL_RESET_LEGACY_CONFIRMATION), true);
  assert.equal(isPersonalResetConfirmation(PERSONAL_RESET_CONFIRMATION), true);
});

test('rejects other confirmation values', () => {
  assert.equal(isPersonalResetConfirmation('wrong'), false);
  assert.equal(isPersonalResetConfirmation(''), false);
  assert.equal(isPersonalResetConfirmation(null), false);
});

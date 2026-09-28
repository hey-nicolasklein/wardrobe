import assert from 'node:assert/strict';
import test from 'node:test';

import { lookPrompt } from './inspiration.js';
import { isLookShot, pickReshoot, shotsFor, shotStyle } from './look-shots.js';

test('hidden shots are left out unless none would remain', () => {
  const street = shotsFor('street', []).map(({ id }) => id);
  assert.ok(street.includes('street-low-wide'));
  assert.ok(!shotsFor('street', ['street-low-wide']).some(({ id }) => id === 'street-low-wide'));
  assert.deepEqual(shotsFor('mirror', ['mirror-straight', 'mirror-angled', 'mirror-step']).length, 3);
  assert.equal(shotStyle('street-steps'), 'street');
  assert.equal(isLookShot('studio-backdrop'), false);
});

test('a reshoot always changes the shot within the style', () => {
  for (let i = 0; i < 20; i++) {
    const shot = pickReshoot('street', 'street-walking', ['street-low-wide']);
    assert.notEqual(shot, 'street-walking');
    assert.notEqual(shot, 'street-low-wide');
    assert.equal(shotStyle(shot), 'street');
  }
});

test('the picked shot becomes the camera sentence of the prompt', () => {
  const concept = { activity: 'waiting for a friend', scene: 'a street corner', mood: 'easy', framing: 'full-body' as const, shot: 'street-low-wide' };
  const item = [{ name: 'Grey sweatpants', category: 'pants', colors: ['grey'] }];
  assert.match(lookPrompt(concept, item, null, true, { style: 'street' }), /Camera: Shot from low, about knee height/);
  assert.doesNotMatch(lookPrompt({ ...concept, shot: undefined }, item, null, true, { style: 'street' }), /Camera:/);
});

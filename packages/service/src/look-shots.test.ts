import assert from 'node:assert/strict';
import test from 'node:test';

import { lookPrompt } from './inspiration.js';
import { isLookShot, pickShot, shotStyle, type ShotWeight } from './look-shots.js';

const weight = (shot: string, value: number): ShotWeight => ({
  style: 'street', shot, likes: 0, recent: false, hidden: value === 0, weight: value, chance: 0,
});

test('shots are drawn by weight and hidden ones never', () => {
  const weights = [weight('street-low-wide', 0), weight('street-walking', 1), weight('street-steps', 3)];
  // The roll walks the weights in order: [0, 1) walking, [1, 4) steps.
  assert.equal(pickShot(weights, 'street', undefined, () => 0.2), 'street-walking');
  assert.equal(pickShot(weights, 'street', undefined, () => 0.3), 'street-steps');
  for (let i = 0; i < 20; i++) assert.notEqual(pickShot(weights, 'street'), 'street-low-wide');
  assert.equal(shotStyle('street-steps'), 'street');
  assert.equal(isLookShot('studio-backdrop'), false);
});

test('another perspective never repeats the current shot', () => {
  const weights = [weight('street-walking', 5), weight('street-steps', 0)];
  // Only a hidden shot is left, so it is taken rather than repeating.
  assert.equal(pickShot(weights, 'street', 'street-walking'), 'street-steps');
});

test('the picked shot becomes the camera sentence of the prompt', () => {
  const concept = { activity: 'waiting for a friend', scene: 'a street corner', mood: 'easy', framing: 'full-body' as const, shot: 'street-low-wide' };
  const item = [{ name: 'Grey sweatpants', category: 'pants', colors: ['grey'] }];
  assert.match(lookPrompt(concept, item, null, true, { style: 'street' }), /Camera: Shot from low, about knee height/);
  assert.doesNotMatch(lookPrompt({ ...concept, shot: undefined }, item, null, true, { style: 'street' }), /Camera:/);
});

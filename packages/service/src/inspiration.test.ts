import assert from 'node:assert/strict';
import test from 'node:test';

import {
  candidatesForLookPlan,
  lookPrompt,
  normalizeAutomaticLookItems,
} from './inspiration.js';

const candidates = [
  ['top-one', 'top'], ['top-two', 'top'], ['jacket-one', 'jacket'], ['jacket-two', 'jacket'],
  ['pants', 'pants'], ['skirt', 'skirt'], ['dress', 'dress'], ['bag', 'bag'],
] as const;

test('automatic look plans keep one garment per outfit slot', () => {
  const items = candidates.map(([id, category]) => ({ id, category }));
  assert.deepEqual(
    normalizeAutomaticLookItems(
      ['top-one', 'top-two', 'jacket-one', 'jacket-two', 'pants', 'skirt', 'bag'],
      items,
      [],
    ),
    ['top-one', 'jacket-one', 'pants', 'bag'],
  );
  assert.deepEqual(
    normalizeAutomaticLookItems(['top-one', 'jacket-one', 'dress', 'pants'], items, []),
    ['jacket-one', 'dress'],
  );
});

test('explicit selections are retained while automatic duplicates are removed', () => {
  const items = candidates.map(([id, category]) => ({ id, category }));
  assert.deepEqual(
    normalizeAutomaticLookItems(['top-two', 'top-one', 'jacket-one', 'jacket-two', 'pants'], items, ['top-one', 'jacket-one']),
    ['top-one', 'jacket-one', 'pants'],
  );
});

test('image-model completion exposes only the selected wardrobe items to planning', () => {
  const items = candidates.map(([id, category]) => ({ id, category }));
  assert.deepEqual(
    candidatesForLookPlan(items, ['top-one'], false),
    [{ id: 'top-one', category: 'top' }],
  );
  assert.equal(candidatesForLookPlan(items, ['top-one'], true), items);
});

test('image-model completion allows unreferenced garments without weakening references', () => {
  const concept = {
    activity: 'walking',
    scene: 'a quiet street',
    mood: 'relaxed',
    framing: 'full-body' as const,
  };
  const item = [{ name: 'Blue shirt', category: 'top', colors: ['blue'] }];
  const freePrompt = lookPrompt(concept, item, null, false);
  assert.match(freePrompt, /Complete the outfit with coherent unreferenced garments/);
  assert.match(freePrompt, /Do not replace, restyle, hide, or obscure any referenced garment/);
  assert.doesNotMatch(freePrompt, /exactly these referenced major garments/);
  assert.match(lookPrompt(concept, item, null, true), /Do not invent other major garments/);
});

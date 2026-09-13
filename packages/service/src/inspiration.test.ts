import assert from 'node:assert/strict';
import test from 'node:test';

import { normalizeAutomaticLookItems } from './inspiration.js';

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

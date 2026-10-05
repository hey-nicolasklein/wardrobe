import assert from 'node:assert/strict';
import test from 'node:test';

import {
  candidatesForLookPlan,
  lookFocus,
  lookPrompt,
  pickCamera,
  tryOnPrompt,
  normalizeAutomaticLookItems,
  similarOutfit,
  recentForLookPlan,
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

test('recency history never asks the planner to avoid a mandated item', () => {
  const concept = { activity: 'walking', scene: 'a street', framing: 'full-body', mood: 'calm' } as const;
  assert.deepEqual(
    recentForLookPlan(
      [{ ids: ['top-one', 'pants', 'bag'], planned_concept: concept }],
      ['top-one', 'pants'],
    ),
    [{ itemIds: ['bag'], concept }],
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

test('look prompts describe the ordered garment board for multiple pieces', () => {
  const concept = {
    activity: 'walking',
    scene: 'a quiet street',
    mood: 'relaxed',
    framing: 'full-body' as const,
  };
  const items = [
    { name: 'Blue shirt', category: 'top', colors: ['blue'] },
    { name: 'Black trousers', category: 'pants', colors: ['black'] },
  ];
  const combined = lookPrompt(concept, items, null, true);
  assert.match(combined, /ordered board/);
  assert.match(combined, /1\. Blue shirt; 2\. Black trousers/);
  assert.doesNotMatch(lookPrompt(concept, items.slice(0, 1), null, true), /ordered board/);
});

test('look styles change the camera', () => {
  const concept = { activity: 'walking', scene: 'a street', mood: 'calm', framing: 'full-body' as const };
  const item = [{ name: 'Black trousers', category: 'pants', colors: ['black'] }];
  const candid = lookPrompt(concept, item, null, true);
  assert.match(candid, /friend casually took it on an iPhone/);
  assert.match(candid, /must never be cropped/);
  assert.match(lookPrompt(concept, item, null, true, { style: 'mirror' }), /mirror selfie/);
  assert.doesNotMatch(lookPrompt(concept, item, null, true, { style: 'mirror' }), /Avoid selfies/);
});

test('selected completion frames the body zone the picked pieces share', () => {
  assert.equal(lookFocus(['jacket']), 'upper');
  assert.equal(lookFocus(['top', 'scarf', 'bag']), 'upper');
  assert.equal(lookFocus(['pants', 'shoes']), 'lower');
  assert.equal(lookFocus(['shoes']), 'feet');
  assert.equal(lookFocus(['jacket', 'shoes']), null);
  assert.equal(lookFocus(['dress']), null);

  const concept = { activity: 'walking', scene: 'a street', mood: 'calm', framing: 'full-body' as const };
  const jacket = [{ name: 'Leather jacket', category: 'jacket', colors: ['black'] }];
  const prompt = lookPrompt(concept, jacket, null, false, { style: 'street', focus: 'upper' });
  assert.match(prompt, /waist up/);
  assert.doesNotMatch(prompt, /head to shoes/);
  assert.match(prompt, /neutral base layer/);
  assert.doesNotMatch(prompt, /Complete the outfit/);
});

test('parties get the flash look and every look avoids the stock-photo polish', () => {
  const concept = { activity: 'laughing', scene: 'a rooftop party', mood: 'loose', framing: 'full-body' as const };
  const item = [{ name: 'Fur coat', category: 'jacket', colors: ['brown'] }];
  const party = lookPrompt(concept, item, null, true, { occasion: 'party' });
  assert.match(party, /Light it with a direct on-camera flash/);
  assert.doesNotMatch(party, /If the scene is at night/);
  assert.match(party, /stock-photo/);
  assert.match(party, /not seated/);
  // A drawn camera replaces the occasion lighting.
  assert.match(lookPrompt({ ...concept, camera: 'flash' }, item, null, true, { occasion: 'casual' }), /Fujifilm X100 with the built-in flash/);
  const casual = lookPrompt(concept, item, null, true, { occasion: 'casual' });
  assert.doesNotMatch(casual, /flash/);
  assert.match(lookPrompt(concept, item, null, true), /If the scene is at night/);
  const street = lookPrompt(concept, item, null, true, { style: 'street' });
  assert.match(street, /friend took on an iPhone/);
  assert.doesNotMatch(street, /telephoto lens with shallow/);
});

test('try-on edits the own photo and keeps everything but the clothes', () => {
  const prompt = tryOnPrompt([{ name: 'Fur coat', category: 'jacket', colors: ['brown'] }]);
  assert.match(prompt, /^Recreate the first reference/);
  assert.match(prompt, /same person, face, hairstyle, build, pose/);
  // Words the image safety filter read as undressing a real person.
  assert.doesNotMatch(prompt, /skin|body shape|what the person wears/);
  assert.match(prompt, /Fur coat \(jacket; brown\)/);
  assert.doesNotMatch(prompt, /identity reference/);
});

test('proposals that change only one added piece count as the same outfit', () => {
  assert.equal(similarOutfit(['shirt', 'jeans', 'boots'], ['shirt', 'jeans', 'sneakers'], []), true);
  assert.equal(similarOutfit(['shirt', 'jeans', 'boots'], ['tee', 'skirt', 'boots'], []), false);
  // The user's exact pieces are shared by design and do not count.
  assert.equal(similarOutfit(['coat', 'shirt', 'jeans'], ['coat', 'tee', 'skirt'], ['coat']), false);
  assert.equal(similarOutfit(['coat', 'boots'], ['coat', 'sneakers'], ['coat']), false);
});

test('nights and parties always get the flash camera, other looks either', () => {
  assert.equal(pickCamera('party', () => 0.9), 'flash');
  assert.equal(pickCamera(null, () => 0.9), 'iphone');
  assert.equal(pickCamera('casual', () => 0.1), 'flash');
});

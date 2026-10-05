import assert from 'node:assert/strict';
import test from 'node:test';

import { adjustOutfit, pickAnchor, warmthClash } from './look-proposals.js';

const now = new Date('2026-10-05T12:00:00Z');
const old = new Date('2026-01-01T00:00:00Z');
const item = (id: string, category: string, createdAt = old) => ({ id, category, createdAt });

test('the anchor favours pieces worn least and skips sibling and clashing pieces', () => {
  const candidates = [
    item('worn-top', 'top'),
    item('fresh-pants', 'pants'),
    item('sibling-skirt', 'skirt'),
    item('ring', 'accessory'),
    item('dress', 'dress'),
  ];
  const usage = new Map([['worn-top', { uses: 6, recent: true }]]);
  const picked = pickAnchor({
    candidates,
    usage,
    exactItemIds: ['dress'],
    siblingItemIds: ['sibling-skirt'],
    now,
    random: () => 0.5,
  });
  // A dress already fills top and lower slots; accessories never anchor.
  assert.equal(picked, null);

  const free = pickAnchor({ candidates, usage, exactItemIds: [], siblingItemIds: ['sibling-skirt'], now, random: () => 0.5 });
  assert.notEqual(free?.itemId, 'worn-top');
  assert.notEqual(free?.itemId, 'sibling-skirt');
});

test('the anchor reason says why the piece was chosen', () => {
  const pick = (createdAt: Date, uses: number, recent: boolean) =>
    pickAnchor({
      candidates: [item('a', 'top', createdAt)],
      usage: new Map(uses ? [['a', { uses, recent }]] : []),
      exactItemIds: [],
      siblingItemIds: [],
      now,
    })?.reason?.kind ?? null;
  assert.equal(pick(new Date('2026-10-01T00:00:00Z'), 0, false), 'new-piece');
  assert.equal(pick(old, 0, false), 'never-styled');
  assert.equal(pick(old, 3, false), 'rarely-styled');
  assert.equal(pick(old, 3, true), null);
});

const piece = (id: string, category: string, warmth: 'light' | 'mid' | 'warm' = 'mid', uses = 0) => ({
  id,
  category,
  warmth,
  uses,
});

test('swapping replaces a piece with the least worn fitting one of its category', () => {
  const outfit = [piece('shirt', 'top'), piece('jeans', 'pants'), piece('sneakers', 'shoes')];
  const pool = [
    ...outfit,
    piece('chinos', 'pants', 'mid', 4),
    piece('cords', 'pants', 'mid', 1),
    piece('shorts', 'pants', 'light', 0),
    piece('coat', 'jacket', 'warm'),
  ];
  // The shorts are worn least, and nothing in the outfit is warm, so they fit.
  assert.deepEqual(adjustOutfit({ outfit, keep: [], exclude: ['jeans'], pool }), ['shirt', 'sneakers', 'shorts']);
  // Next to a kept winter coat, light shorts would clash: the cords come in.
  assert.deepEqual(
    adjustOutfit({ outfit, keep: [piece('coat', 'jacket', 'warm')], exclude: ['jeans'], pool }),
    ['shirt', 'sneakers', 'coat', 'cords'],
  );
});

test('a kept piece takes its slot, and a kept dress replaces top and bottoms', () => {
  const outfit = [piece('shirt', 'top'), piece('skirt', 'skirt'), piece('sneakers', 'shoes')];
  assert.deepEqual(adjustOutfit({ outfit, keep: [piece('jeans', 'pants')], exclude: [], pool: [] }), [
    'shirt',
    'sneakers',
    'jeans',
  ]);
  assert.deepEqual(adjustOutfit({ outfit, keep: [piece('dress', 'dress')], exclude: [], pool: [] }), ['sneakers', 'dress']);
});

test('a kept winter coat pushes out light pieces', () => {
  const outfit = [piece('tee', 'top'), piece('shorts', 'pants', 'light'), piece('sneakers', 'shoes')];
  const pool = [piece('jeans', 'pants', 'mid', 2)];
  assert.deepEqual(
    adjustOutfit({ outfit, keep: [piece('coat', 'jacket', 'warm')], exclude: [], pool }),
    ['tee', 'sneakers', 'coat', 'jeans'],
  );
  assert.equal(warmthClash([piece('coat', 'jacket', 'warm'), piece('shorts', 'pants', 'light')]), true);
});

test('replacements avoid pieces the other proposals already show', () => {
  const outfit = [piece('shirt', 'top'), piece('jeans', 'pants')];
  const pool = [piece('cords', 'pants', 'mid', 0), piece('chinos', 'pants', 'mid', 3)];
  assert.deepEqual(adjustOutfit({ outfit, keep: [], exclude: ['jeans'], pool, elsewhere: ['cords'] }), ['shirt', 'chinos']);
});

import assert from 'node:assert/strict';
import test from 'node:test';

import { adjustOutfit, buildOutfits, pickAnchor, pickProposals, warmthClash } from './look-proposals.js';

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

const builderPiece = (id: string, category: string, warmth: 'light' | 'mid' | 'warm' | null = 'mid') => ({
  id, category, warmth, createdAt: old,
});

test('built outfits keep the exact pieces, fill every core slot once and never mix seasons', () => {
  const pool = [
    builderPiece('tee', 'top', 'light'), builderPiece('knit', 'top', 'warm'), builderPiece('shirt', 'top'),
    builderPiece('shorts', 'pants', 'light'), builderPiece('jeans', 'pants'), builderPiece('skirt', 'skirt'),
    builderPiece('dress', 'dress', 'light'), builderPiece('puffer', 'jacket', 'warm'), builderPiece('denim', 'jacket'),
    builderPiece('sneakers', 'shoes'), builderPiece('boots', 'shoes', 'warm'), builderPiece('cap', 'hat'),
  ];
  let seed = 7;
  const random = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
  const outfits = buildOutfits({ pool, exactItemIds: ['jeans'], categories: [], usage: new Map(), tries: 40, random });
  assert.ok(outfits.length > 5);
  const byId = new Map(pool.map((p) => [p.id, p]));
  for (const { itemIds } of outfits) {
    const pieces = itemIds.map((id) => byId.get(id)!);
    assert.ok(itemIds.includes('jeans'));
    assert.equal(new Set(itemIds).size, itemIds.length);
    assert.equal(pieces.filter((p) => ['pants', 'skirt'].includes(p.category)).length, 1);
    assert.equal(pieces.filter((p) => p.category === 'top').length, 1);
    assert.ok(!pieces.some((p) => p.category === 'dress'));
    assert.equal(warmthClash(pieces), false);
  }
  assert.equal(new Set(outfits.map((o) => [...o.itemIds].sort().join())).size, outfits.length);
});

test('picked proposals follow the scores but skip repeats of each other and of recent looks', () => {
  const outfit = (itemIds: string[], anchor: string) => ({ itemIds, anchor: { itemId: anchor } });
  const outfits = [
    outfit(['tee', 'jeans', 'sneakers'], 'tee'),
    outfit(['tee', 'jeans', 'boots'], 'jeans'),
    outfit(['shirt', 'skirt', 'loafers'], 'shirt'),
    outfit(['knit', 'chinos', 'boots'], 'knit'),
  ];
  const picked = pickProposals({
    outfits,
    scores: [0.9, 0.8, 0.7, 0.1],
    count: 2,
    exactItemIds: [],
    avoid: [['shirt', 'skirt', 'heels']],
  });
  // The second outfit only swaps shoes; the third repeats a recent look.
  assert.deepEqual(picked, [outfits[0], outfits[3]]);
  // With nothing else left, a similar outfit still fills the batch.
  assert.equal(pickProposals({ outfits: outfits.slice(0, 2), scores: [1, 0], count: 2, exactItemIds: [], avoid: [] }).length, 2);
});

import assert from 'node:assert/strict';
import test from 'node:test';

import { pickAnchor } from './look-proposals.js';

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

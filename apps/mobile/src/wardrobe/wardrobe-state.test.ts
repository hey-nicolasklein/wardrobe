import assert from 'node:assert/strict';
import test from 'node:test';

import type { WardrobeItem } from '@form/contracts';

import { mergePendingEdit, selectWardrobeItems } from './wardrobe-state';
import type { PendingWardrobeEdit } from './wardrobe-types';

const item = (id: string, name: string, category: WardrobeItem['metadata']['category'], colors: string[], updatedAt: string): WardrobeItem => ({
  id: `wardrobe-item-${id}`,
  sourcePhotoId: `source-photo-${id}`,
  state: 'owning',
  status: 'ready',
  metadata: { name, category, colors, notes: null },
  currentShelfImageVersionId: null,
  recordVersion: 1,
  createdAt: updatedAt,
  updatedAt,
});

test('filters across metadata and applies deterministic sorting', () => {
  const items = [
    item('000000000001', 'Blue Oxford', 'top', ['Navy'], '2026-08-01T00:00:00.000Z'),
    item('000000000002', 'Canvas Tote', 'bag', ['Blue'], '2026-08-02T00:00:00.000Z'),
  ];

  assert.deepEqual(
    selectWardrobeItems(items, { search: 'blue', category: 'bag', color: 'blue', sort: 'name' }).map(({ id }) => id),
    ['wardrobe-item-000000000002'],
  );
  assert.equal(selectWardrobeItems(items, { search: '', category: null, color: null, sort: 'recent' })[0]?.metadata.name, 'Canvas Tote');
});

test('coalesces offline edits under the first record version and idempotency key', () => {
  const first: PendingWardrobeEdit = {
    accountId: 'account-000000000001',
    wardrobeItemId: 'wardrobe-item-000000000001',
    idempotencyKey: 'edit-0000000000000001',
    expectedRecordVersion: 3,
    patch: { state: 'wanting' },
    createdAt: '2026-08-04T00:00:00.000Z',
    attemptedAt: null,
    error: null,
  };
  const merged = mergePendingEdit(first, {
    ...first,
    idempotencyKey: 'edit-0000000000000002',
    patch: { metadata: { name: 'Coat', category: 'jacket', colors: ['Black'], notes: null } },
  });

  assert.equal(merged.idempotencyKey, first.idempotencyKey);
  assert.equal(merged.expectedRecordVersion, 3);
  assert.deepEqual(merged.patch, {
    state: 'wanting',
    metadata: { name: 'Coat', category: 'jacket', colors: ['Black'], notes: null },
  });
});

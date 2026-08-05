import assert from 'node:assert/strict';
import test from 'node:test';

import type { DetectionProposal } from '@form/contracts';

import { draftsFromDetections, validateDraft } from './add-flow-state';

const detection = (category: DetectionProposal['category']): DetectionProposal => ({
  id: `proposal-${category}-000000000000`,
  sourcePhotoId: 'source-photo-000000000000',
  name: category === 'unsupported' ? 'Watch' : 'Overshirt',
  category,
  colors: ['navy'],
  boundingBox: { x: 100, y: 100, width: 500, height: 700 },
  createdAt: '2026-08-05T08:00:00.000Z',
});

test('supported proposals begin selected while unsupported wearables are called out', () => {
  const [supported, unsupported] = draftsFromDetections([
    detection('jacket'),
    detection('unsupported'),
  ]);
  assert.equal(supported?.selected, true);
  assert.equal(supported?.metadata?.category, 'jacket');
  assert.equal(unsupported?.selected, false);
  assert.equal(unsupported?.metadata, null);
});

test('a selected proposal requires complete reviewed metadata', () => {
  const [draft] = draftsFromDetections([detection('top')]);
  assert.ok(draft);
  assert.equal(validateDraft(draft), null);
  assert.equal(
    validateDraft({ ...draft, metadata: { ...draft.metadata!, colors: [] } }),
    'Enter at least one color.',
  );
});

import assert from 'node:assert/strict';
import test from 'node:test';

import { selectWardrobeHeroMedia } from './wardrobe-hero-media.js';

test('renders the newest generated image while it awaits review', () => {
  assert.deepEqual(
    selectWardrobeHeroMedia({
      currentShelfImageVersionId: null,
      shelfImageVersions: [],
      generationAttempts: [
        { state: 'needs-review', transparentAssetId: 'generated-newest' },
        { state: 'needs-review', transparentAssetId: 'generated-older' },
      ],
    }),
    { assetId: 'generated-newest', pendingReview: true },
  );
});

test('kept current image takes precedence over a pending generation', () => {
  assert.deepEqual(
    selectWardrobeHeroMedia({
      currentShelfImageVersionId: 'current-version',
      shelfImageVersions: [
        { id: 'current-version', transparentAssetId: 'current-asset' },
      ],
      generationAttempts: [
        { state: 'needs-review', transparentAssetId: 'pending-asset' },
      ],
    }),
    { assetId: 'current-asset', pendingReview: false },
  );
});

test('does not render incomplete or failed generation attempts', () => {
  assert.equal(
    selectWardrobeHeroMedia({
      currentShelfImageVersionId: null,
      shelfImageVersions: [],
      generationAttempts: [
        { state: 'queued', transparentAssetId: null },
        { state: 'failed', transparentAssetId: null },
      ],
    }),
    null,
  );
});

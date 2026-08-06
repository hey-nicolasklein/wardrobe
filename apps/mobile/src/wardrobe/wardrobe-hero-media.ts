import type { GenerationAttempt, ShelfImageVersion } from '@form/contracts';

type WardrobeHeroMediaInput = {
  currentShelfImageVersionId: string | null;
  shelfImageVersions: Pick<ShelfImageVersion, 'id' | 'transparentAssetId'>[];
  generationAttempts: Pick<GenerationAttempt, 'state' | 'transparentAssetId'>[];
};

export type WardrobeHeroMedia = {
  assetId: string;
  pendingReview: boolean;
};

export function selectWardrobeHeroMedia({
  currentShelfImageVersionId,
  shelfImageVersions,
  generationAttempts,
}: WardrobeHeroMediaInput): WardrobeHeroMedia | null {
  const currentAssetId = shelfImageVersions.find(
    ({ id }) => id === currentShelfImageVersionId,
  )?.transparentAssetId;
  if (currentAssetId) return { assetId: currentAssetId, pendingReview: false };

  const pendingAssetId = generationAttempts.find(
    ({ state, transparentAssetId }) => state === 'needs-review' && transparentAssetId !== null,
  )?.transparentAssetId;
  return pendingAssetId ? { assetId: pendingAssetId, pendingReview: true } : null;
}

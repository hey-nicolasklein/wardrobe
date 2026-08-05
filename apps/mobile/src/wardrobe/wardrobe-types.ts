import type {
  UpdateWardrobeItemRequest,
  WardrobeItem,
  WardrobeItemDetailResponse,
} from '@form/contracts';

export type EditableWardrobePatch = Pick<
  UpdateWardrobeItemRequest,
  'metadata' | 'state' | 'currentShelfImageVersionId'
>;

export type PendingWardrobeEdit = {
  accountId: string;
  wardrobeItemId: string;
  idempotencyKey: string;
  expectedRecordVersion: number;
  patch: EditableWardrobePatch;
  createdAt: string;
  attemptedAt: string | null;
  error: string | null;
};

export type CachedWardrobe = {
  lists: Partial<Record<WardrobeItem['state'], WardrobeItem[]>>;
  details: Record<string, WardrobeItemDetailResponse>;
  mediaUrls: Record<string, string>;
  updatedAt: string | null;
};

export type WardrobeSort = 'recent' | 'name' | 'category';

export const emptyWardrobeCache: CachedWardrobe = {
  lists: {},
  details: {},
  mediaUrls: {},
  updatedAt: null,
};

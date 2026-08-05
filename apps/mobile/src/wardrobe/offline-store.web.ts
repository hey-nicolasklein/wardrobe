import { mergePendingEdit } from './wardrobe-state';
import {
  emptyWardrobeCache,
  type CachedWardrobe,
  type PendingWardrobeEdit,
} from './wardrobe-types';

const cacheKey = (accountId: string) => `form:wardrobe-cache:${accountId}`;
const outboxKey = (accountId: string) => `form:wardrobe-outbox:${accountId}`;

function readJson<T>(key: string, fallback: T): T {
  const value = globalThis.localStorage?.getItem(key);
  if (!value) return fallback;
  try {
    return JSON.parse(value) as T;
  } catch {
    return fallback;
  }
}

export async function readWardrobeCache(accountId: string): Promise<CachedWardrobe> {
  return readJson(cacheKey(accountId), emptyWardrobeCache);
}

export async function writeWardrobeCache(accountId: string, cache: CachedWardrobe): Promise<void> {
  globalThis.localStorage?.setItem(cacheKey(accountId), JSON.stringify(cache));
}

export async function readPendingEdits(accountId: string): Promise<PendingWardrobeEdit[]> {
  return readJson(outboxKey(accountId), []);
}

export async function putPendingEdit(edit: PendingWardrobeEdit): Promise<PendingWardrobeEdit> {
  const edits = await readPendingEdits(edit.accountId);
  const existing = edits.find(({ wardrobeItemId }) => wardrobeItemId === edit.wardrobeItemId);
  if (existing?.attemptedAt) {
    throw new Error('This item already has an edit awaiting confirmation from the service.');
  }
  const merged = mergePendingEdit(existing, edit);
  globalThis.localStorage?.setItem(
    outboxKey(edit.accountId),
    JSON.stringify([...edits.filter(({ wardrobeItemId }) => wardrobeItemId !== edit.wardrobeItemId), merged]),
  );
  return merged;
}

export async function setPendingEditAttempted(
  edit: PendingWardrobeEdit,
): Promise<PendingWardrobeEdit> {
  if (edit.attemptedAt) return edit;
  const attempted = { ...edit, attemptedAt: new Date().toISOString() };
  const edits = await readPendingEdits(edit.accountId);
  globalThis.localStorage?.setItem(
    outboxKey(edit.accountId),
    JSON.stringify(edits.map((candidate) => candidate.wardrobeItemId === edit.wardrobeItemId ? attempted : candidate)),
  );
  return attempted;
}

export async function deletePendingEdit(accountId: string, wardrobeItemId: string): Promise<void> {
  const edits = await readPendingEdits(accountId);
  globalThis.localStorage?.setItem(
    outboxKey(accountId),
    JSON.stringify(edits.filter((edit) => edit.wardrobeItemId !== wardrobeItemId)),
  );
}

export async function setPendingEditError(
  edit: PendingWardrobeEdit,
  error: string,
): Promise<PendingWardrobeEdit> {
  const failed = { ...edit, error };
  const edits = await readPendingEdits(edit.accountId);
  globalThis.localStorage?.setItem(
    outboxKey(edit.accountId),
    JSON.stringify(edits.map((candidate) => candidate.wardrobeItemId === edit.wardrobeItemId ? failed : candidate)),
  );
  return failed;
}

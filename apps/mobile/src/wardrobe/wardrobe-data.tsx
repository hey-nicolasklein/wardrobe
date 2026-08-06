import NetInfo from '@react-native-community/netinfo';
import type {
  WardrobeItem,
  WardrobeItemDetailResponse,
} from '@form/contracts';
import {
  createContext,
  type PropsWithChildren,
  use,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from 'react';

import { ApiClientError, apiClient } from '@/lib/api-client';

import {
  deletePendingEdit,
  putPendingEdit,
  readPendingEdits,
  readWardrobeCache,
  setPendingEditAttempted,
  setPendingEditError,
  writeWardrobeCache,
} from './offline-store';
import { applyWardrobeItem, mergeWardrobePatch } from './wardrobe-state';
import {
  emptyWardrobeCache,
  type CachedWardrobe,
  type EditableWardrobePatch,
  type PendingWardrobeEdit,
} from './wardrobe-types';

type WardrobeDataContextValue = {
  cache: CachedWardrobe;
  pendingEdits: PendingWardrobeEdit[];
  isOnline: boolean;
  isLoading: boolean;
  isRefreshing: boolean;
  error: string | null;
  refresh: (state?: WardrobeItem['state']) => Promise<void>;
  loadDetail: (wardrobeItemId: string) => Promise<WardrobeItemDetailResponse | null>;
  updateItem: (wardrobeItemId: string, patch: EditableWardrobePatch) => Promise<void>;
  generateShelfImage: (wardrobeItemId: string) => Promise<void>;
  keepShelfImage: (wardrobeItemId: string, generationAttemptId: string) => Promise<void>;
  rejectShelfImage: (wardrobeItemId: string, generationAttemptId: string) => Promise<void>;
  permanentlyDeleteItem: (wardrobeItemId: string) => Promise<void>;
  mediaUrl: (assetId: string) => Promise<string | null>;
};

const WardrobeDataContext = createContext<WardrobeDataContextValue | null>(null);
const states: WardrobeItem['state'][] = ['owning', 'wanting', 'archived'];

function idempotencyKey(): string {
  return `mobile-edit-${Date.now()}-${Math.random().toString(36).slice(2)}-${Math.random().toString(36).slice(2)}`;
}

function itemFromCache(cache: CachedWardrobe, wardrobeItemId: string): WardrobeItem | null {
  const detail = cache.details[wardrobeItemId];
  if (detail) return detail.wardrobeItem;
  for (const list of Object.values(cache.lists)) {
    const item = list?.find(({ id }) => id === wardrobeItemId);
    if (item) return item;
  }
  return null;
}

function overlayPendingItem(
  item: WardrobeItem,
  pendingEdits: PendingWardrobeEdit[],
): WardrobeItem {
  const pending = pendingEdits.find(
    (edit) => edit.wardrobeItemId === item.id && edit.error === null,
  );
  return pending ? mergeWardrobePatch(item, pending.patch) : item;
}

export function WardrobeDataProvider({
  accountId,
  children,
}: PropsWithChildren<{ accountId: string }>) {
  const [cache, setCache] = useState<CachedWardrobe>(emptyWardrobeCache);
  const [pendingEdits, setPendingEdits] = useState<PendingWardrobeEdit[]>([]);
  const [isOnline, setIsOnline] = useState(true);
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const cacheRef = useRef(cache);
  const pendingRef = useRef(pendingEdits);
  const onlineRef = useRef(isOnline);
  const flushPromiseRef = useRef<Promise<void> | null>(null);
  const accountRef = useRef(accountId);

  useEffect(() => {
    cacheRef.current = cache;
  }, [cache]);
  useEffect(() => {
    pendingRef.current = pendingEdits;
  }, [pendingEdits]);
  useEffect(() => {
    onlineRef.current = isOnline;
  }, [isOnline]);

  const commitCache = useCallback(
    (next: CachedWardrobe | ((current: CachedWardrobe) => CachedWardrobe)) => {
      const value = typeof next === 'function' ? next(cacheRef.current) : next;
      cacheRef.current = value;
      setCache(value);
      void writeWardrobeCache(accountRef.current, value);
      return value;
    },
    [],
  );

  const replacePending = useCallback((next: PendingWardrobeEdit[]) => {
    pendingRef.current = next;
    setPendingEdits(next);
  }, []);

  const loadDetail = useCallback(
    async (wardrobeItemId: string): Promise<WardrobeItemDetailResponse | null> => {
      if (!onlineRef.current) return cacheRef.current.details[wardrobeItemId] ?? null;
      try {
        const serverDetail = await apiClient.getWardrobeItem(wardrobeItemId);
        const detail = {
          ...serverDetail,
          wardrobeItem: overlayPendingItem(serverDetail.wardrobeItem, pendingRef.current),
        };
        commitCache((current) => ({
          ...current,
          details: { ...current.details, [wardrobeItemId]: detail },
          updatedAt: new Date().toISOString(),
        }));
        return detail;
      } catch (caught) {
        const cached = cacheRef.current.details[wardrobeItemId] ?? null;
        if (!cached) setError(caught instanceof Error ? caught.message : 'Unable to load this item.');
        return cached;
      }
    },
    [commitCache],
  );

  const refresh = useCallback(
    async (state?: WardrobeItem['state']) => {
      if (!onlineRef.current) return;
      setIsRefreshing(true);
      setError(null);
      try {
        const requestedStates = state ? [state] : states;
        const lists = await Promise.all(
          requestedStates.map(async (requestedState) => [
            requestedState,
            (await apiClient.listWardrobeItems(requestedState)).map((item) =>
              overlayPendingItem(item, pendingRef.current),
            ),
          ] as const),
        );
        commitCache((current) => {
          const nextLists = { ...current.lists };
          if (!state) {
            const allItems = lists.flatMap(([, items]) => items);
            for (const itemState of states) {
              nextLists[itemState] = allItems.filter((item) => item.state === itemState);
            }
          } else {
            const stateItems = lists[0]?.[1] ?? [];
            nextLists[state] = stateItems.filter((item) => item.state === state);
            for (const item of stateItems.filter((candidate) => candidate.state !== state)) {
              const target = nextLists[item.state];
              if (target) {
                nextLists[item.state] = [
                  item,
                  ...target.filter((candidate) => candidate.id !== item.id),
                ];
              }
            }
          }
          return {
            ...current,
            lists: nextLists,
            updatedAt: new Date().toISOString(),
          };
        });
        const ids = lists.flatMap(([, items]) => items.map(({ id }) => id));
        await Promise.allSettled(ids.map((id) => loadDetail(id)));
      } catch (caught) {
        setError(caught instanceof Error ? caught.message : 'Unable to refresh your wardrobe.');
      } finally {
        setIsRefreshing(false);
      }
    },
    [commitCache, loadDetail],
  );

  const flushOutbox = useCallback(async () => {
    if (flushPromiseRef.current) return flushPromiseRef.current;
    const flush = (async () => {
      if (!onlineRef.current) return;
      for (const edit of pendingRef.current) {
        if (!onlineRef.current) break;
        let attempted = edit;
        try {
          attempted = await setPendingEditAttempted(edit);
          replacePending(
            pendingRef.current.map((candidate) =>
              candidate.wardrobeItemId === edit.wardrobeItemId ? attempted : candidate,
            ),
          );
          const item = await apiClient.updateWardrobeItem(attempted.wardrobeItemId, {
            ...attempted.patch,
            expectedRecordVersion: attempted.expectedRecordVersion,
            idempotencyKey: attempted.idempotencyKey,
          });
          await deletePendingEdit(attempted.accountId, attempted.wardrobeItemId);
          replacePending(
            pendingRef.current.filter(({ wardrobeItemId }) => wardrobeItemId !== attempted.wardrobeItemId),
          );
          commitCache((current) => applyWardrobeItem(current, item));
        } catch (caught) {
          if (caught instanceof ApiClientError && caught.status === 409) {
            const failed = await setPendingEditError(attempted, caught.message);
            replacePending(
              pendingRef.current.map((candidate) =>
                candidate.wardrobeItemId === edit.wardrobeItemId ? failed : candidate,
              ),
            );
            continue;
          }
          setError(caught instanceof Error ? caught.message : 'A pending edit could not sync.');
          break;
        }
      }
    })().finally(() => {
      flushPromiseRef.current = null;
    });
    flushPromiseRef.current = flush;
    return flush;
  }, [commitCache, replacePending]);

  const updateItem = useCallback(
    async (wardrobeItemId: string, patch: EditableWardrobePatch) => {
      const item = itemFromCache(cacheRef.current, wardrobeItemId);
      if (!item) throw new Error('This item is not available in the offline cache.');
      const edit = await putPendingEdit({
        accountId: accountRef.current,
        wardrobeItemId,
        expectedRecordVersion: item.recordVersion,
        idempotencyKey: idempotencyKey(),
        patch,
        createdAt: new Date().toISOString(),
        attemptedAt: null,
        error: null,
      });
      replacePending([
        ...pendingRef.current.filter((candidate) => candidate.wardrobeItemId !== wardrobeItemId),
        edit,
      ]);
      commitCache((current) => applyWardrobeItem(current, mergeWardrobePatch(item, patch)));
      if (onlineRef.current) await flushOutbox();
    },
    [commitCache, flushOutbox, replacePending],
  );

  const mediaUrl = useCallback(
    async (assetId: string): Promise<string | null> => {
      const cached = cacheRef.current.mediaUrls[assetId] ?? null;
      if (!onlineRef.current) return cached;
      try {
        const url = await apiClient.createDownloadUrl(assetId);
        commitCache((current) => ({
          ...current,
          mediaUrls: { ...current.mediaUrls, [assetId]: url },
        }));
        return url;
      } catch {
        return cached;
      }
    },
    [commitCache],
  );

  const requireOnlineItem = useCallback((wardrobeItemId: string): WardrobeItem => {
    if (!onlineRef.current) throw new Error('This action requires a connection.');
    const item = itemFromCache(cacheRef.current, wardrobeItemId);
    if (!item) throw new Error('Refresh this item and try again.');
    return item;
  }, []);

  const generateShelfImage = useCallback(async (wardrobeItemId: string) => {
    requireOnlineItem(wardrobeItemId);
    await apiClient.enqueueGeneration(wardrobeItemId);
    await loadDetail(wardrobeItemId);
  }, [loadDetail, requireOnlineItem]);

  const keepShelfImage = useCallback(async (wardrobeItemId: string, generationAttemptId: string) => {
    const item = requireOnlineItem(wardrobeItemId);
    await apiClient.keepShelfImage(wardrobeItemId, generationAttemptId, item.recordVersion);
    await loadDetail(wardrobeItemId);
  }, [loadDetail, requireOnlineItem]);

  const rejectShelfImage = useCallback(async (wardrobeItemId: string, generationAttemptId: string) => {
    const item = requireOnlineItem(wardrobeItemId);
    await apiClient.rejectShelfImage(wardrobeItemId, generationAttemptId, item.recordVersion);
    await loadDetail(wardrobeItemId);
  }, [loadDetail, requireOnlineItem]);

  const permanentlyDeleteItem = useCallback(async (wardrobeItemId: string) => {
    const item = requireOnlineItem(wardrobeItemId);
    await apiClient.permanentlyDeleteWardrobeItem(wardrobeItemId, item.recordVersion);
    commitCache((current) => ({
      ...current,
      lists: Object.fromEntries(
        Object.entries(current.lists).map(([state, items]) => [
          state,
          items?.filter((candidate) => candidate.id !== wardrobeItemId),
        ]),
      ),
      details: Object.fromEntries(
        Object.entries(current.details).filter(([id]) => id !== wardrobeItemId),
      ),
      updatedAt: new Date().toISOString(),
    }));
  }, [commitCache, requireOnlineItem]);

  useEffect(() => {
    accountRef.current = accountId;
    let active = true;
    setIsLoading(true);
    void Promise.all([readWardrobeCache(accountId), readPendingEdits(accountId)]).then(
      ([storedCache, storedPending]) => {
        if (!active) return;
        cacheRef.current = storedCache;
        pendingRef.current = storedPending;
        setCache(storedCache);
        setPendingEdits(storedPending);
        setIsLoading(false);
        if (onlineRef.current) {
          void flushOutbox().then(() => refresh());
        }
      },
      () => {
        if (active) {
          setError('The offline wardrobe could not be opened.');
          setIsLoading(false);
        }
      },
    );
    return () => {
      active = false;
    };
  }, [accountId, flushOutbox, refresh]);

  useEffect(() =>
    NetInfo.addEventListener((network) => {
      const online = network.isConnected !== false && network.isInternetReachable !== false;
      onlineRef.current = online;
      setIsOnline(online);
      if (online && !isLoading) void flushOutbox().then(() => refresh());
    }), [flushOutbox, isLoading, refresh]);

  const value = useMemo<WardrobeDataContextValue>(
    () => ({
      cache,
      pendingEdits,
      isOnline,
      isLoading,
      isRefreshing,
      error,
      refresh,
      loadDetail,
      updateItem,
      generateShelfImage,
      keepShelfImage,
      rejectShelfImage,
      permanentlyDeleteItem,
      mediaUrl,
    }),
    [cache, error, generateShelfImage, isLoading, isOnline, isRefreshing, keepShelfImage, loadDetail, mediaUrl, pendingEdits, permanentlyDeleteItem, refresh, rejectShelfImage, updateItem],
  );

  return <WardrobeDataContext.Provider value={value}>{children}</WardrobeDataContext.Provider>;
}

export function useWardrobeData(): WardrobeDataContextValue {
  const context = use(WardrobeDataContext);
  if (!context) throw new Error('useWardrobeData must be used inside WardrobeDataProvider.');
  return context;
}

import type { ItemMetadata, WardrobeItem } from '@form/contracts';

import type {
  CachedWardrobe,
  EditableWardrobePatch,
  PendingWardrobeEdit,
  WardrobeSort,
} from './wardrobe-types';

export function mergeWardrobePatch(
  item: WardrobeItem,
  patch: EditableWardrobePatch,
): WardrobeItem {
  return {
    ...item,
    ...(patch.metadata === undefined ? {} : { metadata: patch.metadata }),
    ...(patch.state === undefined ? {} : { state: patch.state }),
    ...(patch.currentShelfImageVersionId === undefined
      ? {}
      : { currentShelfImageVersionId: patch.currentShelfImageVersionId }),
    updatedAt: new Date().toISOString(),
  };
}

export function applyWardrobeItem(cache: CachedWardrobe, item: WardrobeItem): CachedWardrobe {
  const lists = Object.fromEntries(
    Object.entries(cache.lists).map(([state, items]) => [
      state,
      items?.filter((candidate) => candidate.id !== item.id),
    ]),
  ) as CachedWardrobe['lists'];

  if (lists[item.state]) lists[item.state] = [item, ...lists[item.state]!];
  const detail = cache.details[item.id];

  return {
    ...cache,
    lists,
    details: detail
      ? { ...cache.details, [item.id]: { ...detail, wardrobeItem: item } }
      : cache.details,
  };
}

export function mergePendingEdit(
  existing: PendingWardrobeEdit | undefined,
  next: PendingWardrobeEdit,
): PendingWardrobeEdit {
  if (!existing) return next;
  return {
    ...existing,
    patch: { ...existing.patch, ...next.patch },
    error: null,
  };
}

function matchesMetadata(
  metadata: ItemMetadata,
  search: string,
  category: string | null,
  color: string | null,
): boolean {
  const query = search.trim().toLocaleLowerCase();
  const text = [metadata.name, metadata.category, ...metadata.colors, metadata.notes ?? '']
    .join(' ')
    .toLocaleLowerCase();
  return (
    (!query || text.includes(query)) &&
    (!category || metadata.category === category) &&
    (!color || metadata.colors.some((value) => value.toLocaleLowerCase() === color.toLocaleLowerCase()))
  );
}

export function selectWardrobeItems(
  items: WardrobeItem[],
  options: { search: string; category: string | null; color: string | null; sort: WardrobeSort },
): WardrobeItem[] {
  return items
    .filter((item) => matchesMetadata(item.metadata, options.search, options.category, options.color))
    .toSorted((left, right) => {
      if (options.sort === 'name') return left.metadata.name.localeCompare(right.metadata.name);
      if (options.sort === 'category') {
        return (
          left.metadata.category.localeCompare(right.metadata.category) ||
          left.metadata.name.localeCompare(right.metadata.name)
        );
      }
      return right.updatedAt.localeCompare(left.updatedAt);
    });
}

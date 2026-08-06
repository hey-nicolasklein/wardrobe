import type { WardrobeItem } from '@form/contracts';
import { Link, type Href, useNavigation } from 'expo-router';
import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  ActivityIndicator,
  FlatList,
  Pressable,
  RefreshControl,
  ScrollView,
  Text,
  TextInput,
  useWindowDimensions,
  View,
} from 'react-native';

import { useAppColors } from '@/theme/colors';
import { selectWardrobeItems } from '@/wardrobe/wardrobe-state';
import type { WardrobeSort } from '@/wardrobe/wardrobe-types';
import { useWardrobeData } from '@/wardrobe/wardrobe-data';
import { selectWardrobeHeroMedia } from '@/wardrobe/wardrobe-hero-media';

import { WardrobeAssetImage } from './wardrobe-asset-image';

const sortLabels: Record<WardrobeSort, string> = {
  recent: 'Recent',
  name: 'Name',
  category: 'Category',
};

function FilterChip({
  label,
  selected,
  onPress,
}: {
  label: string;
  selected: boolean;
  onPress: () => void;
}) {
  const colors = useAppColors();
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityState={{ selected }}
      onPress={onPress}
      style={({ pressed }) => ({
        backgroundColor: selected ? colors.tint : colors.secondaryBackground,
        borderCurve: 'continuous',
        borderRadius: 999,
        opacity: pressed ? 0.6 : 1,
        paddingHorizontal: 12,
        paddingVertical: 7,
      })}>
      <Text style={{ color: selected ? colors.onTint : colors.label, fontSize: 14, fontWeight: '600' }}>
        {label}
      </Text>
    </Pressable>
  );
}

export function WardrobeGrid({ state }: { state: 'owning' | 'wanting' }) {
  const colors = useAppColors();
  const navigation = useNavigation();
  const { width } = useWindowDimensions();
  const { cache, pendingEdits, isLoading, isOnline, isRefreshing, error, refresh } = useWardrobeData();
  const [search, setSearch] = useState('');
  const [category, setCategory] = useState<string | null>(null);
  const [color, setColor] = useState<string | null>(null);
  const [sort, setSort] = useState<WardrobeSort>('recent');
  const items = cache.lists[state] ?? [];
  const columns = width >= 900 ? 5 : width >= 640 ? 4 : width >= 430 ? 3 : 2;
  const categories = useMemo(
    () => [...new Set(items.map((item) => item.metadata.category))].toSorted(),
    [items],
  );
  const colorsInList = useMemo(
    () => [...new Set(items.flatMap((item) => item.metadata.colors))].toSorted(),
    [items],
  );
  const visibleItems = useMemo(
    () => selectWardrobeItems(items, { search, category, color, sort }),
    [category, color, items, search, sort],
  );
  const pendingIds = useMemo(
    () => new Set(pendingEdits.map(({ wardrobeItemId }) => wardrobeItemId)),
    [pendingEdits],
  );

  useEffect(() => {
    if (process.env.EXPO_OS !== 'ios') return;
    navigation.setOptions({
      headerSearchBarOptions: {
        placeholder: `Search ${state}`,
        hideWhenScrolling: true,
        onChangeText: (event: { nativeEvent: { text: string } }) => setSearch(event.nativeEvent.text),
        onCancelButtonPress: () => setSearch(''),
      },
    });
  }, [navigation, state]);

  useEffect(() => {
    void refresh(state);
  }, [refresh, state]);

  const renderItem = useCallback(
    ({ item }: { item: WardrobeItem }) => {
      const detail = cache.details[item.id];
      const heroMedia = detail ? selectWardrobeHeroMedia({
        currentShelfImageVersionId: detail.wardrobeItem.currentShelfImageVersionId,
        shelfImageVersions: detail.shelfImageVersions,
        generationAttempts: detail.generationAttempts,
      }) : null;
      const href = `/(wardrobe)/(${state})/${item.id}` as Href;
      return (
        <View style={{ flex: 1 / columns, padding: 5 }}>
          <Link href={href} asChild>
            <Pressable
              accessibilityLabel={`${item.metadata.name}, ${item.metadata.category}`}
              style={({ pressed }) => ({ gap: 7, opacity: pressed ? 0.65 : 1 })}>
              <WardrobeAssetImage
                assetId={heroMedia?.assetId ?? null}
                fallback={item.metadata.name}
                style={{ aspectRatio: 1, borderRadius: 16, width: '100%' }}
              />
              <View style={{ gap: 2, paddingHorizontal: 2, paddingBottom: 8 }}>
                <View style={{ alignItems: 'center', flexDirection: 'row', gap: 5 }}>
                  <Text numberOfLines={1} style={{ color: colors.label, flex: 1, fontSize: 15, fontWeight: '600' }}>
                    {item.metadata.name}
                  </Text>
                  {pendingIds.has(item.id) ? (
                    <View
                      accessibilityLabel="Edit pending sync"
                      style={{ backgroundColor: colors.tint, borderRadius: 999, height: 7, width: 7 }}
                    />
                  ) : null}
                </View>
                <Text numberOfLines={1} style={{ color: colors.secondaryLabel, fontSize: 13 }}>
                  {item.metadata.category} · {item.metadata.colors.join(', ')}
                </Text>
              </View>
            </Pressable>
          </Link>
        </View>
      );
    },
    [cache.details, colors.label, colors.secondaryLabel, colors.tint, columns, pendingIds, state],
  );

  const cycleSort = () => setSort((current) => current === 'recent' ? 'name' : current === 'name' ? 'category' : 'recent');
  const noResults = items.length > 0 && visibleItems.length === 0;

  return (
    <FlatList
      key={columns}
      contentInsetAdjustmentBehavior="automatic"
      contentContainerStyle={{ flexGrow: 1, paddingHorizontal: 7, paddingBottom: 24 }}
      data={visibleItems}
      keyExtractor={({ id }) => id}
      numColumns={columns}
      refreshControl={<RefreshControl refreshing={isRefreshing} onRefresh={() => void refresh(state)} />}
      renderItem={renderItem}
      ListHeaderComponent={
        <View style={{ gap: 10, paddingHorizontal: 5, paddingBottom: 8 }}>
          {!isOnline ? (
            <Text selectable style={{ color: colors.secondaryLabel, fontSize: 14 }}>
              Offline · showing saved wardrobe. Lightweight edits will sync later.
            </Text>
          ) : null}
          {error ? <Text selectable style={{ color: colors.error, fontSize: 14 }}>{error}</Text> : null}
          {process.env.EXPO_OS !== 'ios' ? (
            <TextInput
              accessibilityLabel={`Search ${state}`}
              onChangeText={setSearch}
              placeholder={`Search ${state}`}
              placeholderTextColor={colors.secondaryLabel}
              style={{
                backgroundColor: colors.secondaryBackground,
                borderCurve: 'continuous',
                borderRadius: 12,
                color: colors.label,
                fontSize: 16,
                paddingHorizontal: 12,
                paddingVertical: 10,
              }}
              value={search}
            />
          ) : null}
          <ScrollView horizontal contentContainerStyle={{ gap: 7 }} showsHorizontalScrollIndicator={false}>
            <FilterChip label={`Sort: ${sortLabels[sort]}`} selected={sort !== 'recent'} onPress={cycleSort} />
            {categories.map((value) => (
              <FilterChip key={value} label={value} selected={category === value} onPress={() => setCategory(category === value ? null : value)} />
            ))}
            {colorsInList.map((value) => (
              <FilterChip key={value} label={value} selected={color === value} onPress={() => setColor(color === value ? null : value)} />
            ))}
          </ScrollView>
        </View>
      }
      ListEmptyComponent={
        <View style={{ alignItems: 'center', flex: 1, gap: 9, justifyContent: 'center', padding: 28 }}>
          {isLoading ? (
            <ActivityIndicator accessibilityLabel="Loading wardrobe" color={colors.tint} size="large" />
          ) : (
            <>
              <Text selectable style={{ color: colors.label, fontSize: 21, fontWeight: '700', textAlign: 'center' }}>
                {noResults ? 'No matches' : `Nothing in ${state} yet`}
              </Text>
              <Text selectable style={{ color: colors.secondaryLabel, maxWidth: 340, textAlign: 'center' }}>
                {noResults ? 'Try clearing a filter or using another search.' : 'Use Add to create your first durable wardrobe item.'}
              </Text>
            </>
          )}
        </View>
      }
    />
  );
}

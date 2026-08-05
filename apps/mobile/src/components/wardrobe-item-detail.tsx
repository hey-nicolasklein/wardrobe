import type { ItemMetadata, SupportedCategory, WardrobeItemDetailResponse } from '@form/contracts';
import { Link, type Href, Stack } from 'expo-router';
import { useEffect, useMemo, useState } from 'react';
import { ActivityIndicator, Pressable, ScrollView, Text, TextInput, View } from 'react-native';

import { useAppColors } from '@/theme/colors';
import { useWardrobeData } from '@/wardrobe/wardrobe-data';
import { selectWardrobeHeroMedia } from '@/wardrobe/wardrobe-hero-media';

import { WardrobeAssetImage } from './wardrobe-asset-image';

const categories: SupportedCategory[] = [
  'top',
  'jacket',
  'pants',
  'skirt',
  'dress',
  'shoes',
  'bag',
  'hat',
  'scarf',
];

function ActionButton({
  title,
  selected = false,
  disabled = false,
  onPress,
}: {
  title: string;
  selected?: boolean;
  disabled?: boolean;
  onPress: () => void;
}) {
  const colors = useAppColors();
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityState={{ selected, disabled }}
      disabled={disabled}
      onPress={onPress}
      style={({ pressed }) => ({
        backgroundColor: selected ? colors.tint : colors.secondaryBackground,
        borderCurve: 'continuous',
        borderRadius: 12,
        opacity: disabled ? 0.4 : pressed ? 0.6 : 1,
        paddingHorizontal: 13,
        paddingVertical: 10,
      })}>
      <Text style={{ color: selected ? colors.onTint : colors.label, fontSize: 15, fontWeight: '600' }}>
        {title}
      </Text>
    </Pressable>
  );
}

function MediaLink({
  assetId,
  fallback,
  title,
  href,
  compact = false,
}: {
  assetId: string;
  fallback: string;
  title: string;
  href: Href;
  compact?: boolean;
}) {
  const colors = useAppColors();
  return (
    <Link href={href}>
      <Link.Trigger>
        <Pressable accessibilityLabel={`Open ${title} fullscreen`} style={({ pressed }) => ({ gap: 7, opacity: pressed ? 0.65 : 1 })}>
          <Link.AppleZoom>
            <WardrobeAssetImage
              assetId={assetId}
              contentFit="contain"
              fallback={fallback}
              style={{
                aspectRatio: 1,
                backgroundColor: colors.secondaryBackground,
                borderRadius: 18,
                width: compact ? 132 : '100%',
              }}
            />
          </Link.AppleZoom>
          <Text selectable style={{ color: colors.secondaryLabel, fontSize: 13 }}>
            {title}
          </Text>
        </Pressable>
      </Link.Trigger>
      <Link.Preview />
    </Link>
  );
}

export function WardrobeItemDetail({
  wardrobeItemId,
  collection,
}: {
  wardrobeItemId: string;
  collection: 'owning' | 'wanting';
}) {
  const colors = useAppColors();
  const { cache, pendingEdits, isOnline, loadDetail, updateItem } = useWardrobeData();
  const detail = cache.details[wardrobeItemId];
  const item = detail?.wardrobeItem;
  const pending = pendingEdits.find((edit) => edit.wardrobeItemId === wardrobeItemId);
  const [name, setName] = useState('');
  const [category, setCategory] = useState<SupportedCategory>('top');
  const [colorText, setColorText] = useState('');
  const [notes, setNotes] = useState('');
  const [saving, setSaving] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);

  useEffect(() => {
    void loadDetail(wardrobeItemId);
  }, [loadDetail, wardrobeItemId]);

  useEffect(() => {
    if (!item) return;
    setName(item.metadata.name);
    setCategory(item.metadata.category);
    setColorText(item.metadata.colors.join(', '));
    setNotes(item.metadata.notes ?? '');
  }, [item]);

  const mediaHref = (assetId: string, title: string) =>
    ({
      pathname: `/(wardrobe)/(${collection})/media`,
      params: { assetId, title },
    }) as Href;

  const metadata = useMemo<ItemMetadata | null>(() => {
    const parsedColors = colorText.split(',').map((value) => value.trim()).filter(Boolean);
    if (!name.trim() || parsedColors.length === 0 || parsedColors.length > 6) return null;
    return { name: name.trim(), category, colors: parsedColors, notes: notes.trim() || null };
  }, [category, colorText, name, notes]);

  if (!detail || !item) {
    return (
      <ScrollView
        contentInsetAdjustmentBehavior="automatic"
        contentContainerStyle={{ alignItems: 'center', flexGrow: 1, justifyContent: 'center', padding: 24 }}>
        <ActivityIndicator accessibilityLabel="Loading item" color={colors.tint} size="large" />
      </ScrollView>
    );
  }

  const heroMedia = selectWardrobeHeroMedia({
    currentShelfImageVersionId: item.currentShelfImageVersionId,
    shelfImageVersions: detail.shelfImageVersions,
    generationAttempts: detail.generationAttempts,
  });
  const save = async () => {
    if (!metadata) {
      setFormError('Enter a name and one to six comma-separated colors.');
      return;
    }
    setSaving(true);
    setFormError(null);
    try {
      await updateItem(wardrobeItemId, { metadata });
    } catch (caught) {
      setFormError(caught instanceof Error ? caught.message : 'The edit could not be saved.');
    } finally {
      setSaving(false);
    }
  };

  const moveTo = async (state: 'owning' | 'wanting' | 'archived') => {
    setSaving(true);
    setFormError(null);
    try {
      await updateItem(wardrobeItemId, { state });
    } catch (caught) {
      setFormError(caught instanceof Error ? caught.message : 'The item could not be moved.');
    } finally {
      setSaving(false);
    }
  };

  return (
    <ScrollView
      contentInsetAdjustmentBehavior="automatic"
      contentContainerStyle={{ gap: 24, padding: 16, paddingBottom: 42 }}
      keyboardShouldPersistTaps="handled">
      <Stack.Title>{item.metadata.name}</Stack.Title>
      <View style={{ gap: 8 }}>
        {heroMedia ? (
          <MediaLink
            assetId={heroMedia.assetId}
            fallback={item.metadata.name}
            href={mediaHref(heroMedia.assetId, item.metadata.name)}
            title={
              heroMedia.pendingReview
                ? 'Generated Shelf Image · pending review'
                : 'Current Shelf Image · AI-generated'
            }
          />
        ) : (
          <WardrobeAssetImage
            assetId={null}
            fallback={item.metadata.name}
            style={{ aspectRatio: 1, borderRadius: 18, width: '100%' }}
          />
        )}
        <View style={{ alignItems: 'center', flexDirection: 'row', gap: 8 }}>
          <Text selectable style={{ color: colors.secondaryLabel, fontSize: 14 }}>
            {isOnline ? 'Online' : 'Offline'} · {item.status.replaceAll('-', ' ')}
          </Text>
          {pending ? (
            <Text selectable style={{ color: pending.error ? colors.error : colors.tint, fontSize: 14, fontWeight: '600' }}>
              {pending.error ? 'Sync conflict' : 'Edit pending sync'}
            </Text>
          ) : null}
        </View>
        {pending?.error ? <Text selectable style={{ color: colors.error }}>{pending.error}</Text> : null}
      </View>

      <View style={{ gap: 12 }}>
        <Text selectable style={{ color: colors.label, fontSize: 20, fontWeight: '700' }}>Details</Text>
        <TextInput
          accessibilityLabel="Item name"
          onChangeText={setName}
          placeholder="Name"
          placeholderTextColor={colors.secondaryLabel}
          style={{ backgroundColor: colors.secondaryBackground, borderCurve: 'continuous', borderRadius: 12, color: colors.label, fontSize: 17, padding: 12 }}
          value={name}
        />
        <ScrollView horizontal contentContainerStyle={{ gap: 7 }} showsHorizontalScrollIndicator={false}>
          {categories.map((value) => <ActionButton key={value} onPress={() => setCategory(value)} selected={category === value} title={value} />)}
        </ScrollView>
        <TextInput
          accessibilityLabel="Item colors"
          onChangeText={setColorText}
          placeholder="Colors, separated by commas"
          placeholderTextColor={colors.secondaryLabel}
          style={{ backgroundColor: colors.secondaryBackground, borderCurve: 'continuous', borderRadius: 12, color: colors.label, fontSize: 17, padding: 12 }}
          value={colorText}
        />
        <TextInput
          accessibilityLabel="Item notes"
          multiline
          onChangeText={setNotes}
          placeholder="Notes"
          placeholderTextColor={colors.secondaryLabel}
          style={{ backgroundColor: colors.secondaryBackground, borderCurve: 'continuous', borderRadius: 12, color: colors.label, fontSize: 17, minHeight: 96, padding: 12, textAlignVertical: 'top' }}
          value={notes}
        />
        {formError ? <Text selectable style={{ color: colors.error }}>{formError}</Text> : null}
        <ActionButton disabled={saving} onPress={() => void save()} selected title={saving ? 'Saving…' : isOnline ? 'Save' : 'Save for sync'} />
      </View>

      <View style={{ gap: 12 }}>
        <Text selectable style={{ color: colors.label, fontSize: 20, fontWeight: '700' }}>Collection</Text>
        <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8 }}>
          <ActionButton disabled={saving} onPress={() => void moveTo('owning')} selected={item.state === 'owning'} title="Owning" />
          <ActionButton disabled={saving} onPress={() => void moveTo('wanting')} selected={item.state === 'wanting'} title="Wanting" />
          <ActionButton disabled={saving} onPress={() => void moveTo('archived')} selected={item.state === 'archived'} title="Archive" />
        </View>
      </View>

      <View style={{ gap: 12 }}>
        <Text selectable style={{ color: colors.label, fontSize: 20, fontWeight: '700' }}>Source Photo</Text>
        <Text selectable style={{ color: colors.secondaryLabel }}>
          Private provenance retained since {new Date(detail.sourcePhoto.createdAt).toLocaleDateString()}.
        </Text>
        <MediaLink
          assetId={detail.sourcePhoto.assetId}
          fallback="Source"
          href={mediaHref(detail.sourcePhoto.assetId, 'Source Photo')}
          title="Source Photo"
        />
      </View>

      <View style={{ gap: 12 }}>
        <Text selectable style={{ color: colors.label, fontSize: 20, fontWeight: '700' }}>Shelf Image History</Text>
        {detail.shelfImageVersions.length === 0 ? (
          <Text selectable style={{ color: colors.secondaryLabel }}>No kept Shelf Images yet.</Text>
        ) : (
          <ScrollView horizontal contentContainerStyle={{ gap: 12 }} showsHorizontalScrollIndicator={false}>
            {detail.shelfImageVersions.map((version) => (
              <MediaLink
                key={version.id}
                assetId={version.transparentAssetId}
                compact
                fallback={item.metadata.name}
                href={mediaHref(version.transparentAssetId, 'Shelf Image')}
                title={`${version.quality} · ${new Date(version.keptAt).toLocaleDateString()}`}
              />
            ))}
          </ScrollView>
        )}
        {detail.generationAttempts.map((attempt) => (
          <Text key={attempt.id} selectable style={{ color: colors.secondaryLabel, fontSize: 14 }}>
            {attempt.state.replaceAll('-', ' ')} · {attempt.model} · {attempt.quality} · {new Date(attempt.createdAt).toLocaleDateString()}
          </Text>
        ))}
      </View>
    </ScrollView>
  );
}

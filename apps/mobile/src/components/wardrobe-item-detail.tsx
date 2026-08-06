import type { GenerationAttempt, ItemMetadata, SupportedCategory } from '@form/contracts';
import { Link, type Href, Stack, useRouter } from 'expo-router';
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
  destructive = false,
  onPress,
}: {
  title: string;
  selected?: boolean;
  disabled?: boolean;
  destructive?: boolean;
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
        backgroundColor: selected ? (destructive ? colors.error : colors.tint) : colors.secondaryBackground,
        borderCurve: 'continuous',
        borderRadius: 12,
        opacity: disabled ? 0.4 : pressed ? 0.6 : 1,
        paddingHorizontal: 13,
        paddingVertical: 10,
      })}>
      <Text style={{ color: selected ? colors.onTint : destructive ? colors.error : colors.label, fontSize: 15, fontWeight: '600' }}>
        {title}
      </Text>
    </Pressable>
  );
}

function formatCost(microunits: number): string {
  return new Intl.NumberFormat(undefined, {
    style: 'currency',
    currency: 'USD',
    minimumFractionDigits: 3,
    maximumFractionDigits: 4,
  }).format(microunits / 1_000_000);
}

function AttemptProvenance({ attempt }: { attempt: GenerationAttempt }) {
  const colors = useAppColors();
  return (
    <View
      style={{
        backgroundColor: colors.secondaryBackground,
        borderCurve: 'continuous',
        borderRadius: 14,
        gap: 5,
        padding: 12,
      }}>
      <Text selectable style={{ color: colors.label, fontSize: 15, fontWeight: '600' }}>
        {attempt.state.replaceAll('-', ' ')} · {new Date(attempt.createdAt).toLocaleString()}
      </Text>
      <Text selectable style={{ color: colors.secondaryLabel, fontSize: 13 }}>
        {attempt.model} · {attempt.quality} · {attempt.size} · prompt {attempt.promptVersion}
      </Text>
      <Text selectable style={{ color: colors.secondaryLabel, fontSize: 13 }}>
        Input: {attempt.reviewedMetadata.name} · {attempt.reviewedMetadata.category} · {attempt.reviewedMetadata.colors.join(', ')}
      </Text>
      {attempt.usage ? (
        <Text selectable style={{ color: colors.secondaryLabel, fontSize: 13, fontVariant: ['tabular-nums'] }}>
          {attempt.usage.textInputTokens.toLocaleString()} text + {attempt.usage.imageInputTokens.toLocaleString()} image input tokens · {attempt.usage.outputTokens.toLocaleString()} output
        </Text>
      ) : null}
      {attempt.costBreakdown ? (
        <Text selectable style={{ color: colors.secondaryLabel, fontSize: 13, fontVariant: ['tabular-nums'] }}>
          {formatCost(attempt.costBreakdown.textInputMicrounits)} text · {formatCost(attempt.costBreakdown.imageInputMicrounits)} image input · {formatCost(attempt.costBreakdown.imageOutputMicrounits)} output · {formatCost(attempt.costBreakdown.totalMicrounits)} total · rates from {attempt.costBreakdown.pricingEffectiveDate}
        </Text>
      ) : attempt.costMicrounits !== null ? (
        <Text selectable style={{ color: colors.secondaryLabel, fontSize: 13, fontVariant: ['tabular-nums'] }}>
          {formatCost(attempt.costMicrounits)} total
        </Text>
      ) : null}
      {attempt.providerRequestId ? (
        <Text selectable style={{ color: colors.secondaryLabel, fontSize: 12 }}>
          Provider request {attempt.providerRequestId}
        </Text>
      ) : null}
      {attempt.failureCategory ? (
        <Text selectable style={{ color: colors.error, fontSize: 13 }}>
          Failed: {attempt.failureCategory.replaceAll('-', ' ')}
        </Text>
      ) : null}
    </View>
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
  const router = useRouter();
  const {
    cache,
    pendingEdits,
    isOnline,
    loadDetail,
    updateItem,
    generateShelfImage,
    keepShelfImage,
    rejectShelfImage,
    permanentlyDeleteItem,
  } = useWardrobeData();
  const detail = cache.details[wardrobeItemId];
  const item = detail?.wardrobeItem;
  const pending = pendingEdits.find((edit) => edit.wardrobeItemId === wardrobeItemId);
  const [name, setName] = useState('');
  const [category, setCategory] = useState<SupportedCategory>('top');
  const [colorText, setColorText] = useState('');
  const [notes, setNotes] = useState('');
  const [saving, setSaving] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);
  const [reviewing, setReviewing] = useState(false);
  const [deleteConfirmation, setDeleteConfirmation] = useState('');
  const [showPermanentDeletion, setShowPermanentDeletion] = useState(false);

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
  const pendingReview = detail.generationAttempts.find((attempt) => attempt.state === 'needs-review');
  const failedAttempt = detail.generationAttempts.find((attempt) => attempt.state === 'failed');
  const transientFailure = failedAttempt && ['connection', 'timeout', 'rate-limit', 'provider-server'].includes(failedAttempt.failureCategory ?? '');
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

  const runReviewAction = async (action: () => Promise<void>) => {
    setReviewing(true);
    setFormError(null);
    try {
      await action();
    } catch (caught) {
      setFormError(caught instanceof Error ? caught.message : 'The Shelf Image action failed.');
    } finally {
      setReviewing(false);
    }
  };

  const regenerate = async () => {
    if (pendingReview) await rejectShelfImage(wardrobeItemId, pendingReview.id);
    await generateShelfImage(wardrobeItemId);
  };

  const deletePermanently = async () => {
    if (deleteConfirmation !== item.metadata.name) return;
    await runReviewAction(async () => {
      await permanentlyDeleteItem(wardrobeItemId);
      router.back();
    });
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

      {pendingReview ? (
        <View style={{ gap: 12 }}>
          <Text selectable style={{ color: colors.label, fontSize: 20, fontWeight: '700' }}>Review Shelf Image</Text>
          <Text selectable style={{ color: colors.secondaryLabel }}>
            Keep makes this version current. Regenerate rejects it and creates a new paid attempt.
          </Text>
          <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8 }}>
            <ActionButton disabled={reviewing || !isOnline} onPress={() => void runReviewAction(() => keepShelfImage(wardrobeItemId, pendingReview.id))} selected title="Keep" />
            <ActionButton destructive disabled={reviewing || !isOnline} onPress={() => void runReviewAction(() => rejectShelfImage(wardrobeItemId, pendingReview.id))} title="Reject" />
            <ActionButton disabled={reviewing || !isOnline} onPress={() => void runReviewAction(regenerate)} title="Regenerate" />
          </View>
          {!isOnline ? <Text selectable style={{ color: colors.secondaryLabel }}>Reconnect to review or regenerate.</Text> : null}
          <AttemptProvenance attempt={pendingReview} />
        </View>
      ) : null}

      {failedAttempt ? (
        <View style={{ gap: 12 }}>
          <Text selectable style={{ color: colors.label, fontSize: 20, fontWeight: '700' }}>Generation Failed</Text>
          <Text selectable style={{ color: colors.secondaryLabel }}>
            {transientFailure
              ? 'The provider failure was temporary. You can safely try a new attempt.'
              : 'Review the item details before starting another paid attempt.'}
          </Text>
          {transientFailure ? <ActionButton disabled={reviewing || !isOnline} onPress={() => void runReviewAction(regenerate)} selected title="Try Again" /> : null}
          <AttemptProvenance attempt={failedAttempt} />
        </View>
      ) : null}

      {!pendingReview && !failedAttempt && item.status === 'ready' ? (
        <View style={{ gap: 12 }}>
          <Text selectable style={{ color: colors.label, fontSize: 20, fontWeight: '700' }}>Shelf Image</Text>
          <Text selectable style={{ color: colors.secondaryLabel }}>Create another version while keeping the current image visible.</Text>
          <ActionButton disabled={reviewing || !isOnline} onPress={() => void runReviewAction(regenerate)} title="Regenerate" />
        </View>
      ) : null}

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
              <View key={version.id} style={{ gap: 8 }}>
                <MediaLink
                  assetId={version.transparentAssetId}
                  compact
                  fallback={item.metadata.name}
                  href={mediaHref(version.transparentAssetId, 'Shelf Image')}
                  title={`${version.quality} · ${new Date(version.keptAt).toLocaleDateString()}`}
                />
                <ActionButton
                  disabled={reviewing || version.id === item.currentShelfImageVersionId}
                  onPress={() => void runReviewAction(() => updateItem(wardrobeItemId, { currentShelfImageVersionId: version.id }))}
                  selected={version.id === item.currentShelfImageVersionId}
                  title={version.id === item.currentShelfImageVersionId ? 'Current' : 'Restore'}
                />
              </View>
            ))}
          </ScrollView>
        )}
        <View style={{ gap: 8 }}>
          {detail.generationAttempts.map((attempt) => <AttemptProvenance attempt={attempt} key={attempt.id} />)}
        </View>
      </View>

      {item.state === 'archived' ? (
        <View style={{ borderTopColor: colors.separator, borderTopWidth: 1, gap: 12, paddingTop: 20 }}>
          <Text selectable style={{ color: colors.error, fontSize: 20, fontWeight: '700' }}>Permanent Deletion</Text>
          {!showPermanentDeletion ? (
            <ActionButton destructive onPress={() => setShowPermanentDeletion(true)} title="Delete Permanently…" />
          ) : (
            <>
              <Text selectable style={{ color: colors.secondaryLabel }}>
                This removes the item, every generated version, and unshared private media. Type “{item.metadata.name}” to confirm.
              </Text>
              <TextInput
                accessibilityLabel="Confirm permanent deletion"
                onChangeText={setDeleteConfirmation}
                placeholder={item.metadata.name}
                placeholderTextColor={colors.secondaryLabel}
                style={{ backgroundColor: colors.secondaryBackground, borderCurve: 'continuous', borderRadius: 12, color: colors.label, fontSize: 17, padding: 12 }}
                value={deleteConfirmation}
              />
              <ActionButton
                destructive
                disabled={reviewing || !isOnline || deleteConfirmation !== item.metadata.name}
                onPress={() => void deletePermanently()}
                selected
                title="Delete Permanently"
              />
            </>
          )}
        </View>
      ) : null}
    </ScrollView>
  );
}

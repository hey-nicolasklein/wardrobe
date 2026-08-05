import type { ItemMetadata, SupportedCategory } from '@form/contracts';
import { Image } from 'expo-image';
import * as ImageManipulator from 'expo-image-manipulator';
import * as ImagePicker from 'expo-image-picker';
import { router, Stack } from 'expo-router';
import { useEffect, useMemo, useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  Text,
  TextInput,
  View,
} from 'react-native';

import {
  draftsFromDetections,
  type ProposalDraft,
  supportedCategories,
  validateDraft,
} from '@/add/add-flow-state';
import { apiClient } from '@/lib/api-client';
import { useAppColors, type AppColors } from '@/theme/colors';
import { useWardrobeData } from '@/wardrobe/wardrobe-data';

type Stage = 'photo' | 'analyzing' | 'proposals' | 'metadata' | 'submitting' | 'complete';
type SelectedPhoto = { uri: string; width: number; height: number };
type SubmissionState = Record<
  string,
  { label: string; state: 'creating' | 'saved' | 'queued' | 'failed' }
>;

function ActionButton({
  children,
  colors,
  disabled = false,
  onPress,
  secondary = false,
}: {
  children: string;
  colors: AppColors;
  disabled?: boolean;
  onPress: () => void;
  secondary?: boolean;
}) {
  return (
    <Pressable
      accessibilityRole="button"
      disabled={disabled}
      onPress={onPress}
      style={({ pressed }) => ({
        alignItems: 'center',
        backgroundColor: secondary ? colors.secondaryBackground : colors.tint,
        borderCurve: 'continuous',
        borderRadius: 12,
        opacity: disabled ? 0.4 : pressed ? 0.65 : 1,
        paddingHorizontal: 18,
        paddingVertical: 13,
      })}>
      <Text style={{ color: secondary ? colors.label : colors.onTint, fontSize: 17, fontWeight: '600' }}>
        {children}
      </Text>
    </Pressable>
  );
}

async function normalizedPhoto(asset: ImagePicker.ImagePickerAsset): Promise<SelectedPhoto> {
  const context = ImageManipulator.ImageManipulator.manipulate(asset.uri);
  const rendered = await context.renderAsync();
  const saved = await rendered.saveAsync({
    compress: 0.92,
    format: ImageManipulator.SaveFormat.JPEG,
  });
  return { uri: saved.uri, width: saved.width, height: saved.height };
}

export default function AddItemScreen() {
  const colors = useAppColors();
  const { isOnline, refresh } = useWardrobeData();
  const [stage, setStage] = useState<Stage>('photo');
  const [photo, setPhoto] = useState<SelectedPhoto | null>(null);
  const [sourcePhotoId, setSourcePhotoId] = useState<string | null>(null);
  const [drafts, setDrafts] = useState<ProposalDraft[]>([]);
  const [focusedId, setFocusedId] = useState<string | null>(null);
  const [isPicking, setIsPicking] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [submission, setSubmission] = useState<SubmissionState>({});
  const selectedDrafts = useMemo(() => drafts.filter(({ selected }) => selected), [drafts]);

  const changeDraft = (proposalId: string, update: (draft: ProposalDraft) => ProposalDraft) => {
    setDrafts((current) =>
      current.map((draft) => (draft.proposal.id === proposalId ? update(draft) : draft)),
    );
  };

  const choosePhoto = async (camera: boolean) => {
    setError(null);
    setIsPicking(true);
    try {
      if (camera) {
        const permission = await ImagePicker.requestCameraPermissionsAsync();
        if (!permission.granted) throw new Error('Camera access is required to take a Source Photo.');
      }
      const result = camera
        ? await ImagePicker.launchCameraAsync({ mediaTypes: ['images'], quality: 1 })
        : await ImagePicker.launchImageLibraryAsync({ mediaTypes: ['images'], quality: 1 });
      if (result.canceled || !result.assets[0]) return;
      const normalized = await normalizedPhoto(result.assets[0]);
      setPhoto(normalized);
      setSourcePhotoId(null);
      setDrafts([]);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'The photo could not be prepared.');
    } finally {
      setIsPicking(false);
    }
  };

  const analyze = async () => {
    if (!photo || !isOnline) return;
    setError(null);
    setStage('analyzing');
    try {
      let durableSourcePhotoId = sourcePhotoId;
      if (!durableSourcePhotoId) {
        const uploaded = await apiClient.uploadSourcePhoto({
          uri: photo.uri,
          fileName: 'source-photo.jpg',
          contentType: 'image/jpeg',
        });
        durableSourcePhotoId = uploaded.sourcePhoto.id;
        setSourcePhotoId(durableSourcePhotoId);
      }
      await apiClient.enqueueDetection(durableSourcePhotoId);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'The photo could not be analyzed.');
      setStage('photo');
    }
  };

  useEffect(() => {
    if (stage !== 'analyzing' || !sourcePhotoId) return;
    let active = true;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const poll = async () => {
      try {
        const result = await apiClient.getDetections(sourcePhotoId);
        if (!active) return;
        if (result.attempt?.state === 'failed') {
          setError(
            result.attempt.failureCategory
              ? `Analysis failed (${result.attempt.failureCategory}). You can try again.`
              : 'Analysis failed. You can try again.',
          );
          setStage('photo');
          return;
        }
        if (result.attempt?.state === 'succeeded') {
          if (!result.detections.length) {
            setError('No wearable items were found. Try a clearer Source Photo.');
            setStage('photo');
            return;
          }
          const next = draftsFromDetections(result.detections);
          setDrafts(next);
          setFocusedId(next.find(({ selected }) => selected)?.proposal.id ?? next[0]?.proposal.id ?? null);
          setStage('proposals');
          return;
        }
        timer = setTimeout(poll, 1_500);
      } catch (caught) {
        if (!active) return;
        setError(caught instanceof Error ? caught.message : 'Analysis status is unavailable.');
        setStage('photo');
      }
    };
    void poll();
    return () => {
      active = false;
      if (timer) clearTimeout(timer);
    };
  }, [sourcePhotoId, stage]);

  const continueToMetadata = () => {
    if (!selectedDrafts.length) {
      setError('Select at least one proposal to continue.');
      return;
    }
    setError(null);
    setStage('metadata');
  };

  const submit = async () => {
    const invalid = selectedDrafts.find((draft) => validateDraft(draft));
    if (invalid) {
      setError(`${invalid.proposal.name}: ${validateDraft(invalid)}`);
      return;
    }
    setError(null);
    setStage('submitting');
    setSubmission(
      Object.fromEntries(
        selectedDrafts.map((draft) => [
          draft.proposal.id,
          { label: draft.metadata!.name, state: 'creating' as const },
        ]),
      ),
    );
    await Promise.all(
      selectedDrafts.map(async (draft) => {
        try {
          const item = await apiClient.createWardrobeItem({
            detectionProposalId: draft.proposal.id,
            state: draft.state,
            metadata: draft.metadata!,
          });
          setSubmission((current) => ({
            ...current,
            [draft.proposal.id]: { label: draft.metadata!.name, state: 'saved' },
          }));
          try {
            await apiClient.enqueueGeneration(item.id);
            setSubmission((current) => ({
              ...current,
              [draft.proposal.id]: { label: draft.metadata!.name, state: 'queued' },
            }));
          } catch {
            setSubmission((current) => ({
              ...current,
              [draft.proposal.id]: { label: draft.metadata!.name, state: 'failed' },
            }));
          }
        } catch {
          setSubmission((current) => ({
            ...current,
            [draft.proposal.id]: { label: draft.metadata!.name, state: 'failed' },
          }));
        }
      }),
    );
    await refresh();
    setStage('complete');
  };

  return (
    <>
      <ScrollView
        contentInsetAdjustmentBehavior="automatic"
        contentContainerStyle={{ gap: 20, padding: 20, paddingBottom: 44 }}
        keyboardShouldPersistTaps="handled"
        style={{ backgroundColor: colors.systemBackground }}>
        <View style={{ gap: 6 }}>
          <Text selectable style={{ color: colors.secondaryLabel, fontSize: 14, fontWeight: '600' }}>
            {stage === 'photo' || stage === 'analyzing'
              ? '1 OF 4 · SOURCE PHOTO'
              : stage === 'proposals'
                ? '2 OF 4 · SELECT ITEMS'
                : stage === 'metadata'
                  ? '3 OF 4 · REVIEW DETAILS'
                  : '4 OF 4 · CREATE & GENERATE'}
          </Text>
          <Text selectable style={{ color: colors.label, fontSize: 22, fontWeight: '700' }}>
            {stage === 'photo'
              ? 'Start with one private photo'
              : stage === 'analyzing'
                ? 'Finding wardrobe items'
                : stage === 'proposals'
                  ? 'Choose what to add'
                  : stage === 'metadata'
                    ? 'Make every item yours'
                    : stage === 'submitting'
                      ? 'Saving durable drafts'
                      : 'Your items are underway'}
          </Text>
          <Text selectable style={{ color: colors.secondaryLabel, fontSize: 16, lineHeight: 22 }}>
            {stage === 'metadata'
              ? 'GPT proposed the name, category, and colors. Review them separately; notes are always yours.'
              : stage === 'submitting' || stage === 'complete'
                ? 'Each draft is saved before its Low-quality 816 × 816 Shelf Image job is queued.'
                : 'The Source Photo stays private and remains visible as provenance for every item created from it.'}
          </Text>
        </View>

        {photo && stage !== 'metadata' && stage !== 'submitting' && stage !== 'complete' ? (
          <View
            style={{
              aspectRatio: photo.width / photo.height,
              backgroundColor: colors.secondaryBackground,
              borderCurve: 'continuous',
              borderRadius: 18,
              overflow: 'hidden',
              position: 'relative',
              width: '100%',
            }}>
            <Image contentFit="contain" source={{ uri: photo.uri }} style={{ height: '100%', width: '100%' }} />
            {stage === 'proposals'
              ? drafts.map((draft) => {
                  const box = draft.proposal.boundingBox;
                  const focused = focusedId === draft.proposal.id;
                  return (
                    <Pressable
                      accessibilityLabel={`Focus ${draft.proposal.name}`}
                      key={draft.proposal.id}
                      onPress={() => setFocusedId(draft.proposal.id)}
                      style={{
                        borderColor: focused ? colors.tint : draft.selected ? '#ffffff' : '#8e8e93',
                        borderWidth: focused ? 4 : 2,
                        left: `${box.x / 10}%`,
                        height: `${box.height / 10}%`,
                        opacity: draft.selected ? 1 : 0.55,
                        position: 'absolute',
                        top: `${box.y / 10}%`,
                        width: `${box.width / 10}%`,
                      }}
                    />
                  );
                })
              : null}
          </View>
        ) : null}

        {stage === 'photo' ? (
          <View style={{ gap: 12 }}>
            <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 10 }}>
              <View style={{ flex: 1, minWidth: 150 }}>
                <ActionButton colors={colors} disabled={isPicking} onPress={() => void choosePhoto(true)}>
                  Take Photo
                </ActionButton>
              </View>
              <View style={{ flex: 1, minWidth: 150 }}>
                <ActionButton colors={colors} disabled={isPicking} onPress={() => void choosePhoto(false)} secondary>
                  Choose from Library
                </ActionButton>
              </View>
            </View>
            {isPicking ? <ActivityIndicator accessibilityLabel="Preparing photo" color={colors.tint} /> : null}
            {photo ? (
              <ActionButton colors={colors} disabled={!isOnline || isPicking} onPress={() => void analyze()}>
                {sourcePhotoId ? 'Analyze Again' : 'Upload & Analyze'}
              </ActionButton>
            ) : null}
            {!isOnline ? (
              <Text selectable style={{ color: colors.secondaryLabel }}>
                Photo uploads and analysis require a connection. Saved wardrobe browsing still works offline.
              </Text>
            ) : null}
          </View>
        ) : null}

        {stage === 'analyzing' ? (
          <View style={{ alignItems: 'center', gap: 10, padding: 24 }}>
            <ActivityIndicator accessibilityLabel="Analyzing Source Photo" color={colors.tint} size="large" />
            <Text selectable style={{ color: colors.secondaryLabel, textAlign: 'center' }}>
              The durable analysis job keeps running if you leave this screen.
            </Text>
          </View>
        ) : null}

        {stage === 'proposals' ? (
          <View style={{ gap: 10 }}>
            {drafts.map((draft) => (
              <Pressable
                accessibilityRole="checkbox"
                accessibilityState={{ checked: draft.selected }}
                key={draft.proposal.id}
                onPress={() => {
                  setFocusedId(draft.proposal.id);
                  changeDraft(draft.proposal.id, (current) => ({ ...current, selected: !current.selected }));
                }}
                style={({ pressed }) => ({
                  backgroundColor: focusedId === draft.proposal.id ? colors.secondaryBackground : 'transparent',
                  borderColor: draft.selected ? colors.tint : colors.separator,
                  borderCurve: 'continuous',
                  borderRadius: 14,
                  borderWidth: 1,
                  gap: 4,
                  opacity: pressed ? 0.65 : 1,
                  padding: 14,
                })}>
                <Text selectable style={{ color: colors.label, fontSize: 17, fontWeight: '600' }}>
                  {draft.selected ? '✓ ' : ''}{draft.proposal.name}
                </Text>
                <Text selectable style={{ color: draft.proposal.category === 'unsupported' ? colors.error : colors.secondaryLabel }}>
                  {draft.proposal.category === 'unsupported'
                    ? 'Unsupported wearable · choose a supported category if you include it'
                    : `${draft.proposal.category} · ${draft.proposal.colors.join(', ')}`}
                </Text>
              </Pressable>
            ))}
            <ActionButton colors={colors} onPress={continueToMetadata}>
              {`Review ${selectedDrafts.length} ${selectedDrafts.length === 1 ? 'Item' : 'Items'}`}
            </ActionButton>
          </View>
        ) : null}

        {stage === 'metadata' ? (
          <View style={{ gap: 18 }}>
            {selectedDrafts.map((draft, index) => (
              <View
                key={draft.proposal.id}
                style={{
                  borderColor: colors.separator,
                  borderCurve: 'continuous',
                  borderRadius: 16,
                  borderWidth: 1,
                  gap: 12,
                  padding: 16,
                }}>
                <Text selectable style={{ color: colors.label, fontSize: 18, fontWeight: '700' }}>
                  {index + 1}. {draft.metadata?.name ?? draft.proposal.name}
                </Text>
                <TextInput
                  accessibilityLabel={`Name for ${draft.proposal.name}`}
                  onChangeText={(name) =>
                    changeDraft(draft.proposal.id, (current) => ({
                      ...current,
                      metadata: { ...(current.metadata ?? fallbackMetadata(current, 'top')), name },
                    }))
                  }
                  placeholder="Item name"
                  placeholderTextColor={colors.secondaryLabel}
                  style={{ backgroundColor: colors.secondaryBackground, borderRadius: 10, color: colors.label, fontSize: 16, padding: 12 }}
                  value={draft.metadata?.name ?? draft.proposal.name}
                />
                <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 7 }}>
                  {supportedCategories.map((category) => (
                    <Pressable
                      accessibilityRole="radio"
                      accessibilityState={{ selected: draft.metadata?.category === category }}
                      key={category}
                      onPress={() =>
                        changeDraft(draft.proposal.id, (current) => ({
                          ...current,
                          metadata: fallbackMetadata(current, category),
                        }))
                      }
                      style={({ pressed }) => ({
                        backgroundColor: draft.metadata?.category === category ? colors.tint : colors.secondaryBackground,
                        borderRadius: 999,
                        opacity: pressed ? 0.6 : 1,
                        paddingHorizontal: 11,
                        paddingVertical: 7,
                      })}>
                      <Text style={{ color: draft.metadata?.category === category ? colors.onTint : colors.label }}>
                        {category}
                      </Text>
                    </Pressable>
                  ))}
                </View>
                <TextInput
                  accessibilityLabel={`Colors for ${draft.proposal.name}`}
                  onChangeText={(value) =>
                    changeDraft(draft.proposal.id, (current) => ({
                      ...current,
                      metadata: {
                        ...(current.metadata ?? fallbackMetadata(current, 'top')),
                        colors: value.split(',').map((color) => color.trim()),
                      },
                    }))
                  }
                  placeholder="Colors, separated by commas"
                  placeholderTextColor={colors.secondaryLabel}
                  style={{ backgroundColor: colors.secondaryBackground, borderRadius: 10, color: colors.label, fontSize: 16, padding: 12 }}
                  value={draft.metadata?.colors.join(', ') ?? draft.proposal.colors.join(', ')}
                />
                <TextInput
                  accessibilityLabel={`Notes for ${draft.proposal.name}`}
                  multiline
                  onChangeText={(notes) =>
                    changeDraft(draft.proposal.id, (current) => ({
                      ...current,
                      metadata: { ...(current.metadata ?? fallbackMetadata(current, 'top')), notes: notes || null },
                    }))
                  }
                  placeholder="Notes (optional and never inferred)"
                  placeholderTextColor={colors.secondaryLabel}
                  style={{ backgroundColor: colors.secondaryBackground, borderRadius: 10, color: colors.label, fontSize: 16, minHeight: 76, padding: 12, textAlignVertical: 'top' }}
                  value={draft.metadata?.notes ?? ''}
                />
                <View style={{ flexDirection: 'row', gap: 8 }}>
                  {(['owning', 'wanting'] as const).map((state) => (
                    <Pressable
                      accessibilityRole="radio"
                      accessibilityState={{ selected: draft.state === state }}
                      key={state}
                      onPress={() => changeDraft(draft.proposal.id, (current) => ({ ...current, state }))}
                      style={({ pressed }) => ({
                        backgroundColor: draft.state === state ? colors.tint : colors.secondaryBackground,
                        borderRadius: 9,
                        flex: 1,
                        opacity: pressed ? 0.6 : 1,
                        padding: 10,
                      })}>
                      <Text style={{ color: draft.state === state ? colors.onTint : colors.label, textAlign: 'center' }}>
                        {state === 'owning' ? 'Owning' : 'Wanting'}
                      </Text>
                    </Pressable>
                  ))}
                </View>
                {validateDraft(draft) ? (
                  <Text selectable style={{ color: colors.error }}>{validateDraft(draft)}</Text>
                ) : null}
              </View>
            ))}
            <Text selectable style={{ color: colors.secondaryLabel, lineHeight: 21 }}>
              One confirmation saves {selectedDrafts.length} durable {selectedDrafts.length === 1 ? 'draft' : 'drafts'} and starts one paid Low-quality generation for each.
            </Text>
            <ActionButton colors={colors} disabled={!isOnline} onPress={() => void submit()}>
              {`Create ${selectedDrafts.length} & Generate`}
            </ActionButton>
            <ActionButton colors={colors} onPress={() => setStage('proposals')} secondary>
              Back to Selection
            </ActionButton>
          </View>
        ) : null}

        {stage === 'submitting' || stage === 'complete' ? (
          <View style={{ gap: 10 }}>
            {Object.entries(submission).map(([id, item]) => (
              <View key={id} style={{ backgroundColor: colors.secondaryBackground, borderCurve: 'continuous', borderRadius: 13, gap: 3, padding: 14 }}>
                <Text selectable style={{ color: colors.label, fontSize: 17, fontWeight: '600' }}>{item.label}</Text>
                <Text selectable style={{ color: item.state === 'failed' ? colors.error : colors.secondaryLabel }}>
                  {item.state === 'creating'
                    ? 'Saving draft…'
                    : item.state === 'saved'
                      ? 'Draft saved · queueing generation…'
                      : item.state === 'queued'
                        ? 'Draft saved · generation queued'
                        : 'Needs attention · the draft may already be saved'}
                </Text>
              </View>
            ))}
            {stage === 'submitting' ? <ActivityIndicator color={colors.tint} /> : null}
            {stage === 'complete' ? (
              <>
                <Text selectable style={{ color: colors.secondaryLabel, lineHeight: 21 }}>
                  Generation continues durably in the background. Open an item from Owning or Wanting to follow its status.
                </Text>
                <ActionButton colors={colors} onPress={() => router.back()}>Done</ActionButton>
              </>
            ) : null}
          </View>
        ) : null}

        {error ? <Text selectable style={{ color: colors.error, lineHeight: 21 }}>{error}</Text> : null}
      </ScrollView>
      {process.env.EXPO_OS === 'ios' ? (
        <Stack.Toolbar placement="right">
          <Stack.Toolbar.Button onPress={() => router.back()}>Close</Stack.Toolbar.Button>
        </Stack.Toolbar>
      ) : null}
    </>
  );
}

function fallbackMetadata(draft: ProposalDraft, category: SupportedCategory): ItemMetadata {
  return {
    name: draft.metadata?.name ?? draft.proposal.name,
    category,
    colors: draft.metadata?.colors ?? draft.proposal.colors,
    notes: draft.metadata?.notes ?? null,
  };
}

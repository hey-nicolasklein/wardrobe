import type {
  DetectionAttempt,
  DetectionProposal,
  ItemMetadata,
  ItemState,
  SupportedCategory,
} from '@form/contracts';

export const supportedCategories: SupportedCategory[] = [
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

export type ProposalDraft = {
  proposal: DetectionProposal;
  selected: boolean;
  state: Exclude<ItemState, 'archived'>;
  metadata: ItemMetadata | null;
};

export function matchingDetectionAttempt(
  expectedAttemptId: string,
  attempt: DetectionAttempt | null,
): DetectionAttempt | null {
  return attempt?.id === expectedAttemptId ? attempt : null;
}

export function draftsFromDetections(detections: DetectionProposal[]): ProposalDraft[] {
  return detections.map((proposal) => ({
    proposal,
    selected: proposal.category !== 'unsupported',
    state: 'owning',
    metadata:
      proposal.category === 'unsupported'
        ? null
        : {
            name: proposal.name,
            category: proposal.category,
            colors: proposal.colors,
            notes: null,
          },
  }));
}

export function validateDraft(draft: ProposalDraft): string | null {
  if (!draft.selected) return null;
  if (!draft.metadata) return 'Choose a supported category.';
  if (!draft.metadata.name.trim()) return 'Enter a name.';
  if (!draft.metadata.colors.length || draft.metadata.colors.some((color) => !color.trim())) {
    return 'Enter at least one color.';
  }
  return null;
}

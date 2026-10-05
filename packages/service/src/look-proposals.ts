import type { LookReason } from '@form/contracts';

// Pieces that can carry an outfit. Accessories make weak anchors.
const anchorCategories = new Set(['top', 'dress', 'pants', 'skirt', 'jacket', 'shoes']);
// Slots a dress fills, so a dress and these never anchor next to each other.
const dressSlots = new Set(['dress', 'top', 'pants', 'skirt']);
const newPieceDays = 14;

export type AnchorCandidate = { id: string; category: string; createdAt: Date };
// How often a piece appeared in finished looks, and whether among the latest.
export type PieceUsage = { uses: number; recent: boolean };

/**
 * Picks the piece a proposal is built around. Pieces worn least, and not in
 * the latest looks, are likelier; pieces of sibling proposals are skipped, so
 * every proposal of a batch starts from a different place in the closet.
 */
export function pickAnchor(input: {
  candidates: AnchorCandidate[];
  usage: Map<string, PieceUsage>;
  exactItemIds: string[];
  siblingItemIds: string[];
  now?: Date;
  random?: () => number;
}): { itemId: string; reason: LookReason | null } | null {
  const exact = input.candidates.filter((item) => input.exactItemIds.includes(item.id));
  const exactCategories = new Set(exact.map((item) => item.category));
  const clashes = (category: string) =>
    exactCategories.has(category) ||
    (category === 'dress' && [...exactCategories].some((c) => dressSlots.has(c))) ||
    (exactCategories.has('dress') && dressSlots.has(category));
  const eligible = input.candidates.filter(
    (item) =>
      anchorCategories.has(item.category) &&
      !input.exactItemIds.includes(item.id) &&
      !input.siblingItemIds.includes(item.id) &&
      !clashes(item.category),
  );
  if (!eligible.length) return null;
  const weight = (id: string) => {
    const usage = input.usage.get(id) ?? { uses: 0, recent: false };
    return (1 / (1 + usage.uses)) * (usage.recent ? 0.15 : 1);
  };
  const total = eligible.reduce((sum, item) => sum + weight(item.id), 0);
  let roll = (input.random ?? Math.random)() * total;
  const anchor = eligible.find((item) => (roll -= weight(item.id)) <= 0) ?? eligible.at(-1)!;
  const usage = input.usage.get(anchor.id) ?? { uses: 0, recent: false };
  const ageDays = ((input.now ?? new Date()).getTime() - anchor.createdAt.getTime()) / 86_400_000;
  const reason: LookReason | null =
    usage.uses === 0 && ageDays <= newPieceDays
      ? { kind: 'new-piece', itemId: anchor.id }
      : usage.uses === 0
        ? { kind: 'never-styled', itemId: anchor.id }
        : !usage.recent
          ? { kind: 'rarely-styled', itemId: anchor.id }
          : null;
  return { itemId: anchor.id, reason };
}

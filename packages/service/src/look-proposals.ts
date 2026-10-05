import type { LookReason } from '@form/contracts';

import type { Warmth } from './catalog-provider.js';

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

export type OutfitPiece = { id: string; category: string; warmth?: Warmth | null; uses?: number };

const lowerSlots = new Set(['pants', 'skirt']);

/** Whether two pieces would fill the same place in an outfit. */
function sameSlot(a: string, b: string) {
  if (a === b) return true;
  if (lowerSlots.has(a) && lowerSlots.has(b)) return true;
  if (a === 'dress') return dressSlots.has(b);
  if (b === 'dress') return dressSlots.has(a);
  return false;
}

/** A winter coat next to shorts: warm and light pieces never share an outfit. */
export function warmthClash(pieces: Array<{ warmth?: Warmth | null }>) {
  const levels = new Set(pieces.map((piece) => piece.warmth));
  return levels.has('warm') && levels.has('light');
}

/**
 * Applies the user's swipe marks to a planned outfit without asking the
 * planner again: kept pieces move in and push out whatever filled their slot,
 * excluded pieces and pieces that clash in warmth with the kept ones are
 * replaced by the least worn fitting piece of the same category from [pool].
 */
export function adjustOutfit(input: {
  outfit: OutfitPiece[];
  keep: OutfitPiece[];
  exclude: string[];
  pool: OutfitPiece[];
  // Pieces of the other open proposals; replacements avoid them when they can.
  elsewhere?: string[];
}): string[] {
  const elsewhere = new Set(input.elsewhere ?? []);
  const keptIds = new Set(input.keep.map((piece) => piece.id));
  let outfit = [...input.outfit];
  const gaps: string[] = [];
  for (const piece of outfit)
    if (input.exclude.includes(piece.id) && !keptIds.has(piece.id)) gaps.push(piece.category);
  outfit = outfit.filter((piece) => !input.exclude.includes(piece.id) || keptIds.has(piece.id));
  for (const kept of input.keep) {
    if (outfit.some((piece) => piece.id === kept.id)) continue;
    outfit = outfit.filter((piece) => !sameSlot(piece.category, kept.category));
    outfit.push(kept);
  }
  // Pieces that clash with what the user kept make way, like excluded ones.
  const anchors = outfit.filter((piece) => keptIds.has(piece.id));
  const clashing = outfit.filter(
    (piece) => !keptIds.has(piece.id) && anchors.some((kept) => warmthClash([kept, piece])),
  );
  for (const piece of clashing) gaps.push(piece.category);
  outfit = outfit.filter((piece) => !clashing.includes(piece));
  for (const category of gaps) {
    if (outfit.some((piece) => sameSlot(piece.category, category))) continue;
    const replacement = input.pool
      .filter(
        (piece) =>
          piece.category === category &&
          !input.exclude.includes(piece.id) &&
          !input.outfit.some((old) => old.id === piece.id) &&
          !warmthClash([...outfit, piece]),
      )
      .sort(
        (a, b) =>
          Number(elsewhere.has(a.id)) - Number(elsewhere.has(b.id)) ||
          (a.uses ?? 0) - (b.uses ?? 0),
      )[0];
    if (replacement) outfit.push(replacement);
  }
  return outfit.map((piece) => piece.id);
}

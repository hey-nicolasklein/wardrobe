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

/**
 * Two proposals read as the same outfit when the pieces added around the
 * user's exact pieces change in at most one slot, e.g. only the necklace.
 */
export function similarOutfit(a: string[], b: string[], exact: string[]) {
  const added = (ids: string[]) => ids.filter((id) => !exact.includes(id));
  const [left, right] = [added(a), added(b)];
  const size = Math.max(left.length, right.length);
  const shared = left.filter((id) => right.includes(id)).length;
  return size >= 2 && size - shared <= 1;
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

export type BuilderPiece = OutfitPiece & { createdAt: Date };
export type BuiltOutfit = { itemIds: string[]; anchor: { itemId: string; reason: LookReason | null } | null };

const optionalExtras = ['bag', 'hat', 'scarf', 'accessory'];

/**
 * Samples distinct outfit candidates from the closet without a model: each
 * starts from the user's exact pieces and an anchor (see pickAnchor), fills
 * the core slots, shoes and maybe a jacket and one extra, and never mixes
 * warm with light pieces. Less worn pieces are likelier at every step.
 * A ranker then picks the best of them, see pickProposals.
 */
export function buildOutfits(input: {
  pool: BuilderPiece[];
  exactItemIds: string[];
  categories: string[];
  usage: Map<string, PieceUsage>;
  tries: number;
  random?: () => number;
}): BuiltOutfit[] {
  const random = input.random ?? Math.random;
  const exact = input.pool.filter((piece) => input.exactItemIds.includes(piece.id));
  const weight = (piece: BuilderPiece) => {
    const usage = input.usage.get(piece.id) ?? { uses: 0, recent: false };
    return (1 / (1 + usage.uses)) * (usage.recent ? 0.3 : 1);
  };
  const draw = (outfit: BuilderPiece[], categories: string[]) => {
    const options = input.pool.filter(
      (piece) =>
        categories.includes(piece.category) &&
        !outfit.some((worn) => worn.id === piece.id || sameSlot(worn.category, piece.category)) &&
        !warmthClash([...outfit, piece]),
    );
    const total = options.reduce((sum, piece) => sum + weight(piece), 0);
    let roll = random() * total;
    return options.find((piece) => (roll -= weight(piece)) <= 0) ?? options.at(-1);
  };
  const seen = new Set<string>();
  const outfits: BuiltOutfit[] = [];
  for (let attempt = 0; attempt < input.tries; attempt += 1) {
    const outfit = [...exact];
    const anchor = pickAnchor({
      candidates: input.pool.filter((piece) => !warmthClash([...exact, piece])),
      usage: input.usage,
      exactItemIds: input.exactItemIds,
      siblingItemIds: [],
      random,
    });
    const anchorPiece = input.pool.find((piece) => piece.id === anchor?.itemId);
    if (anchorPiece && !outfit.some((worn) => sameSlot(worn.category, anchorPiece.category)))
      outfit.push(anchorPiece);
    const add = (...categories: string[]) => {
      const piece = draw(outfit, categories);
      if (piece) outfit.push(piece);
    };
    for (const category of input.categories)
      if (!outfit.some((worn) => worn.category === category)) add(category);
    const has = (...categories: string[]) => outfit.some((worn) => categories.includes(worn.category));
    if (!has('dress', 'top', 'pants', 'skirt') && random() < 0.15) add('dress');
    if (!has('dress')) {
      if (!has('top')) add('top');
      if (!has('pants', 'skirt')) add('pants', 'skirt');
    }
    if (!has('shoes')) add('shoes');
    const season = new Set(outfit.map((piece) => piece.warmth));
    const jacketOdds = season.has('warm') ? 0.9 : season.has('light') ? 0.15 : 0.5;
    if (!has('jacket') && random() < jacketOdds) add('jacket');
    if (!has(...optionalExtras) && random() < 0.35) add(...optionalExtras);
    const itemIds = outfit.map((piece) => piece.id);
    const key = [...itemIds].sort().join(',');
    if (seen.has(key)) continue;
    seen.add(key);
    outfits.push({ itemIds, anchor: anchor && itemIds.includes(anchor.itemId) ? anchor : null });
  }
  return outfits;
}

/**
 * The best [count] outfits by [scores] that differ from each other, from
 * [avoid] (open sibling proposals and recent looks) and, where possible, in
 * their anchor. Falls back to similar, and then repeated, outfits only when
 * nothing else is left.
 */
export function pickProposals<T extends { itemIds: string[]; anchor: { itemId: string } | null }>(input: {
  outfits: T[];
  scores: number[];
  count: number;
  exactItemIds: string[];
  avoid: string[][];
}): T[] {
  const ranked = input.outfits
    .map((outfit, index) => ({ outfit, score: input.scores[index] ?? 0 }))
    .sort((a, b) => b.score - a.score)
    .map(({ outfit }) => outfit);
  const picked: T[] = [];
  const similar = (outfit: T, others: string[][]) =>
    others.some((other) => similarOutfit(other, outfit.itemIds, input.exactItemIds));
  const passes: Array<(outfit: T) => boolean> = [
    (outfit) =>
      !similar(outfit, [...input.avoid, ...picked.map((p) => p.itemIds)]) &&
      !picked.some((p) => p.anchor && p.anchor.itemId === outfit.anchor?.itemId),
    (outfit) => !similar(outfit, [...input.avoid, ...picked.map((p) => p.itemIds)]),
    (outfit) => !similar(outfit, picked.map((p) => p.itemIds)),
    () => true,
  ];
  for (const pass of passes)
    for (const outfit of ranked) {
      if (picked.length >= input.count) return picked;
      if (!picked.includes(outfit) && pass(outfit)) picked.push(outfit);
    }
  // A closet this small repeats its best outfits; the scenes still differ.
  for (let index = 0; picked.length < input.count && ranked.length; index += 1)
    picked.push(picked[index % picked.length]!);
  return picked;
}

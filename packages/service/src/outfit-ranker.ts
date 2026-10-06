import type { ItemTraits } from './catalog-provider.js';

export type RankedPiece = {
  name: string;
  category: string;
  colors: string[];
  traits?: Omit<ItemTraits, 'brand'>;
};

export type OutfitRanking = {
  // One per outfit, higher is better.
  scores: number[];
  model: string;
  usage: { inputTokens: number; outputTokens: number };
};

/**
 * Scores outfits by how well they work. Null when no score is available, so
 * callers keep their own order.
 */
export type OutfitRanker = (input: {
  outfits: RankedPiece[][];
  occasion: string | null;
  signal?: AbortSignal;
}) => Promise<OutfitRanking | null>;

const typesafeUrl = 'https://api.typesafe.ai/v1/systemone';

const coherenceLevels = [
  'Clashing: the pieces fight in style, formality, season or color',
  'Workable but unremarkable',
  'A coherent everyday outfit',
  'A strong, intentional outfit a stylist would put together',
];
const occasionLevels = [
  'Wrong for the occasion',
  'Passable for the occasion',
  'A good fit for the occasion',
];

/**
 * Ranks outfits with TypeSafe's Jev: one Score per outfit for coherence and,
 * with an occasion, one for occasion fit, all in a single parallel request.
 * Gives up after [timeoutMs] and returns null on any failure.
 */
export function createJevOutfitRanker(apiKey: string, timeoutMs = 3_000): OutfitRanker {
  return async ({ outfits, occasion, signal }) => {
    if (!outfits.length) return null;
    const questions: Record<string, unknown> = {};
    for (const [index, outfit] of outfits.entries()) {
      questions[`coherence-${index}`] = {
        type: 'score',
        instructions: {
          outfit,
          question:
            'How well do the pieces in `outfit` work together as one outfit a person would actually wear, in color, style, formality and season?',
        },
        criteria: coherenceLevels,
      };
      if (occasion)
        questions[`occasion-${index}`] = {
          type: 'score',
          instructions: { outfit, question: 'How well does `outfit` suit `occasion`?' },
          criteria: occasionLevels,
        };
    }
    const timeout = AbortSignal.timeout(timeoutMs);
    try {
      const response = await fetch(typesafeUrl, {
        method: 'POST',
        headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
        signal: signal ? AbortSignal.any([signal, timeout]) : timeout,
        body: JSON.stringify({ model: 'jev-latest', state: { occasion }, questions }),
      });
      if (!response.ok) throw new Error(`TypeSafe answered ${response.status}`);
      const body = (await response.json()) as {
        model: string;
        answers: Record<string, { score?: number }>;
        usage: { input_tokens: number; output_tokens: number };
      };
      // Both scores on a 0..1 scale, occasion fit weighing as much as coherence.
      const scores = outfits.map((_, index) => {
        const coherence = (body.answers[`coherence-${index}`]?.score ?? 0) / (coherenceLevels.length - 1);
        if (!occasion) return coherence;
        const fit = (body.answers[`occasion-${index}`]?.score ?? 0) / (occasionLevels.length - 1);
        return (coherence + fit) / 2;
      });
      return {
        scores,
        model: body.model,
        usage: { inputTokens: body.usage.input_tokens, outputTokens: body.usage.output_tokens },
      };
    } catch (error) {
      console.error('Outfit ranking failed, keeping the closet order.', error);
      return null;
    }
  };
}

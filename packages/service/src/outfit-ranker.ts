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

// A look the user filed into a Sammlung, named after it, e.g. "Büro".
export type LikedOutfit = { collection: string; outfit: RankedPiece[] };

/**
 * Scores outfits by how well they work and, given [liked] outfits, how close
 * they come to the user's taste. Null when no score is available, so callers
 * keep their own order.
 */
export type OutfitRanker = (input: {
  outfits: RankedPiece[][];
  occasion: string | null;
  liked?: LikedOutfit[];
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
const tasteLevels = [
  'Unlike anything in liked_outfits',
  'Shares a little with liked_outfits',
  'Close to the style of liked_outfits',
];
// Three questions of about 300 tokens per outfit keep a chunk well inside
// Jev's 64k tokens per request.
const outfitsPerRequest = 20;

/**
 * Ranks outfits with TypeSafe's Jev: one Score per outfit for coherence, with
 * an occasion one for occasion fit, and with liked outfits one for taste.
 * Sends chunks of [outfitsPerRequest] outfits in parallel, gives up after
 * [timeoutMs] and returns null on any failure.
 */
export function createJevOutfitRanker(apiKey: string, timeoutMs = 3_000): OutfitRanker {
  return async ({ outfits, occasion, liked, signal }) => {
    if (!outfits.length) return null;
    const taste = liked?.length ? liked : null;
    const timeout = AbortSignal.timeout(timeoutMs);
    const scoreChunk = async (chunk: RankedPiece[][]) => {
      const questions: Record<string, unknown> = {};
      for (const [index, outfit] of chunk.entries()) {
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
        if (taste)
          questions[`taste-${index}`] = {
            type: 'score',
            instructions: {
              outfit,
              question:
                'The person filed `liked_outfits` into collections of their own, named in each `collection`. How close does `outfit` come to their taste in color, formality and style?',
            },
            criteria: tasteLevels,
          };
      }
      const response = await fetch(typesafeUrl, {
        method: 'POST',
        headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
        signal: signal ? AbortSignal.any([signal, timeout]) : timeout,
        body: JSON.stringify({
          model: 'jev-latest',
          state: { occasion, ...(taste ? { liked_outfits: taste } : {}) },
          questions,
        }),
      });
      if (!response.ok) throw new Error(`TypeSafe answered ${response.status}`);
      const body = (await response.json()) as {
        model: string;
        answers: Record<string, { score?: number }>;
        usage: { input_tokens: number; output_tokens: number };
      };
      // Every score on a 0..1 scale, weighing the same.
      const level = (key: string, levels: string[]) => (body.answers[key]?.score ?? 0) / (levels.length - 1);
      const scores = chunk.map((_, index) => {
        const parts = [level(`coherence-${index}`, coherenceLevels)];
        if (occasion) parts.push(level(`occasion-${index}`, occasionLevels));
        if (taste) parts.push(level(`taste-${index}`, tasteLevels));
        return parts.reduce((sum, part) => sum + part, 0) / parts.length;
      });
      return { scores, model: body.model, usage: body.usage };
    };
    try {
      const chunks: RankedPiece[][][] = [];
      for (let start = 0; start < outfits.length; start += outfitsPerRequest)
        chunks.push(outfits.slice(start, start + outfitsPerRequest));
      const answered = await Promise.all(chunks.map(scoreChunk));
      return {
        scores: answered.flatMap((chunk) => chunk.scores),
        model: answered[0]!.model,
        usage: {
          inputTokens: answered.reduce((sum, chunk) => sum + chunk.usage.input_tokens, 0),
          outputTokens: answered.reduce((sum, chunk) => sum + chunk.usage.output_tokens, 0),
        },
      };
    } catch (error) {
      console.error('Outfit ranking failed, keeping the closet order.', error);
      return null;
    }
  };
}

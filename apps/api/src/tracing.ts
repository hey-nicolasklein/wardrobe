import { observe, propagateAttributes, startActiveObservation, updateActiveObservation } from '@langfuse/tracing';
import type { OutfitRanker } from '@form/service';

/**
 * Runs one proposal batch inside a `look-proposal` trace, the name the worker
 * uses for planned proposals, so Langfuse groups both.
 */
export async function traceProposals<T>(accountId: string, input: unknown, run: () => Promise<T>): Promise<T> {
  return startActiveObservation('look-proposal', (span) =>
    propagateAttributes({ traceName: 'look-proposal', userId: accountId, tags: ['look-proposal'] }, async () => {
      span.update({ input });
      const result = await run();
      span.update({ output: result });
      return result;
    }),
  );
}

/** Records every Jev ranking as a Langfuse generation with model and tokens. */
export function tracedOutfitRanker(ranker: OutfitRanker): OutfitRanker {
  return observe(
    async (input: Parameters<OutfitRanker>[0]) => {
      const ranking = await ranker(input);
      if (ranking)
        updateActiveObservation(
          {
            model: ranking.model,
            usageDetails: { input: ranking.usage.inputTokens, output: ranking.usage.outputTokens },
          },
          { asType: 'generation' },
        );
      return ranking;
    },
    { name: 'outfit-ranking', asType: 'generation' },
  );
}

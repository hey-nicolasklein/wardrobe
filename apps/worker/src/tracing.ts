import { LangfuseMedia } from '@langfuse/core';
import { propagateAttributes, startActiveObservation } from '@langfuse/tracing';
import {
  calculateCostLedger,
  calculateDetectionCostLedger,
  type CatalogExecutionConfig,
  type CatalogProvider,
  type GenerationProviderResult,
  type RemoteImageJob,
  type RemoteImageJobKind,
} from '@form/service';

// One trace per job, named after the user-facing feature so the Langfuse
// dashboard can group cost by trace name or tag.
const traceNames: Record<RemoteImageJobKind, string> = {
  'detect-source-photo': 'clothing-analysis',
  'generate-shelf-image': 'shelf-item-generation',
  'generate-look': 'feed-image',
  'generate-character-sheet': 'character-sheet',
};

/** Runs one worker job inside its feature-named Langfuse trace. */
export async function traceJob(job: RemoteImageJob, run: () => Promise<void>): Promise<void> {
  const name = traceNames[job.kind];
  await startActiveObservation(name, (span) =>
    propagateAttributes(
      {
        traceName: name,
        userId: job.accountId,
        tags: [name],
        metadata: { jobId: job.id, jobKind: job.kind, attempt: String(job.attempts) },
      },
      async () => {
        span.update({ input: { jobKind: job.kind, payload: job.payload } });
        try {
          await run();
        } catch (error) {
          span.update({ level: 'ERROR', statusMessage: (error as Error).message });
          throw error;
        }
      },
    ),
  );
}

const usd = (microunits: number) => microunits / 1_000_000;

// Provider inputs mix JPEG and PNG, so sniff the PNG signature instead of trusting call sites.
function image(bytes: Uint8Array) {
  const contentType = bytes[0] === 0x89 && bytes[1] === 0x50 ? 'image/png' : 'image/jpeg';
  return new LangfuseMedia({ source: 'bytes', contentBytes: bytes, contentType });
}

function imageGenerationDetails(result: GenerationProviderResult, config: CatalogExecutionConfig) {
  const cost = calculateCostLedger(result.usage, config.pricing);
  return {
    output: { image: image(result.pngBytes) },
    usageDetails: {
      input_text: result.usage.textInputTokens,
      input_image: result.usage.imageInputTokens,
      output_image: result.usage.outputTokens,
    },
    costDetails: {
      input_text: usd(cost.textInputMicrounits),
      input_image: usd(cost.imageInputMicrounits),
      output_image: usd(cost.imageOutputMicrounits),
      total: usd(cost.totalMicrounits),
    },
    metadata: { requestId: result.requestId, serviceTier: result.usage.serviceTier },
  };
}

/**
 * Wraps a provider so every OpenAI call becomes a Langfuse generation nested
 * under the active job trace. Costs are ingested from the same pinned rate
 * card the credit ledger uses, so Langfuse and the database agree.
 */
export function traceProvider(
  provider: CatalogProvider,
  config: CatalogExecutionConfig,
): CatalogProvider {
  return {
    detect: (input) =>
      startActiveObservation(
        'detect-garments',
        async (generation) => {
          generation.update({ model: input.model, input: { photo: image(input.jpegBytes) } });
          const result = await provider.detect(input);
          const cost = calculateDetectionCostLedger(result.usage, config.detectionPricing);
          const { inputTokens, cachedInputTokens, cacheWriteInputTokens, outputTokens } = result.usage;
          generation.update({
            output: result.detections,
            // OpenAI's input count includes cached and cache-write tokens; Langfuse wants disjoint buckets.
            usageDetails: {
              input: inputTokens - cachedInputTokens - cacheWriteInputTokens,
              input_cached_tokens: cachedInputTokens,
              input_cache_write_tokens: cacheWriteInputTokens,
              output: outputTokens,
            },
            costDetails: {
              input: usd(cost.inputMicrounits),
              input_cached_tokens: usd(cost.cachedInputMicrounits),
              input_cache_write_tokens: usd(cost.cacheWriteInputMicrounits),
              output: usd(cost.outputMicrounits),
              total: usd(cost.totalMicrounits),
            },
            metadata: { requestId: result.requestId, reasoningTokens: result.usage.reasoningTokens },
          });
          return result;
        },
        { asType: 'generation' },
      ),
    generate: (input) =>
      startActiveObservation(
        'generate-shelf-image',
        async (generation) => {
          generation.update({
            model: input.model,
            modelParameters: { quality: input.quality, size: input.size },
            input: {
              reference: image(input.referenceJpeg),
              previousShelfImage: input.previousShelfImage && image(input.previousShelfImage),
              feedback: input.feedback,
              metadata: input.metadata,
              promptVersion: input.promptVersion,
            },
          });
          const result = await provider.generate(input);
          generation.update(imageGenerationDetails(result, config));
          return result;
        },
        { asType: 'generation' },
      ),
    planLook: (input) =>
      startActiveObservation(
        'plan-look',
        async (generation) => {
          const { signal: _signal, ...plan } = input;
          generation.update({ model: input.model, input: plan });
          const result = await provider.planLook(input);
          const cached = result.usage?.input_tokens_details?.cached_tokens ?? 0;
          generation.update({
            output: { itemIds: result.itemIds, concept: result.concept },
            // No pinned rate card for the planner: Langfuse infers cost from the model name.
            usageDetails: result.usage && {
              input: (result.usage.input_tokens ?? 0) - cached,
              input_cached_tokens: cached,
              output: result.usage.output_tokens ?? 0,
            },
            metadata: { requestId: result.requestId },
          });
          return result;
        },
        { asType: 'generation' },
      ),
    generateComposite: (input) =>
      startActiveObservation(
        'generate-feed-image',
        async (generation) => {
          generation.update({
            model: input.model,
            modelParameters: { quality: input.quality, size: input.size },
            input: {
              prompt: input.prompt,
              references: input.references.map((bytes) => image(bytes)),
            },
          });
          const result = await provider.generateComposite(input);
          generation.update(imageGenerationDetails(result, config));
          return result;
        },
        { asType: 'generation' },
      ),
  };
}

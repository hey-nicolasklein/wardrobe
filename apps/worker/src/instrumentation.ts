import { LangfuseSpanProcessor } from '@langfuse/otel';
import { NodeSDK } from '@opentelemetry/sdk-node';

// Langfuse tracing is opt-in: without keys the SDK never starts and every
// `@langfuse/tracing` call below stays a no-op. The processor reads
// LANGFUSE_PUBLIC_KEY, LANGFUSE_SECRET_KEY and LANGFUSE_BASE_URL itself.
const sdk = process.env.LANGFUSE_PUBLIC_KEY
  ? new NodeSDK({ spanProcessors: [new LangfuseSpanProcessor()] })
  : null;
sdk?.start();

/** Flushes pending traces. Call once on worker shutdown. */
export async function shutdownTracing(): Promise<void> {
  await sdk?.shutdown();
}

import { randomUUID } from 'node:crypto';

import { contractVersion } from '@form/contracts';
import {
  checkDependencies,
  claimJobs,
  completeJob,
  createDatabase,
  createPrivateObjectStorage,
  executeCatalogJob,
  failCatalogAttempt,
  failJob,
  ensurePrivateBucket,
  migrateDatabase,
  OpenAICatalogProvider,
  recoverExpiredLeases,
  renewJobLease,
  type CatalogJobError,
  type RemoteImageJob,
} from '@form/service';

import { readWorkerConfig } from './config.js';
import { SerialPoller } from './polling.js';

const config = readWorkerConfig();
const database = createDatabase(config);
const storage = createPrivateObjectStorage(config);
const workerId = `worker-${randomUUID()}`;
const provider = new OpenAICatalogProvider(config.OPENAI_API_KEY, config.OPENAI_API_BASE_URL);
const executionConfig = {
  requestTimeoutMs: config.OPENAI_REQUEST_TIMEOUT_MS,
  pricing: {
    effectiveDate: config.OPENAI_PRICING_EFFECTIVE_DATE,
    textInputMicrodollarsPerMillion:
      config.OPENAI_IMAGE_TEXT_INPUT_RATE_MICRODOLLARS_PER_MILLION,
    imageInputMicrodollarsPerMillion: config.OPENAI_IMAGE_INPUT_RATE_MICRODOLLARS_PER_MILLION,
    imageOutputMicrodollarsPerMillion: config.OPENAI_IMAGE_OUTPUT_RATE_MICRODOLLARS_PER_MILLION,
  },
};

await migrateDatabase(database);
await ensurePrivateBucket(storage);

const health = await checkDependencies(database, storage);
if (health.status !== 'ready') {
  throw new Error(`Worker dependencies are not ready: ${JSON.stringify(health)}`);
}

const recovered = await recoverExpiredLeases(database);
console.log(
  `FORM worker ${workerId} ready on contract v${contractVersion}; recovered ${recovered} expired lease(s).`,
);

const recoveryTimer = setInterval(() => {
  void recoverExpiredLeases(database).catch((error: unknown) => {
    console.error('Failed to recover expired job leases.', error);
  });
}, Math.max(config.REMOTE_IMAGE_LEASE_SECONDS * 500, 5_000));

let stopping = false;

async function processJob(job: RemoteImageJob): Promise<void> {
  const heartbeat = setInterval(() => {
    void renewJobLease(
      database,
      job.id,
      workerId,
      config.REMOTE_IMAGE_LEASE_SECONDS,
    ).catch((error: unknown) => console.error(`Failed to renew lease for job ${job.id}.`, error));
  }, Math.max(Math.floor((config.REMOTE_IMAGE_LEASE_SECONDS * 1_000) / 3), 1_000));
  try {
    await executeCatalogJob(database, storage, provider, job, executionConfig);
    if (!(await completeJob(database, job.id, workerId))) {
      console.error(`Job ${job.id} completed after its worker lease was lost.`);
    }
  } catch (error) {
    const catalogError = error as CatalogJobError;
    const outcome = await failJob(database, job.id, workerId, {
      retryable: catalogError.retryable === true,
      category: catalogError.category ?? 'internal',
      detail: catalogError.message,
      retryDelaySeconds: Math.min(60, 5 * 2 ** Math.max(0, job.attempts - 1)),
    });
    if (outcome === 'failed') {
      await failCatalogAttempt(database, job, catalogError);
    }
    if (outcome !== 'retried') {
      console.error(`Catalog job ${job.id} ${outcome}.`, catalogError);
    }
  } finally {
    clearInterval(heartbeat);
  }
}

async function poll(): Promise<void> {
  const jobs = await claimJobs(database, {
    workerId,
    limit: config.REMOTE_IMAGE_GLOBAL_CONCURRENCY,
    perAccountLimit: config.REMOTE_IMAGE_ACCOUNT_CONCURRENCY,
    leaseSeconds: config.REMOTE_IMAGE_LEASE_SECONDS,
  });
  await Promise.all(jobs.map(processJob));
}

const poller = new SerialPoller(poll, (error: unknown) => {
  console.error('Catalog worker poll failed.', error);
});

const pollTimer = setInterval(() => poller.start(), config.REMOTE_IMAGE_POLL_INTERVAL_MS);
poller.start();

async function stop(): Promise<void> {
  if (stopping) return;
  stopping = true;
  clearInterval(recoveryTimer);
  clearInterval(pollTimer);
  await poller.stop();
  storage.client.destroy();
  await database.end();
}

process.once('SIGINT', () => void stop());
process.once('SIGTERM', () => void stop());

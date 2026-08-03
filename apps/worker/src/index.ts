import { contractVersion } from '@form/contracts';
import {
  createDatabase,
  DurableJobQueue,
  loadLocalEnvironment,
  PrivateAssetStore,
  runMigrations,
  runQueueWorker,
} from '@form/service';

import { readWorkerConfig } from './config.js';

loadLocalEnvironment();
const config = readWorkerConfig();
const database = createDatabase(config.DATABASE_URL);
const assets = new PrivateAssetStore(database, config);
const abortController = new AbortController();

await runMigrations(database);
await assets.ensurePrivateBucket();

console.log(
  `FORM worker ready on contract v${contractVersion}; waiting for remote-image handlers.`,
);

function shutdown(): void {
  abortController.abort();
}

process.once('SIGINT', shutdown);
process.once('SIGTERM', shutdown);

await runQueueWorker({
  queue: new DurableJobQueue(database),
  workerId: config.WORKER_ID,
  handlers: {},
  globalConcurrency: config.REMOTE_IMAGE_GLOBAL_CONCURRENCY,
  perAccountConcurrency: config.REMOTE_IMAGE_ACCOUNT_CONCURRENCY,
  signal: abortController.signal,
});
await database.end();

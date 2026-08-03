import { randomUUID } from 'node:crypto';

import { contractVersion } from '@form/contracts';
import {
  checkDependencies,
  createDatabase,
  createPrivateObjectStorage,
  ensurePrivateBucket,
  migrateDatabase,
  recoverExpiredLeases,
} from '@form/service';

import { readWorkerConfig } from './config.js';

const config = readWorkerConfig();
const database = createDatabase(config);
const storage = createPrivateObjectStorage(config);
const workerId = `worker-${randomUUID()}`;

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
async function stop(): Promise<void> {
  if (stopping) return;
  stopping = true;
  clearInterval(recoveryTimer);
  storage.client.destroy();
  await database.end();
}

process.once('SIGINT', () => void stop());
process.once('SIGTERM', () => void stop());
